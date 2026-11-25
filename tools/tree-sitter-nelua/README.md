# Nelua Tree-sitter grammar

Grammar rules follow the compiler's existing `syntaxdefs.lua`, pinned to
[`6a4246a99166c596e7fa9ed74c5e61866712bfc6`](https://github.com/Spaceghost/nelua/commit/6a4246a99166c596e7fa9ed74c5e61866712bfc6).
This is editor parsing/highlighting, not compiler validation or a language change.
The grammar graph and external scanner are maintained in Nelua, with generated C.
It matches arbitrary long-bracket string/comment/preprocessor delimiter levels;
short preprocessing bodies remain opaque Lua code, rather than Nelua statements.

Generate with Tree-sitter CLI 0.25.10, then generate the scanner using the pinned
fork and host compiler. The repository workflow checks the corpus, scanner ABI under sanitizers,
and generated output. Parser C and its headers are Tree-sitter outputs,
not a second maintained Nelua implementation. `grammar.nelua` generates a bounded
host tool that emits Tree-sitter's external JSON grammar schema. The tool uses
GNU C11, matching the fork's statement-expression output. Lua drives generation;
no JavaScript grammar DSL or hidden C bodies are maintained.

From the repository root, with Tree-sitter CLI 0.25.10 on your `PATH`:

```sh
git worktree add --detach ../nelua-grammar-pin 6a4246a99166c596e7fa9ed74c5e61866712bfc6
make -C ../nelua-grammar-pin
cd tools/tree-sitter-nelua
pinned_compiler="$(cd ../../../nelua-grammar-pin && pwd)"
"$pinned_compiler/nelua-lua" generate.lua --check "$pinned_compiler/nelua" "$(command -v tree-sitter)"
tree-sitter test
```

Use `--generate` in place of `--check` when updating generated files.
The [provenance manifest](PROVENANCE.txt) records input and output hashes.

## Fork syntax

`grammar.nelua` follows the fork's `syntaxdefs.lua` at the pin above for the
syntax added after the original `b0cbfdb` pin: const pointers (`*const T`,
`*const [0]cchar`, `*const *const T`; `const` after `*` is a keyword, elsewhere
it stays an ordinary identifier such as the `<const>` annotation or `x * const`),
variant types (`A|B`, `A|B|C`, `variant(A, B)`, nested in `function(...)` and
`variant(...)` arguments) wherever a type expression is accepted, and anonymous
`function(...) ... end` expressions. `test/corpus/fork-syntax.txt` and
`queries/highlights.scm` cover them. `src/` and `PROVENANCE.txt` are the
`generate.lua --generate` outputs for that pin with Tree-sitter CLI 0.25.10;
`tree-sitter generate` resolves `* const` through `pointer_type`'s precedence
and reported no unresolved conflict.

## Changing the compiler pin

The pin lives in three places and must move together, or CI fails at
`generate.lua`'s `wrong compiler pin` assertion: `pin` in `generate.lua`, the
`git worktree add --detach` line in `.github/workflows/tree-sitter-nelua.yml`,
and this README. The compiler directory handed to `generate.lua` must be a
checkout whose `git rev-parse HEAD` equals the pin. After the bump run
`generate.lua --generate`, `tree-sitter test`, and commit every changed file
under `src/` plus `PROVENANCE.txt`.

## Shape and ABI

The grammar follows the compiler's `syntaxdefs.lua` shapes: types are layered
like `typeexpr` (`|` outermost over unary types; a unary type is a `*`/`[n]`
prefixed simple type with at most one `?` suffix, so `T??` is an error), `T?`
inside generic arguments is an `optional_type` (dynamic precedence over
`try_expression`), and a call statement is a try-free chain ending in a call
(`call` / `TryStat <== call ?`), so `a?.b()` is an error as a statement and fine
as an expression. The compiler's keywords are reserved words (`local orelse = 1`
is an error); Tree-sitter emits reserved-word tables only at ABI 15, which is
why `generate.lua` passes `--abi 15` with `tree-sitter.json` and the parser needs
a Tree-sitter runtime of 0.25 or newer. `tree-sitter generate` warns about
conflicts that became unnecessary; keep the list in `grammar.nelua` warning-free.
