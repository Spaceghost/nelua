/* Linux process ABI only. No libc, startup objects, or allocator. */
#include <stdint.h>
int nelua_typed_arena_check(uint64_t);
int64_t nelua_typed_fixed_roundtrip(int64_t);

__attribute__((noreturn, force_align_arg_pointer)) void _start(void)
{
    long code = nelua_typed_arena_check(0);
    if (!code)
        code = nelua_typed_arena_check(UINT64_MAX);
    if (!code && nelua_typed_fixed_roundtrip(INT64_MIN) != INT64_MIN)
        code = 6;
    __asm__ volatile("syscall" : : "a"(60L), "D"(code) : "rcx", "r11", "memory");
    __builtin_unreachable();
}
