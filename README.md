# PyOZ

**Python bindings for Zig** - Write Python extension modules in pure Zig with zero boilerplate.

PyOZ is the Zig equivalent of [PyO3](https://pyo3.rs/) for Rust. It automatically handles all Python/Zig interop, letting you write natural Zig code that "just works" from Python.

## Features

- **Zero boilerplate** - Write normal Zig functions, PyOZ handles the rest
- **Automatic type conversion** - Python ↔ Zig types converted automatically
- **Full class support** - Structs become Python classes with all magic methods
- **Tiny binaries** - ~500KB stripped release builds
- **Fast compilation** - Zig's speed, not Rust's compile times
- **Comprehensive Python protocol support** - Iterators, sequences, mappings, buffers, descriptors, context managers, and more

## Quick Start

### Installation

**Pre-built binaries** (recommended):

Download the latest release for your platform from [GitHub Releases](https://github.com/dzonerzy/PyOZ/releases):

| Platform | Binary |
|----------|--------|
| Linux x86_64 | `pyoz-x86_64-linux` |
| Linux ARM64 | `pyoz-aarch64-linux` |
| macOS x86_64 | `pyoz-x86_64-macos` |
| macOS ARM64 (Apple Silicon) | `pyoz-aarch64-macos` |
| Windows x86_64 | `pyoz-x86_64-windows.exe` |
| Windows ARM64 | `pyoz-aarch64-windows.exe` |

```bash
# Example for Linux x86_64
curl -LO https://github.com/dzonerzy/PyOZ/releases/latest/download/pyoz-x86_64-linux
chmod +x pyoz-x86_64-linux
sudo mv pyoz-x86_64-linux /usr/local/bin/pyoz
```

**Build from source**:

```bash
git clone https://github.com/dzonerzy/PyOZ.git
cd PyOZ
zig build cli -Doptimize=ReleaseFast

# Add to PATH
export PATH="$PATH:$(pwd)/zig-out/bin"
```

### Create a New Project

```bash
pyoz init mymodule
cd mymodule
pyoz build
pip install dist/*.whl
```

### Write Your First Module

Edit `src/lib.zig`:

```zig
const pyoz = @import("PyOZ");

// Just write normal Zig functions!
fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn greet(name: []const u8) []const u8 {
    _ = name;
    return "Hello from Zig!";
}

// Define the module
const MyModule = pyoz.module(.{
    .name = "mymodule",
    .funcs = &.{
        pyoz.func("add", add, "Add two integers"),
        pyoz.func("greet", greet, "Greet someone"),
    },
});

pub export fn PyInit_mymodule() ?*pyoz.PyObject {
    return MyModule.init();
}
```

Use from Python:

```python
import mymodule

print(mymodule.add(2, 3))      # 5
print(mymodule.greet("World")) # Hello from Zig!
```

## Type Conversions

PyOZ automatically converts between Python and Zig types:

| Python | Zig |
|--------|-----|
| `int` | `i8`, `i16`, `i32`, `i64`, `i128`, `u8`, `u16`, `u32`, `u64`, `u128` |
| `float` | `f32`, `f64` |
| `bool` | `bool` |
| `str` | `[]const u8` |
| `bytes` | `pyoz.Bytes` |
| `list` | `[]const T`, `pyoz.ListView(T)` |
| `dict` | `pyoz.DictView(K, V)`, `pyoz.Dict(K, V)` |
| `set` | `pyoz.SetView(T)`, `pyoz.Set(T)` |
| `frozenset` | `pyoz.FrozenSet(T)` |
| `tuple` | Zig tuple structs |
| `None` | `?T` (optional) |
| `complex` | `pyoz.Complex` |
| `datetime` | `pyoz.DateTime`, `pyoz.Date`, `pyoz.Time`, `pyoz.TimeDelta` |
| `Decimal` | `pyoz.Decimal` |
| `pathlib.Path` | `pyoz.Path` |

## Classes

Define Python classes using Zig structs:

```zig
const Point = struct {
    x: f64,
    y: f64,

    // Instance method (takes *const Self or *Self)
    pub fn magnitude(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    // Static method (no self parameter)
    pub fn origin() Point {
        return .{ .x = 0, .y = 0 };
    }

    // Class method (takes comptime cls: type)
    pub fn from_polar(comptime cls: type, r: f64, theta: f64) Point {
        _ = cls;
        return .{ .x = r * @cos(theta), .y = r * @sin(theta) };
    }

    // Magic methods
    pub fn __repr__(self: *const Point) []const u8 {
        return "Point(...)";
    }

    pub fn __add__(self: *const Point, other: *const Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn __eq__(self: *const Point, other: *const Point) bool {
        return self.x == other.x and self.y == other.y;
    }
};

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .classes = &.{
        pyoz.class("Point", Point),
    },
});
```

Python usage:

```python
from mymodule import Point

p1 = Point(3.0, 4.0)
print(p1.x, p1.y)        # 3.0 4.0
print(p1.magnitude())    # 5.0

p2 = Point.origin()      # Static method
p3 = Point.from_polar(1.0, 0.0)  # Class method

print(p1 + p2)           # Point addition
print(p1 == Point(3.0, 4.0))  # True
```

## Supported Magic Methods

PyOZ supports the full range of Python magic methods:

### Object Protocol
- `__new__`, `__init__`, `__del__`
- `__repr__`, `__str__`, `__hash__`
- `__doc__` (class and method docstrings)

### Comparison
- `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`

### Numeric Operations
- `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`, `__mod__`, `__divmod__`, `__pow__`
- `__neg__`, `__pos__`, `__abs__`, `__invert__`
- `__and__`, `__or__`, `__xor__`, `__lshift__`, `__rshift__`
- `__int__`, `__float__`, `__bool__`, `__index__`, `__complex__`
- In-place: `__iadd__`, `__isub__`, `__imul__`, etc.
- Reflected: `__radd__`, `__rsub__`, `__rmul__`, etc.

### Sequences & Mappings
- `__len__`, `__getitem__`, `__setitem__`, `__delitem__`, `__contains__`
- `__iter__`, `__next__`, `__reversed__`

### Context Managers
- `__enter__`, `__exit__`

### Callable Objects
- `__call__`

### Attribute Access
- `__getattr__`, `__setattr__`, `__delattr__`

### Descriptors
- `__get__`, `__set__`, `__delete__`

### Buffer Protocol
- `__buffer__` (for numpy compatibility)

### GC Support
- `__traverse__`, `__clear__`

## Computed Properties

Define computed properties with `get_X` and `set_X`:

```zig
const Point = struct {
    x: f64,
    y: f64,

    // Read-only computed property
    pub fn get_length(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    // With setter (read-write property)
    pub fn set_length(self: *Point, new_length: f64) void {
        const current = self.get_length();
        if (current > 0) {
            const factor = new_length / current;
            self.x *= factor;
            self.y *= factor;
        }
    }
};
```

```python
p = Point(3.0, 4.0)
print(p.length)  # 5.0 (computed)
p.length = 10.0  # scales point
print(p.x, p.y)  # 6.0 8.0
```

## Error Handling

Zig errors are automatically converted to Python exceptions:

```zig
fn divide(a: f64, b: f64) !f64 {
    if (b == 0.0) return error.DivisionByZero;
    return a / b;
}
```

```python
divide(1.0, 0.0)  # Raises RuntimeError: DivisionByZero
```

### Custom Exceptions

```zig
const MyModule = pyoz.module(.{
    .name = "mymodule",
    .exceptions = &.{
        pyoz.exception("ValidationError", "Validation failed"),
    },
    .funcs = &.{ ... },
});

fn validate(n: i64) ?i64 {
    if (n < 0) {
        MyModule.getException(0).raise("Value must be positive");
        return null;
    }
    return n;
}
```

## GIL Control

Release the GIL for CPU-intensive operations:

```zig
fn heavy_computation(n: i64) i64 {
    // Release GIL - other Python threads can run
    const gil = pyoz.releaseGIL();
    defer gil.acquire();

    // Do expensive work without GIL
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        sum += i * i;
    }
    return sum;
}
```

## CLI Commands

```bash
pyoz init <name>       # Create new project
pyoz init <name> -l <path>  # Use local PyOZ path (for development)
pyoz build             # Build in debug mode
pyoz build --release   # Build in release mode
pyoz develop           # Install in development mode (symlink)
pyoz publish           # Publish to PyPI
pyoz --version         # Show version
```

## Project Configuration

Configure your project in `pyproject.toml`:

```toml
[project]
name = "mymodule"
version = "0.1.0"
description = "My awesome Zig-powered Python module"

[tool.pyoz]
module-path = "src/lib.zig"
# optimize = "ReleaseFast"  # ReleaseFast, ReleaseSmall, ReleaseSafe, Debug
# strip = true
```

## Building from Source

```bash
git clone https://github.com/dzonerzy/PyOZ.git
cd PyOZ

# Enable git hooks (validates version tags)
git config core.hooksPath .githooks

# Build CLI
zig build cli

# Build example module
zig build example

# Run tests
zig build test

# Cross-compile for all platforms
zig build release
```

## Releasing

PyOZ uses a pre-push hook to ensure version tags match `src/version.zig`:

1. Update `src/version.zig` with the new version
2. Commit: `git commit -am "Bump version to X.Y.Z"`
3. Tag: `git tag vX.Y.Z`
4. Push: `git push && git push --tags`

If the tag doesn't match `version.zig`, the push will be blocked.

## Requirements

- **Zig 0.15.2** (required)
- Python 3.8+
- python3-config (for header detection)

## Comparison with PyO3

| Feature | PyOZ | PyO3 |
|---------|------|------|
| Language | Zig | Rust |
| Binary size | ~8KB (module) / ~500KB (CLI) | ~100KB+ |
| Compile time | Fast | Slow |
| All magic methods | ✅ | ✅ |
| Static/class methods | ✅ | ✅ |
| Context managers | ✅ | ✅ |
| Buffer protocol | ✅ | ✅ |
| GIL control | ✅ | ✅ |
| Async/await | ❌ | ✅ |
| abi3 (stable ABI) | ❌ | ✅ |
| Maturity | New | Battle-tested |

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.
