#!/bin/sh
# Linux/POSIX native table acceptance; run from a checkout with make-built Nelua.
# BASE_NELUA=/path/to/unmodified/nelua also checks cross-checkout generated C.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"
case_dir=tests/luatable
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir "$tmp/home"
export HOME="$tmp/home"
export XDG_CACHE_HOME="$tmp/cache"
export LC_ALL=C
cc=${CC:-cc}

printf 'local function run(x: int64): int64 <cexport, codename "ordinary"> return x + 1 end\n' >"$tmp/ordinary.nelua"
./nelua --print-code "$tmp/ordinary.nelua" >"$tmp/default.c"
if [ "${BASE_NELUA:-}" ]; then
  "$BASE_NELUA" --print-code "$tmp/ordinary.nelua" >"$tmp/base.c"
  cmp "$tmp/default.c" "$tmp/base.c"
fi
cp "$tmp/ordinary.nelua" "$tmp/body"
{ printf "require 'luatable'\n"; cat "$tmp/body"; } >"$tmp/ordinary.nelua"
./nelua --print-code "$tmp/ordinary.nelua" >"$tmp/unused.c"
cmp "$tmp/default.c" "$tmp/unused.c"

./nelua --print-code "$case_dir/fixed.nelua" >"$tmp/fixed.c"
./nelua --cc "$cc" -r -B -o "$tmp/fixed.o" "$case_dir/fixed.nelua"
nm -u "$tmp/fixed.o" >"$tmp/fixed.undefined"
test ! -s "$tmp/fixed.undefined"
# Verify the fixed boundary has no call/jump to a runtime or indirect dispatch.
# On x86 use disassembly so an in-object dispatch cannot evade the nm test.
case "$(uname -m)" in
  x86_64|i?86)
    objdump -d --disassemble=nelua_table_fixed "$tmp/fixed.o" >"$tmp/fixed.asm"
    grep -q '<nelua_table_fixed>:' "$tmp/fixed.asm"
    if grep -E '[[:space:]](callq?|jmpq?)[[:space:]]' "$tmp/fixed.asm"; then
      printf '%s\n' 'No helper calls/dispatch allowed in the optimized fixed probe.' >&2
      exit 1
    fi
    cat "$tmp/fixed.asm"
    ;;
esac
"$cc" -O2 "$case_dir/driver.c" "$tmp/fixed.o" -o "$tmp/driver"
printf '%s\n' 0 -7 41 123456789 9223372036854775806 >"$tmp/inputs"
"$tmp/driver" <"$tmp/inputs" >"$tmp/fixed.out"
cmp "$tmp/inputs" "$tmp/fixed.out"

./nelua-lua "$case_dir/reference.lua" >"$tmp/lua.out"
./nelua --cc "$cc" "$case_dir/dynamic.nelua" >"$tmp/native.out"
cmp "$tmp/lua.out" "$tmp/native.out"
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 \
  ./nelua --cc "$cc" -S "$case_dir/dynamic.nelua" >"$tmp/sanitized.out"
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 \
  ./nelua --cc "$cc" -S "$case_dir/edge.nelua"
cmp "$tmp/lua.out" "$tmp/sanitized.out"
printf '%s\n' 'PASS: unused C unchanged; fixed no runtime calls; native/ASan/UBSan with leak checking matches Lua transcript and fault-injection cleanup'
