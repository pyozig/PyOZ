# PyOZ

**Python bindings for Zig** - Write Python extension modules in pure Zig with zero boilerplate.

PyOZ is the Zig equivalent of [PyO3](https://pyo3.rs/) for Rust. It automatically handles all Python/Zig interop, letting you write natural Zig code that "just works" from Python.

## Features

- **Zero boilerplate** - Write normal Zig functions, PyOZ handles the rest
- **Automatic type conversion** - Python ↔ Zig types converted automatically
- **Full class support** - Structs become Python classes with all magic methods
- **Tiny binaries** - ~8KB modules (ReleaseSmall + strip), ~500KB CLI
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
| any iterable | `pyoz.IteratorView(T)` |
| `tuple` | Zig tuple structs |
| `None` | `?T` (optional) |
| `complex` | `pyoz.Complex` |
| `datetime` | `pyoz.DateTime`, `pyoz.Date`, `pyoz.Time`, `pyoz.TimeDelta` |
| `Decimal` | `pyoz.Decimal` |
| `pathlib.Path` | `pyoz.Path` |
| `numpy.ndarray` | `pyoz.BufferView(T)`, `pyoz.BufferViewMut(T)` |

## NumPy Arrays (Zero-Copy)

PyOZ provides zero-copy access to numpy arrays via the Python buffer protocol. This lets you pass numpy arrays directly to Zig functions without copying data.

### Basic Usage

```zig
const pyoz = @import("PyOZ");

// Read-only access to numpy array
fn sum_array(arr: pyoz.BufferView(f64)) f64 {
    var total: f64 = 0;
    for (arr.data) |v| {
        total += v;
    }
    return total;
}

// Mutable (in-place) access
fn scale_array(arr: pyoz.BufferViewMut(f64), factor: f64) void {
    for (arr.data) |*v| {
        v.* *= factor;
    }
}

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .funcs = &.{
        pyoz.func("sum_array", sum_array, "Sum array elements"),
        pyoz.func("scale_array", scale_array, "Scale array in-place"),
    },
});
```

Python usage:

```python
import numpy as np
import mymodule

arr = np.array([1.0, 2.0, 3.0, 4.0, 5.0], dtype=np.float64)
print(mymodule.sum_array(arr))  # 15.0

mymodule.scale_array(arr, 2.0)
print(arr)  # [2. 4. 6. 8. 10.] - modified in-place!
```

### Supported Element Types

| NumPy dtype | Zig type |
|-------------|----------|
| `float64` | `f64` |
| `float32` | `f32` |
| `int64` | `i64` |
| `int32` | `i32` |
| `int16` | `i16` |
| `int8` | `i8` |
| `uint64` | `u64` |
| `uint32` | `u32` |
| `uint16` | `u16` |
| `uint8` | `u8` |
| `complex128` | `pyoz.Complex` |
| `complex64` | `pyoz.Complex32` |

### BufferView API

```zig
// Read-only view
const view: pyoz.BufferView(f64) = ...;
view.data          // []const f64 - direct slice access
view.len()         // number of elements
view.ndim          // number of dimensions
view.shape         // array shape
view.rows()        // rows (for 2D arrays)
view.cols()        // columns (for 2D arrays)
view.get(i)        // get element at index
view.get2D(r, c)   // get element at row, col
view.isEmpty()     // true if empty
view.isContiguous()// true if C or F contiguous

// Mutable view (same API plus):
const mut_view: pyoz.BufferViewMut(f64) = ...;
mut_view.data      // []f64 - mutable slice
mut_view.set(i, v) // set element at index
mut_view.set2D(r, c, v) // set element at row, col
mut_view.fill(v)   // fill with value
```

### Complex Numbers

```zig
fn process_complex(arr: pyoz.BufferView(pyoz.Complex)) pyoz.Complex {
    var sum = pyoz.Complex.init(0, 0);
    for (arr.data) |c| {
        sum = sum.add(c);
    }
    return sum;
}

fn conjugate_inplace(arr: pyoz.BufferViewMut(pyoz.Complex)) void {
    for (arr.data) |*c| {
        c.* = c.conjugate();
    }
}
```

```python
arr = np.array([1+2j, 3+4j], dtype=np.complex128)
result = mymodule.process_complex(arr)  # (4+6j)

mymodule.conjugate_inplace(arr)
print(arr)  # [1.-2.j 3.-4.j]
```

### Raising Exceptions

Use optional return types with `PyErr_SetString` to raise Python exceptions:

```zig
/// Returns ?T (optional) to allow raising exceptions:
///   - return value  -> Python receives the value
///   - return null   -> Check PyErr_Occurred(), raise if set, else return None
fn safe_dot(a: pyoz.BufferView(f64), b: pyoz.BufferView(f64)) ?f64 {
    if (a.len() != b.len()) {
        pyoz.py.PyErr_SetString(pyoz.py.PyExc_ValueError(), "Arrays must have same length");
        return null;  // This triggers the exception
    }
    var result: f64 = 0;
    for (a.data, b.data) |x, y| {
        result += x * y;
    }
    return result;
}
```

### What's Supported

| Feature | Status | Notes |
|---------|--------|-------|
| C-contiguous arrays | ✅ | Default numpy layout |
| Fortran-contiguous arrays | ✅ | Column-major order |
| 1D arrays | ✅ | Full support |
| 2D arrays | ✅ | With `rows()`, `cols()`, `get2D()` |
| Complex numbers | ✅ | `complex64` and `complex128` |
| Read-only access | ✅ | `BufferView(T)` |
| Mutable access | ✅ | `BufferViewMut(T)` |
| Zero-copy | ✅ | No data copying |

### What's NOT Supported (and Why)

| Feature | Reason |
|---------|--------|
| Non-contiguous arrays (e.g., `arr[::2]`) | **Medium effort, low value.** Would require stride-based iteration instead of direct slice access, slowing down all operations. Workaround: use `.copy()` to make contiguous. |
| Structured dtypes | **Hard to implement, low value.** Would require parsing format strings and dynamic field access. Workaround: access fields in Python, pass simple arrays to Zig. |
| String arrays | **Complex memory layout.** NumPy strings have fixed-width or object dtype. Workaround: convert to list of strings in Python. |

### Performance Tips

1. **Use contiguous arrays**: If you get a "buffer is not contiguous" error, call `.copy()` on sliced arrays
2. **Prefer `BufferView` over `BufferViewMut`**: Read-only when possible
3. **Release GIL for heavy computation**: Combine with `pyoz.releaseGIL()` for parallel Python threads

```zig
fn heavy_numpy_work(arr: pyoz.BufferView(f64)) f64 {
    const gil = pyoz.releaseGIL();
    defer gil.acquire();
    
    // CPU-intensive work without GIL
    var sum: f64 = 0;
    for (arr.data) |v| {
        sum += @sin(v) * @cos(v);
    }
    return sum;
}
```

## Iterators (Universal Iterable Support)

PyOZ provides `IteratorView(T)` for accepting **any** Python iterable - lists, tuples, sets, generators, ranges, or any object with `__iter__`.

### Basic Usage

```zig
const pyoz = @import("PyOZ");

// Works with ANY Python iterable!
fn sum_all(items: pyoz.IteratorView(i64)) i64 {
    var iter = items;
    var total: i64 = 0;
    while (iter.next()) |value| {
        total += value;
    }
    return total;
}

fn find_max(items: pyoz.IteratorView(i64)) ?i64 {
    var iter = items;
    var max_val: ?i64 = null;
    while (iter.next()) |value| {
        if (max_val == null or value > max_val.?) {
            max_val = value;
        }
    }
    return max_val;
}

fn average(items: pyoz.IteratorView(f64)) ?f64 {
    var iter = items;
    var sum: f64 = 0;
    var count: usize = 0;
    while (iter.next()) |value| {
        sum += value;
        count += 1;
    }
    if (count == 0) return null;
    return sum / @as(f64, @floatFromInt(count));
}

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .funcs = &.{
        pyoz.func("sum_all", sum_all, "Sum any iterable of integers"),
        pyoz.func("find_max", find_max, "Find max in any iterable"),
        pyoz.func("average", average, "Calculate average of any iterable"),
    },
});
```

Use from Python - works with **any iterable**:

```python
import mymodule

# Lists
mymodule.sum_all([1, 2, 3, 4, 5])  # 15

# Tuples
mymodule.sum_all((10, 20, 30))  # 60

# Sets
mymodule.sum_all({100, 200, 300})  # 600

# Ranges
mymodule.sum_all(range(1, 101))  # 5050

# Generators
mymodule.sum_all(x * x for x in range(10))  # 285

# Any iterator
mymodule.sum_all(iter([1, 2, 3]))  # 6

# Dict keys (dicts are iterable over keys)
mymodule.sum_all({1: 'a', 2: 'b', 3: 'c'})  # 6
```

### IteratorView API

```zig
var iter = items;           // Create mutable copy to iterate

// Core iteration
iter.next()                 // ?T - get next item or null when exhausted

// Convenience methods
iter.count()                // usize - count remaining items (consumes iterator)
iter.collect(allocator)     // ![]T - collect all items into allocated slice
iter.forEach(func)          // void - apply function to each item
iter.find(predicate)        // ?T - find first matching item
iter.any(predicate)         // bool - check if any item matches
iter.all(predicate)         // bool - check if all items match
```

### When to Use Each Collection Type

| Type | Use When |
|------|----------|
| `IteratorView(T)` | Accept **any** iterable (most flexible) |
| `ListView(T)` | Need list-specific features (indexing, length upfront) |
| `SetView(T)` | Need set-specific features (`contains` check) |
| `DictView(K, V)` | Need dict-specific features (key-value access) |
| `[]const T` | Need a concrete Zig slice (allocates/copies) |

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
- `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`, `__mod__`, `__divmod__`, `__pow__`, `__matmul__`
- `__neg__`, `__pos__`, `__abs__`, `__invert__`
- `__and__`, `__or__`, `__xor__`, `__lshift__`, `__rshift__`
- `__int__`, `__float__`, `__bool__`, `__index__`, `__complex__`
- In-place: `__iadd__`, `__isub__`, `__imul__`, `__imatmul__`, etc.
- Reflected: `__radd__`, `__rsub__`, `__rmul__`, `__rmatmul__`, etc.

### Sequences & Mappings
- `__len__`, `__getitem__`, `__setitem__`, `__delitem__`, `__contains__`
- `__iter__`, `__next__`, `__reversed__`
- `__missing__` (for dict subclasses)

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

## Keyword Arguments

Use `pyoz.Args(T)` to define functions with keyword arguments and defaults:

```zig
const GreetArgs = struct {
    name: []const u8,                    // Required positional
    greeting: []const u8 = "Hello",      // Optional with default
    times: i64 = 1,                      // Optional with default
    excited: bool = false,               // Optional with default
};

fn greet(args: pyoz.Args(GreetArgs)) []const u8 {
    const a = args.value;
    // Use a.name, a.greeting, a.times, a.excited
    return a.greeting;
}
```

```python
greet(name="World")                           # Uses defaults
greet(name="Alice", greeting="Hi", times=3)   # Override defaults
greet("Bob", excited=True)                    # Mix positional and keyword
```

## Class Inheritance

Extend Python built-in types using `__base__`:

```zig
const Stack = struct {
    // Inherit from Python's list
    pub const __base__ = pyoz.bases.list;

    pub fn push(self: *Stack, item: *pyoz.PyObject) void {
        _ = pyoz.py.PyList_Append(pyoz.object(self), item);
    }

    pub fn pop_item(self: *Stack) ?*pyoz.PyObject {
        // ... implementation using pyoz.object(self) to access base list
    }
};

const DefaultDict = struct {
    // Inherit from Python's dict
    pub const __base__ = pyoz.bases.dict;

    // Called when key is not found
    pub fn __missing__(self: *DefaultDict, key: *pyoz.PyObject) ?*pyoz.PyObject {
        // Return default value or store and return
    }
};
```

```python
s = Stack()
s.push(1)        # Custom method
s.append(2)      # Inherited from list
print(len(s))    # 2
```

## Class Attributes

Define class-level constants using the `classattr_` prefix:

```zig
const Circle = struct {
    radius: f64,

    // Class attributes (shared by all instances)
    pub const classattr_PI: f64 = 3.14159265358979;
    pub const classattr_UNIT_RADIUS: f64 = 1.0;
    pub const classattr_DEFAULT_COLOR: []const u8 = "red";
    pub const classattr_MAX_RADIUS: i64 = 1000;

    pub fn area(self: *const Circle) f64 {
        return classattr_PI * self.radius * self.radius;
    }
};
```

```python
print(Circle.PI)              # 3.14159265358979
print(Circle.DEFAULT_COLOR)   # "red"
c = Circle(5.0)
print(c.PI)                   # Also accessible on instances
```

## Docstrings

Add documentation to classes, methods, and fields:

```zig
const Point = struct {
    // Class docstring
    pub const __doc__: [*:0]const u8 = 
        "A 2D point with x and y coordinates.";

    // Field docstrings
    pub const x__doc__: [*:0]const u8 = "The x coordinate";
    pub const y__doc__: [*:0]const u8 = "The y coordinate";

    x: f64,
    y: f64,

    // Method docstring
    pub const magnitude__doc__: [*:0]const u8 = 
        "Calculate distance from origin.";

    pub fn magnitude(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    // Computed property docstring
    pub const length__doc__: [*:0]const u8 = 
        "The length (magnitude) of the point vector.";

    pub fn get_length(self: *const Point) f64 {
        return self.magnitude();
    }
};
```

```python
help(Point)              # Shows class and method docs
print(Point.__doc__)     # "A 2D point with x and y coordinates."
help(Point.magnitude)    # Shows method doc
```

## Frozen (Immutable) Classes

Create immutable classes that cannot be modified after creation:

```zig
const FrozenPoint = struct {
    pub const __frozen__: bool = true;

    x: f64,
    y: f64,

    // __hash__ is recommended for frozen classes (enables use in sets/dicts)
    pub fn __hash__(self: *const FrozenPoint) i64 {
        const x_bits: u64 = @bitCast(self.x);
        const y_bits: u64 = @bitCast(self.y);
        return @bitCast(x_bits ^ (y_bits *% 31));
    }

    pub fn __eq__(self: *const FrozenPoint, other: *const FrozenPoint) bool {
        return self.x == other.x and self.y == other.y;
    }
};
```

```python
p = FrozenPoint(3.0, 4.0)
p.x = 5.0  # Raises AttributeError!

# Can be used in sets and as dict keys
points = {FrozenPoint(0, 0), FrozenPoint(1, 1)}
cache = {FrozenPoint(0, 0): "origin"}
```

## Dynamic Attributes (__dict__ and weakref)

Enable Python-style dynamic attribute assignment:

```zig
const Flexible = struct {
    pub const __features__ = .{ .dict = true, .weakref = true };

    value: i64,

    pub fn get_value(self: *const Flexible) i64 {
        return self.value;
    }
};
```

```python
f = Flexible(42)
f.custom_attr = "hello"    # Works! Stored in __dict__
print(f.custom_attr)       # "hello"
print(f.__dict__)          # {'custom_attr': 'hello'}

import weakref
ref = weakref.ref(f)       # Weak references work too
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
- **Linux/macOS**: `python3` in PATH
- **Windows**: `python` in PATH

Python configuration is auto-detected using the `sysconfig` module (standard library).

## Comparison with PyO3

| Feature | PyOZ | PyO3 |
|---------|------|------|
| Language | Zig | Rust |
| Binary size | ~8KB (module) | ~100KB+ |
| Compile time | Fast | Slow |
| All magic methods | ✅ | ✅ |
| Static/class methods | ✅ | ✅ |
| Context managers | ✅ | ✅ |
| Buffer protocol | ✅ | ✅ |
| GIL control | ✅ | ✅ |
| Async/await | ❌ | ✅ |
| abi3 (stable ABI) | ❌ | ✅ |
| Maturity | New | Battle-tested |

## Comparison with Ziggy-Pydust

[Ziggy-Pydust](https://github.com/spiraldb/ziggy-pydust) is another Zig-to-Python binding library. Here's a fair comparison based on code analysis of both projects:

### API Philosophy

**PyOZ** - Write natural Zig:
```zig
fn add(a: i64, b: i64) i64 {
    return a + b;
}
```

**Pydust** - Struct-wrapped arguments:
```zig
pub fn add(args: struct { a: i64, b: i64 }) i64 {
    return args.a + args.b;
}
```

### Class Definitions

**PyOZ** - Structs remain portable Zig:
```zig
const Point = struct {
    x: f64,
    y: f64,
    pub fn magnitude(self: *const Point) f64 { ... }
};
// Register with: pyoz.class("Point", Point)
```

**Pydust** - Wrapper pattern:
```zig
pub const Point = py.class(struct {
    x: f64,
    y: f64,
    pub fn magnitude(self: *const @This()) f64 { ... }
});
```

### Feature Comparison

| Feature | PyOZ | Pydust |
|---------|------|--------|
| **Zig version** | 0.15.x | 0.14.0 |
| **Python version** | 3.8+ | 3.11+ |
| **Stable ABI (abi3)** | ❌ | ✅ |
| **Build system** | Standalone CLI | Poetry integration |
| **Function syntax** | Natural Zig | Struct-wrapped args |
| **`*args/**kwargs`** | ✅ | ✅ (native to struct pattern) |
| **NumPy BufferView** | ✅ First-class | ✅ Lower-level |
| **Complex numbers** | ✅ Built-in types | Manual |
| **DateTime types** | ✅ Built-in | Manual |
| **Decimal type** | ✅ Built-in | Manual |
| **i128/u128** | ✅ | Unknown |
| **All dunder methods** | ✅ | ✅ |
| **Reflected ops (`__radd__`)** | ✅ | Limited |
| **Context managers** | ✅ | Unknown |
| **Descriptors** | ✅ | Limited |
| **GIL control** | ✅ | ✅ |
| **GC support** | ✅ | ✅ |
| **pytest integration** | ❌ | ✅ |

### When to Choose Each

| Choose **PyOZ** if... | Choose **Pydust** if... |
|-----------------------|-------------------------|
| You want clean, natural Zig syntax | You need stable ABI (one binary for Python 3.11+) |
| You need Python 3.8-3.10 support | You already use Poetry |
| You want built-in numpy/datetime/decimal support | You want pytest integration |
| You prefer standalone CLI tooling | You prefer a more modular codebase |
| You want the latest Zig (0.15.x) | You want an established project (SpiralDB backing) |

### Codebase Comparison

| Metric | PyOZ | Pydust |
|--------|------|--------|
| Core library LoC | ~7,600 | ~5,750 |
| File count | 4 (monolithic) | 30+ (modular) |
| Architecture | Straightforward | Discovery-based |

**Bottom line:** PyOZ prioritizes ergonomics and "just write Zig" philosophy. Pydust prioritizes modularity and stable ABI. Both are valid approaches for different use cases.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.
