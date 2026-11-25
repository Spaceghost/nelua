---
layout: docs
title: Installing
permalink: /installing/
categories: docs toc
order: 1
---

{% raw %}

Build the Spaceghost fork of Nelua on Linux, macOS, or Windows.
{: .lead}

Building from source requires Git, Make, and a C compiler. Nelua includes
the Lua interpreter used by the compiler. A C compiler is also needed to
compile Nelua programs when using a prebuilt package.

## Prebuilt development builds

Download the archive for your machine from the
[latest development release](https://github.com/Spaceghost/nelua/releases/tag/latest).
The release offers packages for Linux x86-64 and AArch64, macOS arm64,
and Windows x86-64. Extract the archive and keep the launcher, bundled
interpreter, `lib`, and `lualib` together. From the extracted directory,
run `./nelua -v` on Unix or `./nelua.bat -v` on Windows to see the build
information. Use the source steps below to build a specific Git revision.

## Linux

Use your system's package manager to install all of the required tools first:

For example, on **Ubuntu** you should do:

```bash
sudo apt-get install build-essential git
```

While on **ArchLinux**, you should do:

```bash
sudo pacman -S base-devel git
```

## macOS

Install the Xcode Command Line Tools for Clang, Git, and Make.

```bash
xcode-select --install
```

## Windows

Install [MSYS2](https://www.msys2.org/) and open the **UCRT64** terminal.
Install the build tools and make sure the MinGW GCC is on your path.

```bash
pacman -Syu
pacman -S --needed make git mingw-w64-ucrt-x86_64-gcc
```

If MSYS2 asks you to close the terminal during the update, reopen UCRT64
and run `pacman -Syu` again before installing the packages.

## Clone and install

```bash
git clone https://github.com/Spaceghost/nelua.git
cd nelua
make
```

On Linux with Clang, use `make CC=clang` and pass `--cc clang` when running Nelua if GCC is unavailable.

Run `./nelua` directly on Linux or macOS and `./nelua.bat` in MSYS2. On Unix you
can also install Nelua in your user account.

```bash
make install PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

The default install prefix is `/usr/local`. Use `sudo make install` if you
want that system-wide location and it requires administrator privileges.
For a native Linux AArch64 build and packaging example, see the
[Fedora Incus guide](https://github.com/Spaceghost/nelua/blob/master/docs/arm64-fedora-incus.md).

## Testing

From the checkout root, run:

```bash
./nelua -v
./nelua examples/helloworld.nelua
make test
```

On Windows, use `./nelua.bat` for the first two commands. If you installed Nelua
to a directory on your `PATH`, you can invoke it as `nelua`.

The most interesting examples are perhaps the graphical ones,
such as `snakesdl.nelua` and `condots.nelua`.

To run the Snake SDL game demo, for example, you will need to have the SDL2 library installed.
Install it using your system's package manager and run the example:

```bash
# install SDL2 on MSYS2
pacman -S mingw-w64-ucrt-x86_64-SDL2
# install SDL2 on Ubuntu
sudo apt-get install libsdl2-dev
# run it from the checkout (use ./nelua.bat on Windows)
./nelua examples/snakesdl.nelua
```

<a href="/tutorial/" class="btn btn-outline-primary btn-lg float-right">Tutorial >></a>

{% endraw %}

## Editor support

Two editor grammars live in the repository and follow the fork syntax:

* `tools/tree-sitter-nelua`: a Tree-sitter grammar authored in Nelua
  (`grammar.nelua`) with corpus tests and highlight queries. It covers const
  pointers (`*const T`, `*const [0]cchar`, `*const *const T`), variant type
  expressions (`A|B`, `A|B|C`, `variant(A, B)`), anonymous `function`
  expressions and the optional syntax: the type suffix `T?` (`optional_type`,
  binding looser than `*`, `[N]` and tighter than `|`), the try suffix `expr?`
  (`try_expression`) and statement `f()?` (`try_statement`), the `orelse`
  operator (between comparison and `|`), `if local x = e then` /
  `elseif local` (`if_local`) and the `match` statement (`match_statement`
  with `match_local` for `case local x: T`; `match` stays an identifier in
  `s:match(p)`); `queries/highlights.scm` captures `orelse` as
  `@keyword.operator`, the `?` tokens as `@operator` and `match` as `@keyword`.
  The checked-in `src/parser.c` is generated from the compiler
  pin named in the tool README with Tree-sitter CLI 0.25.10 and parses the
  fork syntax; the corpus under `test/corpus` exercises it.
* `tools/textmate-nelua`: a TextMate grammar (`source.nelua`) for GitHub,
  VS Code and other TextMate consumers. `const` after `*` is a storage
  modifier and `|` inside a type context is the variant operator; `?` after a
  type name inside a type context is `keyword.operator.type.optional`, `?`
  after a name, a `)` or a `]` elsewhere (also after a method call such as
  `f:write(x)?`, whose `:` opened a type context) is the try suffix
  `keyword.operator.try` (so `variant(A, B)?` is scoped as try), `orelse` is
  `keyword.operator.orelse`, the `local` of `if local` / `elseif local` is
  wrapped in `meta.if-local` and a `match` not preceded by `.` or `:` whose
  line goes on to `do` or `case` is `keyword.control.match` (`s:match(p)`
  stays a method name). A type
  context is a line heuristic, not compiler parsing: it opens after any
  `name:` (a declaration, a `):` return type, but also a method call such as
  `obj:method(...)`) or after `@`, and closes at `=`, `,`, `;`, `<`, a closing
  bracket, a statement keyword such as `end` or `return`, or the end of the
  line; brackets inside stay balanced and keep the type rules, and strings or
  comments inside keep their own scope.
