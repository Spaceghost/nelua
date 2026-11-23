#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

extern int64_t nelua_table_fixed(int64_t);
extern int64_t nelua_table_scalar(int64_t);

int main(void)
{
    int64_t x;
    while (scanf("%" SCNd64, &x) == 1) {
        int64_t got = nelua_table_fixed(x), expected = nelua_table_scalar(x);
        if (got != expected) {
            fprintf(stderr, "fixed mismatch at %" PRId64 ": %" PRId64 " != %" PRId64 "\n", x, got, expected);
            return 1;
        }
        printf("%" PRId64 "\n", got);
    }
    return ferror(stdin) ? 1 : 0;
}
