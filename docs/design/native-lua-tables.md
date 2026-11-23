# Native Lua-style tables (opt-in prototype)

`require 'luatable'` makes the native table types available to a Nelua program.
It adds no Lua VM or garbage collector, does not change the `table` type or
parser, and does not change code generation for programs that do not use it.

```nelua
require 'luatable'

local Small = @FixedLuaTable(2)
local t: Small
local alias: *Small = &t
local one = LuaKey.integer(1)
local text = LuaKey.string('1')
assert(t:set(one, LuaValue.boolean(false)))
assert(alias:set(text, LuaValue.integer(42)))
assert(t:get(one).kind == LuaValueKind.Boolean)
assert(not t:get(one):truthy())
assert(t:get(text).data.i == 42)
assert(t:set(one, (@LuaValue){}))
assert(t:get(one).kind == LuaValueKind.Nil)
```

Keys are signed 64-bit integers or byte strings; integer `1` and string `'1'`
are distinct. Values are tagged nil, booleans, signed 64-bit integers, 64-bit
floats, or byte strings. The zero value of `LuaValue` is nil. Read only the
union member matching the value's `kind`: `b`, `i`, `n`, or `s`.
Missing reads return nil and do not insert; setting nil deletes a key,
including when it was already absent. Only nil and false are falsey.
`len()` counts all live entries, not Lua's sequence length. No iteration
order, Lua literals or bracket assignments, metatables, arbitrary Lua types,
cycle collection, or thread safety are part of this prototype.

## Choose storage explicitly

- **`FixedLuaTable(N)`** has `N` inline slots and linear lookup. It needs no
  allocator and can live on the stack; prefer small `N`. A full table still
  allows replacement/deletion, but returns false on a new insertion. It
  borrows string bytes, which must stay alive and immutable while stored or
  until all outstanding reads are done. Copying the native record copies
  its slots; use a pointer if mutations should be shared.
- **`LuaTable(Allocator)`** has a growable open-addressed hash table with
  lazy allocation. Storage scales with populated slots and retained capacity,
  not the largest integer key. Deletions do not shrink capacity; `destroy()`
  releases it. Hashing is deterministic and not hardened against
  adversarial collisions. Bring an allocator supporting aligned `alloc`,
  zeroing `alloc0`, and `dealloc`, which must remain valid through cleanup.

```nelua
require 'luatable'
require 'allocators.general'

local Dynamic = @LuaTable(GeneralAllocator)
local t <close> = Dynamic.make(general_allocator)
assert(t:set(LuaKey.integer(9000000000), LuaValue.string('large key')))
```

The dynamic record is owned: share through pointers and use `move` to
transfer ownership. Use `<close>` at the owner declaration or call
`destroy()` manually. Do not use an alias after its owner is moved or leaves
scope. Insertions copy string keys and values, including binary strings.
`get` copies the tagged descriptor, not the bytes: a dynamic string result
is valid until that value is replaced/deleted or the table is destroyed.
Make an independent copy before keeping it beyond that boundary. Failed
allocation leaves existing entries unchanged. `set` returns false for an
invalid key, a full fixed table, or a failed dynamic insertion/replacement.

## Optimization boundary

No compiler pass, runtime initialization hook, or global allocator was added.
The fixed representation and inlinable operations let the existing C
optimizer eliminate a small, nonescaping fixed-key case. That is an
observable code-generation result for tested examples, not a guarantee for
every fixed table; escaping tables and runtime keys remain real data.
