# Nelua TextMate grammar

The generated grammar is [syntaxes/nelua.tmLanguage.json](syntaxes/nelua.tmLanguage.json).
Edit [grammar.lua](grammar.lua) to change highlighting rules. Build Nelua at the
repository root with `make`, then run the following from this directory.

```sh
../../nelua-lua generate.lua --generate
../../nelua-lua generate.lua --check
npm install --no-save --no-package-lock vscode-textmate@9.2.0 vscode-oniguruma@2.0.1
node test.cjs
```

See the [installation guide](../../docs/pages/installing.md#editor-support) for
syntax coverage and the [Linguist submission notes](LINGUIST_SUBMISSION.md) for
the GitHub highlighting work.
