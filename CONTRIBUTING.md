# Contributing to Nelua

Use [this repository's issues](https://github.com/Spaceghost/nelua/issues) for bugs and
proposals involving the Spaceghost fork. Search existing issues first and include the
output of `nelua -v`, your OS and architecture, your C compiler, and the smallest example
that reproduces the behavior. For large changes, open an issue to discuss the intended
behavior before writing a patch.

For upstream language questions, use [upstream discussions](https://github.com/edubart/nelua-lang/discussions)
or the [Nelua Discord](https://discord.gg/7aaGeG7). Use the
[security policy](SECURITY.md) for vulnerabilities.

## Build and test

```sh
make
make test
```

Run commands from the checkout root unless the tool's guide specifies another
directory. `make test-quick` stops at the first failure. On Windows, use the
[MSYS2 setup](docs/pages/installing.md#windows).

| Area | Where to work | How to verify |
| --- | --- | --- |
| Parser, semantic analysis, and code generation | [lualib/nelua](lualib/nelua), [spec](spec) | `make test` |
| Standard library | [lib](lib), [runtime fixtures](tests) | `./nelua tests/all_test.nelua` |
| C hosting and freestanding builds | [examples/c_host](examples/c_host), [examples/freestanding](examples/freestanding) | `python3 examples/c_host/check.py --sanitize` and `python3 examples/freestanding/check.py --sanitize` on x86-64 Linux |
| Bundled Lua interpreter and native dependencies | [src](src) | `make clean-nelualua`, then `make test` |
| Bindings and editor grammars | [tools](tools) | Follow the [bindgen](tools/nelua-bindgen/README.md), [Tree-sitter](tools/tree-sitter-nelua/README.md), and [TextMate](tools/textmate-nelua/README.md) guides |

The spec suite uses the bundled interpreter. `make check` requires LuaCheck.
`make coverage-test` requires LuaCov. Some example programs require extra C libraries.

Keep changes focused, follow the surrounding style, and include a regression spec
for behavior changes. Update the relevant [documentation](docs/README.md) when
changing public syntax, options, or APIs. Regenerate editor artifacts using their
documented tools and include the resulting files.

Exploratory and superseded work remains available on the
[`archive/` branches](https://github.com/Spaceghost/nelua/branches/all?query=archive%2F).
Those branches record their own state and context. Use `master` for a current build.
