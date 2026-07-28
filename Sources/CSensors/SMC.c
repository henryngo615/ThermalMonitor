#include "include/SMC.h"
#include <string.h>
#include <IOKit/IOKitLib.h>

#define SMC_INDEX      2
#define CMD_KEY_INFO   9
#define CMD_READ_BYTES 5
#define CMD_READ_INDEX 8

typedef struct { char a,b,c,d; unsigned short e; } SMCVer;
typedef struct { unsigned short a,b; unsigned int c,d,e; } SMCPLim;
typedef struct { unsigned int size, type; char attr; } SMCKInfo;
typedef struct {
    unsigned int   key;
    SMCVer         ver;
    SMCPLim        plim;
    SMCKInfo       kinfo;
    char           result, status, cmd;
    unsigned int   data32;
    unsigned char  bytes[32];
} SMCKD;

static io_connect_t g_conn = 0;

static unsigned int fcc(const char *s) {
    return (unsigned int)((unsigned char)s[0]<<24|(unsigned char)s[1]<<16|
                          (unsigned char)s[2]<<8 |(unsigned char)s[3]);
}
static void fcc_str(unsigned int v, char *s) {
    s[0]=(v>>24)&0xFF; s[1]=(v>>16)&0xFF; s[2]=(v>>8)&0xFF; s[3]=v&0xFF; s[4]=0;
}

int smc_open(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return 0;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    return r == KERN_SUCCESS ? 1 : 0;
}

static int call(SMCKD *in, SMCKD *out) {
    size_t sz = sizeof(SMCKD);
    return IOConnectCallStructMethod(g_conn, SMC_INDEX, in, sz, out, &sz) == KERN_SUCCESS
           && out->result == 0;
}

// A key's payload size and type never change while the connection is open, so they are
// looked up once. Without this every read costs two round trips into the SMC instead of
// one, which is the difference between ~32 ms and ~16 ms for a full sensor sweep.
// Sized past the number of temperature keys any current Mac exposes (~350), so the
// discovery sweep leaves every key the app goes on to poll already cached.
#define KEY_CACHE_MAX 1024
typedef struct { unsigned int key, size, type; } SMCKeyInfo;
static SMCKeyInfo g_key_cache[KEY_CACHE_MAX];
static int g_key_cache_count = 0;

static int key_info(unsigned int key, unsigned int *size, unsigned int *type) {
    for (int i = 0; i < g_key_cache_count; i++) {
        if (g_key_cache[i].key != key) continue;
        *size = g_key_cache[i].size;
        *type = g_key_cache[i].type;
        return 1;
    }

    SMCKD in={0}, out={0};
    in.key = key; in.cmd = CMD_KEY_INFO;
    if (!call(&in, &out)) return 0;
    *size = out.kinfo.size;
    *type = out.kinfo.type;

    if (g_key_cache_count < KEY_CACHE_MAX) {
        SMCKeyInfo *slot = &g_key_cache[g_key_cache_count++];
        slot->key = key; slot->size = *size; slot->type = *type;
    }
    return 1;
}

void smc_close(void) {
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
    g_key_cache_count = 0;
}

static double decode(SMCKD *out, unsigned int dt) {
    unsigned char *b = out->bytes;
    if (dt == fcc("flt ")) { float f; memcpy(&f,b,4); return (double)f; }
    if (dt == fcc("ioft")) { unsigned int r=b[0]<<24|b[1]<<16|b[2]<<8|b[3]; return r/65536.0; }
    if (dt == fcc("sp78")) { return ((short)(b[0]<<8|b[1]))/256.0; }
    if (dt == fcc("fpe2")) { return ((unsigned short)(b[0]<<8|b[1]))/4.0; }
    return -999;
}

double smc_read_temp(const char *key) {
    if (!g_conn) return -999;
    unsigned int k = fcc(key), ds, dt;
    if (!key_info(k, &ds, &dt)) return -999;

    SMCKD in={0}, out={0};
    in.key=k; in.kinfo.size=ds; in.cmd=CMD_READ_BYTES;
    if (!call(&in, &out)) return -999;
    return decode(&out, dt);
}

// Get total number of SMC keys
static unsigned int smc_key_count(void) {
    SMCKD in={0}, out={0};
    in.key = fcc("#KEY"); in.cmd = CMD_KEY_INFO;
    if (!call(&in, &out)) return 0;
    unsigned int ds = out.kinfo.size;
    in=(SMCKD){0}; out=(SMCKD){0};
    in.key=fcc("#KEY"); in.kinfo.size=ds; in.cmd=CMD_READ_BYTES;
    if (!call(&in, &out)) return 0;
    unsigned char *b = out.bytes;
    return (unsigned int)(b[0]<<24|b[1]<<16|b[2]<<8|b[3]);
}

static unsigned int key_at_index(unsigned int idx) {
    SMCKD in={0}, out={0};
    in.cmd = CMD_READ_INDEX; in.data32 = idx;
    size_t sz = sizeof(SMCKD);
    IOConnectCallStructMethod(g_conn, SMC_INDEX, &in, sz, &out, &sz);
    return out.key;
}

int smc_find_keys_with_prefix(char prefix, char (*out_keys)[5], int max_count) {
    if (!g_conn) return 0;
    unsigned int total = smc_key_count();
    int found = 0;
    for (unsigned int i = 0; i < total && found < max_count; i++) {
        unsigned int k = key_at_index(i);
        char ks[5]; fcc_str(k, ks);
        if (ks[0] != prefix) continue;
        double t = smc_read_temp(ks);
        if (t > 1.0 && t < 150.0) {
            memcpy(out_keys[found], ks, 5);
            found++;
        }
    }
    return found;
}
