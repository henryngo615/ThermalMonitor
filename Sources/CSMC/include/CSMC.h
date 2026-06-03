#pragma once
#include <stdint.h>

int    smc_open(void);
void   smc_close(void);

// Read one key. Returns celsius, or -999 on failure.
double smc_read_temp(const char *key);

// Enumerate all SMC keys whose name starts with prefix into out_keys (null-terminated strings).
// Returns number found. out_keys must hold at least max_count * 5 bytes.
int    smc_find_keys_with_prefix(char prefix, char (*out_keys)[5], int max_count);
