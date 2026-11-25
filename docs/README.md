# Nelua documentation

## Use the compiler

- [Install or build Nelua](pages/installing.md), including [Linux AArch64 in Fedora Incus](arm64-fedora-incus.md).
- Learn with the [tutorial](pages/tutorial.md), [language overview](pages/overview.md),
  [standard library reference](pages/libraries.md), and [examples](../examples/README.md).
- See the [fork guide](pages/fork.md) and [project background](project-background.md)
  for the fork's scope and Nelua's original design goals.

## Work on a specific area

| Area | Guide |
| --- | --- |
| C interop | [C libraries](pages/clibraries.md), [bindgen](../tools/nelua-bindgen/README.md), [C-hosted and freestanding builds](pages/runtime-free.md) |
| Compiler extensions | [Compile-time evaluation](pages/comptime.md), [syntax extensions and Bend2](pages/syntax-extensions.md) |
| Editor integration | [Editor support](pages/installing.md#editor-support), [Tree-sitter](../tools/tree-sitter-nelua/README.md), [TextMate](../tools/textmate-nelua/README.md) |
| Design notes | [Optionals](design/optional-types.md), [native Lua tables](design/native-lua-tables.md), [typed Lua tables](design/typed-lua-tables.md) |

## Preview the documentation

The Jekyll source lives here. With Ruby and Bundler installed, run
`cd docs && bundle install` from the repository root, then run `make docs` from
the root to build the pages or `make docs-serve` to preview them locally.
