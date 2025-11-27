<div align="center">

<img src="docs/assets/logo.svg" alt="PyOZ Logo" width="150">

# PyOZ

**Zig's power meets Python's simplicity.**

Build blazing-fast Python extensions with zero boilerplate and zero Python C API headaches.

[![GitHub Stars](https://img.shields.io/github/stars/dzonerzy/PyOZ?style=flat)](https://github.com/dzonerzy/PyOZ)
[![Python](https://img.shields.io/badge/python-3.8--3.13-blue)](https://www.python.org/)
[![Zig](https://img.shields.io/badge/zig-0.15+-orange)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[Documentation](https://pyoz.dev) | [Getting Started](https://pyoz.dev/quickstart/) | [Examples](https://pyoz.dev/examples/complete-module/)

</div>

---

## Quick Example

```zig
const pyoz = @import("PyOZ");

fn add(a: i64, b: i64) i64 {
    return a + b;
}

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .funcs = &.{
        pyoz.func("add", add, "Add two numbers"),
    },
});

pub export fn PyInit_mymodule() ?*pyoz.PyObject {
    return MyModule.init();
}
```

```python
import mymodule
print(mymodule.add(2, 3))  # 5
```

## Features

- **Declarative API** - Define modules, functions, and classes with simple struct literals
- **Automatic Type Conversion** - Zig types map naturally to Python types
- **Full Class Support** - Magic methods, operators, properties, inheritance
- **NumPy Integration** - Zero-copy array access
- **Error Handling** - Zig errors become Python exceptions
- **Type Stubs** - Automatic `.pyi` generation for IDE support
- **Simple Tooling** - `pyoz init`, `pyoz build`, `pyoz publish`

## Installation

```bash
# Download the latest release
# https://github.com/dzonerzy/PyOZ/releases

# Or build from source
git clone https://github.com/dzonerzy/PyOZ.git
cd PyOZ
zig build
```

## Getting Started

```bash
# Create a new project
pyoz init myproject
cd myproject

# Build and install for development
pyoz develop

# Test it
python -c "import myproject; print(myproject.add(1, 2))"
```

## Documentation

Full documentation available at **[pyoz.dev](https://pyoz.dev)**

- [Installation](https://pyoz.dev/installation/)
- [Quickstart](https://pyoz.dev/quickstart/)
- [Functions](https://pyoz.dev/guide/functions/)
- [Classes](https://pyoz.dev/guide/classes/)
- [NumPy Integration](https://pyoz.dev/guide/numpy/)
- [Error Handling](https://pyoz.dev/guide/errors/)
- [CLI Reference](https://pyoz.dev/cli/build/)

## Requirements

- Zig 0.15.0+
- Python 3.8 - 3.13

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or submit a PR.
