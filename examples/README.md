# Nelua examples

Build Nelua with `make` from the repository root. Run an example from the same
directory with `./nelua examples/helloworld.nelua`. On Windows, use `./nelua.bat`.

| Try | Example |
| --- | --- |
| Basic syntax and programs | [Hello world](helloworld.nelua), [language overview](overview.nelua), [Fibonacci](fibonacci.nelua), [matrix multiplication](matmul.nelua) |
| Compile-time programming | [Configuration evaluation](comptime_config.nelua), [syntax extension tour](syntax_tour.nelua), [DSL embedding](dsl2.nelua) |
| C and freestanding | [C-hosted component](c_host/README.md), [no-CRT executable](freestanding/README.md) |
| Bend2 integration | [CPU and CUDA examples](bend2), [setup and usage](../docs/pages/syntax-extensions.md#embed-bend2) |
| Graphics with SDL2 | [Snake](snakesdl.nelua), [dots](condots.nelua), [SDL2 setup](../docs/pages/installing.md#testing) |
