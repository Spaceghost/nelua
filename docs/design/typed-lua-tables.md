# Typed Lua-style table facade (prototype)

Use this opt-in facade when one key type and one value type describe the data.
It uses the existing Nelua `hashmap` directly; buckets do not store dynamic
Lua key/value tags, and no Lua VM or new syntax is involved.

```nelua
require 'typedluatable'
require 'allocators.general'

local Flags = @TypedLuaTable(int64, boolean, GeneralAllocator)
local flags <close> = Flags.make(general_allocator)
assert(flags:set(92, false))      -- a present false value
assert(flags:get(92):has())
assert(not flags:get(92):get())
local p = flags:peek(92)          -- optional pointer, no insertion
assert(p:has() and not $p:get())
assert(flags:set(92, nil))        -- remove; an absent delete also succeeds
assert(flags:get(92) == nil)
```

- `TypedLuaTable(K,V,Allocator,Hash?,Equal?)` accepts copyable keys and values.
  The optional hash/equality functions use the ordinary hashmap contract;
  equal keys must have equal hashes. The facade defaults to a mixing hash for
  integer keys up to 64 bits, including structured IDs. This is not a keyed
  hash or a defense against deliberate collision attacks. Other key types
  use the regular hashmap hash. Supply a custom hash to override it, for
  example an identity cast to `usize` when integer keys are already well
  distributed. The default for raw `hashmap` remains unchanged.
- `get` returns an optional copy; `peek` returns a nullable reference without
  inserting and does not allocate. A reference is invalidated by successful
  growth, erasing its entry, or destruction; use it only while valid.
  `erase` reports whether an entry was removed. `len` counts live entries.
  Nelua's optional pointer value treats a null pointer as absent.
- `set` returns false when the two replacement buffers cannot be acquired.
  Prior entries, size, and references survive that failure. Successful
  growth temporarily needs both old and new buffers. This is the additive
  `hashmap:try_set` path; legacy indexing, rehash and reserve still have
  their previous panic-on-allocation-failure contracts.
- Strings and pointers are copied as descriptors, **not as owned bytes**.
  Caller-owned bytes must stay live; string key contents must remain
  immutable while indexed. Use `LuaTable` for heterogeneous keys/values
  or its owned-byte behavior. The typed table itself is owned, so use
  `<close>`, explicit `destroy()`, and pointer borrows instead of shallow
  copies. A stateful arena must be stored externally and passed by stable
  pointer/adapter; do not copy it into a movable hashmap record.

## Three different cost claims

1. An unused compile-time typed factory instantiation produces no extra
   instructions in the tested object, although generated C can contain
   harmless type declarations.
2. A fixed, local `FixedLuaTable(1)` round trip of an external scalar can
   optimize to the scalar itself, with no allocation or table code.
3. The growable typed facade really allocates at run time. Its fixed-arena
   test uses no heap, Lua runtime or CRT. It still performs bounded arena
   allocations, growth and hash lookups; exhaustion is an observable false
   result. This is Linux process ABI evidence, not a bare-metal hardware test.

Run `tests/typedluatable/check_freestanding.sh` on Linux x86-64 with
GCC/binutils to audit symbols and link and execute the no-CRT proof.
