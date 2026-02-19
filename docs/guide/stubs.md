# Type Stubs

PyOZ automatically generates Python type stub files (`.pyi`) at compile time. These provide IDE autocomplete, type checking with mypy/pyright, and API documentation.

## Automatic Generation

When you build with `pyoz build` or `pyoz develop`, stub files are generated alongside the extension:

```
zig-out/lib/
├── mymodule.so      # Linux/macOS
├── mymodule.pyd     # Windows
└── mymodule.pyi     # Type stubs
```

## What Gets Generated

PyOZ generates stubs for all exported items:

- **Functions**: Parameter types, return types, docstrings
- **Classes**: Fields, methods, static methods, properties
- **Enums**: IntEnum or StrEnum with correct values
- **Constants**: Module-level constants with types
- **Exceptions**: Custom exception classes with base types

## Type Mappings

| Zig Type | Python Annotation |
|----------|-------------------|
| `i8`-`i64`, `u8`-`u64`, `i128`, `u128` | `int` |
| `f32`, `f64` | `float` |
| `bool` | `bool` |
| `[]const u8` | `str` |
| `void` | `None` |
| `?T` | `T \| None` |
| `pyoz.Signature(?T, "U")` | `U` (user-defined override) |
| `!T` | `T` |
| `pyoz.Complex` | `complex` |
| `pyoz.Date` | `datetime.date` |
| `pyoz.DateTime` | `datetime.datetime` |
| `pyoz.Bytes` | `bytes` |
| `pyoz.Path` | `str \| pathlib.Path` |
| `pyoz.Decimal` | `decimal.Decimal` |
| `pyoz.ListView(T)` | `list[T]` |
| `pyoz.DictView(K,V)` | `dict[K, V]` |
| `pyoz.BufferView(T)` | `numpy.ndarray` |
| `[]const T` (return) | `list[T]` |
| `struct { T, U }` (return) | `tuple[T, U]` |

## Example Output

For this Zig module:

```zig
const Point = struct {
    x: f64,
    y: f64,
    pub fn magnitude(self: *const Point) f64 { ... }
    pub fn origin() Point { ... }
};

fn add(a: i64, b: i64) i64 { return a + b; }
```

PyOZ generates:

```python
# mymodule.pyi
def add(a: int, b: int) -> int: ...

class Point:
    x: float
    y: float
    def __init__(self, x: float, y: float) -> None: ...
    def magnitude(self) -> float: ...
    @staticmethod
    def origin() -> Point: ...
```

## Adding Docstrings

Docstrings are included in stubs:

```zig
pyoz.func("add", add, "Add two integers together."),
```

For classes and methods, use `__doc__` constants:

```zig
const Point = struct {
    pub const __doc__: [*:0]const u8 = "A 2D point.";
    pub const magnitude__doc__: [*:0]const u8 = "Distance from origin.";
};
```

## IDE Support

With stubs in place, IDEs provide:
- **Autocomplete**: Function names, parameters, class members
- **Type hints**: Parameter and return types shown inline
- **Documentation**: Docstrings in hover tooltips
- **Error detection**: Type mismatches highlighted

## Type Checking

Run mypy or pyright on your Python code:

```bash
mypy my_script.py
pyright my_script.py
```

## Return Type Override (`Signature`)

Sometimes the automatically inferred stub type doesn't match the intended Python-level API. The most common case: a function returns `?T` (optional) only to signal errors via `null`, but the Python caller never sees `None` — they see a raised exception instead. The stub would show `T | None` when it should just show `T`.

Use `pyoz.Signature(T, "stub_string")` as the return type to override the stub annotation while preserving runtime behavior:

```zig
fn validate_positive(n: i64) pyoz.Signature(?i64, "int") {
    if (n < 0) {
        _ = pyoz.raiseValueError("must be non-negative");
        return .{ .value = null };
    }
    return .{ .value = n };
}
```

Generated stub:
```python
def validate_positive(arg0: int) -> int: ...
```

Without `Signature`, the stub would show `-> int | None`.

### How It Works

`Signature` is a comptime wrapper type. At runtime it's a struct with a single `.value` field — PyOZ unwraps it automatically, so Python never sees the wrapper. The second parameter (the string) is used verbatim as the return type annotation in the generated `.pyi` file.

### Works Everywhere

`Signature` works identically for module-level functions and class methods (instance, static, and class methods):

```zig
const Parser = struct {
    pub fn parse(self: *const Parser, input: []const u8) pyoz.Signature(?Node, "Node") {
        // null signals an error, not a None return
        if (input.len == 0) {
            _ = pyoz.raiseValueError("empty input");
            return .{ .value = null };
        }
        return .{ .value = self.doParse(input) };
    }
};
```

Generated stub:
```python
def parse(self, arg0: str) -> Node: ...
```

### When to Use

| Scenario | Without Signature | With Signature |
|----------|-------------------|----------------|
| `?T` where `null` = error | `T \| None` | Use `Signature(?T, "T")` |
| Raw `*PyObject` return | `Any` | Use `Signature(*PyObject, "list[Node]")` |
| Complex generic return | `Any` | Use `Signature(*PyObject, "dict[str, list[int]]")` |

## Limitations

- Generic types may show as `Any` for complex cases
- Some advanced Zig patterns may not map perfectly
- Submodule stubs are included in the parent stub file

## Next Steps

- [Installation](../installation.md) - Build and install your module
- [Quickstart](../quickstart.md) - Getting started guide
