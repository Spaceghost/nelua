# Nelua

![Nelua logo](docs/assets/img/nelua-logo-64px.png)

Nelua is a Lua-inspired systems programming language with static typing and
compile-time metaprogramming. It translates Nelua to C and uses a C compiler to
produce native code. The language is in alpha and still evolving.

This repository is the Spaceghost fork of [Eduardo Bart's Nelua](https://github.com/edubart/nelua-lang).
It adds optional types, variants and pattern matching, owned records, closures,
syntax extensions, and tools for C interop and freestanding builds.
See [what this fork adds](docs/pages/fork.md) for the upstream baseline and feature details.

[Project site](https://spacegho.st/nelua/) ·
[Download a development build](https://github.com/Spaceghost/nelua/releases/tag/latest) ·
[Installation guide](docs/pages/installing.md) ·
[Contributing](CONTRIBUTING.md)

## Quick start

With Git, Make, and a C compiler installed, build and run from the checkout.

```sh
git clone https://github.com/Spaceghost/nelua.git
cd nelua
make
./nelua examples/helloworld.nelua
```

On Windows, follow the [MSYS2 setup](docs/pages/installing.md#windows) and use
`./nelua.bat`. The [installation guide](docs/pages/installing.md) covers dependencies,
prebuilt packages, and installing outside the checkout. Build and package for
Linux AArch64 with the [Fedora Incus guide](docs/arm64-fedora-incus.md).

## Learn Nelua

- Start with the [tutorial](docs/pages/tutorial.md), [language overview](docs/pages/overview.md),
  and [standard library reference](docs/pages/libraries.md).
- Run programs from the [examples index](examples/README.md).
- Embed Nelua in C or build without its runtime using the [runtime-free guide](docs/pages/runtime-free.md).
- Extend the compiler with the [syntax extension guide](docs/pages/syntax-extensions.md)
  or [compile-time function evaluation](docs/pages/comptime.md).
- See the [documentation index](docs/README.md) for design notes, C bindings, and editor tooling.

## Develop

Run `make test` from the repository root. The [contributor guide](CONTRIBUTING.md)
maps the compiler, standard library, fixtures, and tooling and gives commands
for testing each area.

Use [this repository's issues](https://github.com/Spaceghost/nelua/issues) for fork-specific
bugs and proposals. For upstream questions, see the [upstream discussions](https://github.com/edubart/nelua-lang/discussions),
[Nelua Discord](https://discord.gg/7aaGeG7), and [Awesome Nelua](https://github.com/edubart/nelua-lang/wiki/Awesome-Nelua).
For security reports, see the [security policy](SECURITY.md).

## License

[MIT](LICENSE). Nelua was created by Eduardo Bart.
