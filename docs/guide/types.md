# Types

PyOZ automatically converts between Zig and Python types. This guide covers all supported types.

## Basic Types

| Zig Type | Python Type | Notes |
|----------|-------------|-------|
| `i8` - `i64`, `u8` - `u64` | `int` | Standard integers |
| `i128`, `u128` | `int` | Big integers (via string conversion) |
| `f32`, `f64` | `float` | Floating point |
| `bool` | `bool` | Boolean |
| `[]const u8` | `str` | Strings (input and output) |
| `void` | `None` | No return value |

## Optional Types

Use `?T` for values that may be `None`:

- As parameters: `?[]const u8` becomes an optional keyword argument
- As return type: return `null` to return `None`

When returning `null`, if a Python exception is set, it becomes an error indicator; otherwise returns `None`.

## Special Types

PyOZ provides wrapper types for Python's specialized types:

| Type | Python Equivalent | Usage |
|------|-------------------|-------|
| `pyoz.Complex` | `complex` | 64-bit complex numbers |
| `pyoz.Complex32` | `complex` | 32-bit complex (NumPy) |
| `pyoz.Date` | `datetime.date` | Date values |
| `pyoz.Time` | `datetime.time` | Time values |
| `pyoz.DateTime` | `datetime.datetime` | Combined date/time |
| `pyoz.TimeDelta` | `datetime.timedelta` | Time differences |
| `pyoz.Bytes` | `bytes` | Byte sequences |
| `pyoz.Path` | `str` or `pathlib.Path` | File paths (accepts both) |
| `pyoz.Decimal` | `decimal.Decimal` | Arbitrary precision decimals |

Create them with `.init()` methods (e.g., `pyoz.Date.init(2024, 12, 25)`).

## Collections

### Input (Zero-Copy Views)

These provide read access to Python collections without copying:

| Type | Python Source | Key Methods |
|------|---------------|-------------|
| `pyoz.ListView(T)` | `list` | `.len()`, `.get(i)`, `.iterator()` |
| `pyoz.DictView(K, V)` | `dict` | `.len()`, `.get(key)`, `.contains(key)`, `.iterator()` |
| `pyoz.SetView(T)` | `set`/`frozenset` | `.len()`, `.contains(val)`, `.iterator()` |
| `pyoz.IteratorView(T)` | Any iterable | `.next()` - works with generators, ranges, etc. |

### Output

| Type | Creates | Example |
|------|---------|---------|
| `[]const T` | `list` | `return &[_]i64{1, 2, 3};` |
| `pyoz.Dict(K, V)` | `dict` | `.{ .entries = &.{...} }` |
| `pyoz.Set(T)` | `set` | `.{ .items = &.{...} }` |
| `pyoz.FrozenSet(T)` | `frozenset` | `.{ .items = &.{...} }` |
| `struct { T, U }` | `tuple` | `return .{ a, b };` |

### Fixed-Size Arrays

`[N]T` accepts a Python list of exactly N elements. Wrong size raises an error.

## NumPy Arrays (Buffer Protocol)

Zero-copy access to NumPy arrays:

| Type | Access | Use Case |
|------|--------|----------|
| `pyoz.BufferView(T)` | Read-only | Analysis, computation |
| `pyoz.BufferViewMut(T)` | Read-write | In-place modification |

**Supported element types:** `f32`, `f64`, `i8`-`i64`, `u8`-`u64`, `pyoz.Complex`, `pyoz.Complex32`

**Methods:** `.len()`, `.rows()`, `.cols()`, `.data` (slice), `.fill(value)` (mutable only)

Access data directly via `.data` slice for maximum performance.

## Class Instances

Pass your PyOZ classes between functions:

- `*const T` - Read-only access to instance
- `*T` - Mutable access to instance

The class must be registered in the same module.

## Raw Python Objects

For advanced cases, use `*pyoz.PyObject` to accept any Python object. You're responsible for reference counting and type checking.

## Type Conversion Summary

| Direction | Zig | Python |
|-----------|-----|--------|
| Both | Integers, floats, bool, strings | int, float, bool, str |
| Both | `?T` | T or None |
| Both | Special types (Complex, DateTime, etc.) | Corresponding Python types |
| Input only | View types (ListView, BufferView, etc.) | list, dict, set, ndarray |
| Input only | `*const T`, `*T` | Class instances |
| Input only | `[N]T` | list (exact size) |
| Output only | Slices, Dict, Set | list, dict, set |
| Output only | Anonymous struct | tuple |

## Next Steps

- [Errors](errors.md) - Exception handling
- [Functions](functions.md) - Function definitions
- [Classes](classes.md) - Class definitions
