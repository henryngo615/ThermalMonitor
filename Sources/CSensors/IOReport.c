#include "include/IOReport.h"
#include <dlfcn.h>
#include <stdlib.h>

typedef CFMutableDictionaryRef (*fn_copy_channels)(CFStringRef group, CFStringRef subgroup,
                                                   uint64_t a, uint64_t b, uint64_t c);
typedef void (*fn_merge)(CFMutableDictionaryRef into, CFMutableDictionaryRef from, CFTypeRef opts);
typedef CFTypeRef (*fn_subscribe)(void *unused, CFMutableDictionaryRef desired,
                                  CFMutableDictionaryRef *subscribed, uint64_t id, CFTypeRef opts);
typedef CFDictionaryRef (*fn_samples)(CFTypeRef sub, CFMutableDictionaryRef channels, CFTypeRef opts);
typedef CFDictionaryRef (*fn_delta)(CFDictionaryRef prev, CFDictionaryRef cur, CFTypeRef opts);
typedef CFStringRef (*fn_chan_str)(CFDictionaryRef channel);
typedef int32_t (*fn_chan_i32)(CFDictionaryRef channel);
typedef CFStringRef (*fn_idx_str)(CFDictionaryRef channel, int32_t index);
typedef int64_t (*fn_idx_i64)(CFDictionaryRef channel, int32_t index);
// The second argument is an optional out-pointer, not an index — passing an
// integer here dereferences it and crashes.
typedef int64_t (*fn_simple)(CFDictionaryRef channel, void *unused);

static fn_copy_channels sCopyChannels;
static fn_merge         sMerge;
static fn_subscribe     sSubscribe;
static fn_samples       sSamples;
static fn_delta         sDelta;
static fn_chan_str      sGroup, sSubGroup, sName, sUnit;
static fn_chan_i32      sFormat, sStateCount;
static fn_idx_str       sStateName;
static fn_idx_i64       sStateResidency;
static fn_simple        sSimpleValue;

typedef struct {
    CFTypeRef              subscription;
    CFMutableDictionaryRef channels;
} IORepHandle;

int iorep_available(void) {
    static int resolved = -1;
    if (resolved >= 0) return resolved;

    void *lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY);
    if (!lib) { resolved = 0; return 0; }

    sCopyChannels   = (fn_copy_channels)dlsym(lib, "IOReportCopyChannelsInGroup");
    sMerge          = (fn_merge)        dlsym(lib, "IOReportMergeChannels");
    sSubscribe      = (fn_subscribe)    dlsym(lib, "IOReportCreateSubscription");
    sSamples        = (fn_samples)      dlsym(lib, "IOReportCreateSamples");
    sDelta          = (fn_delta)        dlsym(lib, "IOReportCreateSamplesDelta");
    sGroup          = (fn_chan_str)     dlsym(lib, "IOReportChannelGetGroup");
    sSubGroup       = (fn_chan_str)     dlsym(lib, "IOReportChannelGetSubGroup");
    sName           = (fn_chan_str)     dlsym(lib, "IOReportChannelGetChannelName");
    sUnit           = (fn_chan_str)     dlsym(lib, "IOReportChannelGetUnitLabel");
    sFormat         = (fn_chan_i32)     dlsym(lib, "IOReportChannelGetFormat");
    sStateCount     = (fn_chan_i32)     dlsym(lib, "IOReportStateGetCount");
    sStateName      = (fn_idx_str)      dlsym(lib, "IOReportStateGetNameForIndex");
    sStateResidency = (fn_idx_i64)      dlsym(lib, "IOReportStateGetResidency");
    sSimpleValue    = (fn_simple)       dlsym(lib, "IOReportSimpleGetIntegerValue");

    resolved = sCopyChannels && sMerge && sSubscribe && sSamples && sDelta &&
               sGroup && sSubGroup && sName && sUnit && sFormat &&
               sStateCount && sStateName && sStateResidency && sSimpleValue;
    return resolved;
}

static void merge_group(CFMutableDictionaryRef into, CFStringRef group, CFStringRef subgroup) {
    CFMutableDictionaryRef extra = sCopyChannels(group, subgroup, 0, 0, 0);
    if (!extra) return;
    sMerge(into, extra, NULL);
    CFRelease(extra);
}

void *iorep_subscribe(void) {
    if (!iorep_available()) return NULL;

    // "Energy Model" carries the per-block energy counters (CPU/GPU/ANE/DRAM) and the
    // GPU group carries its performance-state residencies. The matching CPU group is
    // deliberately not subscribed: see ProcessorLoad for why its per-core channels
    // cannot be used for utilization.
    CFMutableDictionaryRef desired = sCopyChannels(CFSTR("Energy Model"), NULL, 0, 0, 0);
    if (!desired) return NULL;
    merge_group(desired, CFSTR("GPU Stats"), CFSTR("GPU Performance States"));

    CFMutableDictionaryRef subscribed = NULL;
    CFTypeRef sub = sSubscribe(NULL, desired, &subscribed, 0, NULL);
    CFRelease(desired);
    if (!sub || !subscribed) {
        if (sub) CFRelease(sub);
        if (subscribed) CFRelease(subscribed);
        return NULL;
    }

    IORepHandle *handle = malloc(sizeof(IORepHandle));
    if (!handle) { CFRelease(sub); CFRelease(subscribed); return NULL; }
    handle->subscription = sub;
    handle->channels = subscribed;
    return handle;
}

void iorep_release(void *handle) {
    IORepHandle *h = (IORepHandle *)handle;
    if (!h) return;
    if (h->subscription) CFRelease(h->subscription);
    if (h->channels) CFRelease(h->channels);
    free(h);
}

CFDictionaryRef iorep_sample(void *handle) {
    IORepHandle *h = (IORepHandle *)handle;
    if (!h || !sSamples) return NULL;
    return sSamples(h->subscription, h->channels, NULL);
}

CFDictionaryRef iorep_delta(CFDictionaryRef previous, CFDictionaryRef current) {
    if (!previous || !current || !sDelta) return NULL;
    return sDelta(previous, current, NULL);
}

CFArrayRef iorep_channels(CFDictionaryRef sample) {
    if (!sample) return NULL;
    return (CFArrayRef)CFDictionaryGetValue(sample, CFSTR("IOReportChannels"));
}

CFStringRef iorep_channel_group(CFDictionaryRef channel)    { return channel ? sGroup(channel) : NULL; }
CFStringRef iorep_channel_subgroup(CFDictionaryRef channel) { return channel ? sSubGroup(channel) : NULL; }
CFStringRef iorep_channel_name(CFDictionaryRef channel)     { return channel ? sName(channel) : NULL; }
CFStringRef iorep_channel_unit(CFDictionaryRef channel)     { return channel ? sUnit(channel) : NULL; }
int32_t     iorep_channel_format(CFDictionaryRef channel)   { return channel ? sFormat(channel) : 0; }
int64_t     iorep_simple_value(CFDictionaryRef channel)     { return channel ? sSimpleValue(channel, NULL) : 0; }
int32_t     iorep_state_count(CFDictionaryRef channel)      { return channel ? sStateCount(channel) : 0; }

CFStringRef iorep_state_name(CFDictionaryRef channel, int32_t index) {
    return channel ? sStateName(channel, index) : NULL;
}

int64_t iorep_state_residency(CFDictionaryRef channel, int32_t index) {
    return channel ? sStateResidency(channel, index) : 0;
}
