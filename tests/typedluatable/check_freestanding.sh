#!/bin/sh
# Linux x86-64 with GCC/binutils; intentionally not a portable CI gate.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cc=${CC:-gcc}

./nelua -r --print-code --cache-dir "$tmp/cache" tests/typedluatable/comptime.nelua >"$tmp/plain.c"
./nelua -r --print-code --cache-dir "$tmp/cache" -D typed_comptime=true tests/typedluatable/comptime.nelua >"$tmp/comptime.c"
$cc -Os -c "$tmp/plain.c" -o "$tmp/plain.o"
$cc -Os -c "$tmp/comptime.c" -o "$tmp/comptime.o"
objcopy -O binary --only-section=.text "$tmp/plain.o" "$tmp/plain.text"
objcopy -O binary --only-section=.text "$tmp/comptime.o" "$tmp/comptime.text"
cmp "$tmp/plain.text" "$tmp/comptime.text"
test -z "$(nm -u "$tmp/comptime.o")"

./nelua -r --print-code --cache-dir "$tmp/cache" tests/typedluatable/arena.nelua >"$tmp/arena.c"
flags='-std=c11 -Os -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector'
$cc $flags -c "$tmp/arena.c" -o "$tmp/arena.o"
test -z "$(nm -u "$tmp/arena.o")"
test "$(nm -g --defined-only "$tmp/arena.o" | awk '{print $3}' | sort)" = "nelua_typed_arena_check
nelua_typed_fixed_roundtrip"

asm=$(objdump -dr --disassemble=nelua_typed_fixed_roundtrip "$tmp/arena.o")
printf '%s\n' "$asm"
! printf '%s\n' "$asm" | grep -Eq 'call|R_X86_64|\(%rsp\)|\(%rbp\)'
$cc $flags -static -fno-pie -nostdlib -Wl,-e,_start "$tmp/arena.c"    tests/typedluatable/start_linux_x86_64.c -o "$tmp/no-crt"
test -z "$(nm -u "$tmp/no-crt")"
! readelf -l "$tmp/no-crt" | grep -q INTERP
! readelf -d "$tmp/no-crt" | grep -Eq '\((NEEDED|INIT|INIT_ARRAY)\)'
"$tmp/no-crt"
echo 'PASS: unused comptime instantiation eliminated; fixed scalar roundtrip; runtime arena grows, reports exhaustion and preserves data; no-CRT Linux execution'
