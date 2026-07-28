#pragma once
#include <CoreFoundation/CoreFoundation.h>

// Thin wrapper over /usr/lib/libIOReport.dylib, which is what powermetrics itself
// reads. Unlike powermetrics it needs no elevated privileges, so the app can sample
// energy counters and DVFS state residencies as a normal user.
//
// The symbols are private, so they are resolved lazily with dlsym and every entry
// point degrades to a null/zero result if the resolve fails.

// Resolves the library. Returns 1 if all required symbols were found.
int iorep_available(void);

// Subscribes to the energy + CPU/GPU performance-state channels.
// Returns an opaque handle, or NULL. Free with iorep_release.
void *iorep_subscribe(void);
void  iorep_release(void *handle);

// Counter snapshot. Caller owns the result.
CF_RETURNS_RETAINED CFDictionaryRef iorep_sample(void *handle);
// Per-channel difference between two snapshots. Caller owns the result.
CF_RETURNS_RETAINED CFDictionaryRef iorep_delta(CFDictionaryRef previous, CFDictionaryRef current);

// The channel array inside a sample/delta. Borrowed, valid while the sample is.
CF_RETURNS_NOT_RETAINED CFArrayRef iorep_channels(CFDictionaryRef sample);

// Channel accessors. `format` is 1 for a simple counter and 2 for state residencies.
CF_RETURNS_NOT_RETAINED CFStringRef iorep_channel_group(CFDictionaryRef channel);
CF_RETURNS_NOT_RETAINED CFStringRef iorep_channel_subgroup(CFDictionaryRef channel);
CF_RETURNS_NOT_RETAINED CFStringRef iorep_channel_name(CFDictionaryRef channel);
CF_RETURNS_NOT_RETAINED CFStringRef iorep_channel_unit(CFDictionaryRef channel);
int32_t iorep_channel_format(CFDictionaryRef channel);

int64_t iorep_simple_value(CFDictionaryRef channel);
int32_t iorep_state_count(CFDictionaryRef channel);
CF_RETURNS_NOT_RETAINED CFStringRef iorep_state_name(CFDictionaryRef channel, int32_t index);
int64_t iorep_state_residency(CFDictionaryRef channel, int32_t index);
