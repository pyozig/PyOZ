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
| `pyoz.Bytes` | `bytes` or `bytearray` | Byte sequences (read-only) |
| `pyoz.ByteArray` | `bytearray` | Mutable byte sequences |
| `pyoz.MemoryView` | `memoryview` | Read-only memoryview access (call `.release()` when done) |
| `pyoz.BytesLike` | `bytes`, `bytearray`, or `memoryview` | Any byte-like object (call `.release()` when done) |
| `pyoz.Path` | `str` or `pathlib.Path` | File paths (accepts both) |
| `pyoz.Decimal` | `decimal.Decimal` | Arbitrary precision decimals |
| `pyoz.Owned(T)` | (same as `T`) | Allocator-backed return values |

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
| `pyoz.Iterator(T)` | `list` | `.{ .items = &.{...} }` (eager) |
| `pyoz.LazyIterator(T, State)` | iterator | Lazy on-demand iteration |
| `struct { T, U }` | `tuple` | `return .{ a, b };` |

### Iterator vs LazyIterator

PyOZ provides two ways to return iterable data:

**`Iterator(T)`** - Eager iteration, converts to Python list immediately:

```zig
fn get_fibonacci() pyoz.Iterator(i64) {
    const fibs = [_]i64{ 1, 1, 2, 3, 5, 8, 13, 21, 34, 55 };
    return .{ .items = &fibs };
}
// Python: get_fibonacci() returns [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
```

**`LazyIterator(T, State)`** - Lazy iteration, generates values on-demand:

```zig
const RangeState = struct {
    current: i64,
    end: i64,
    step: i64,

    pub fn next(self: *@This()) ?i64 {
        if (self.current >= self.end) return null;
        const val = self.current;
        self.current += self.step;
        return val;
    }
};

fn lazy_range(start: i64, end: i64, step: i64) pyoz.LazyIterator(i64, RangeState) {
    return .{ .state = .{ .current = start, .end = end, .step = step } };
}
// Python: lazy_range(0, 1000000, 1) returns an iterator (memory efficient!)
```

**When to use which:**

| Use Case | Type | Reason |
|----------|------|--------|
| Small, known data | `Iterator(T)` | Simple, returns a list |
| Large/infinite sequences | `LazyIterator(T, State)` | Memory efficient |
| Need random access | `Iterator(T)` | Lists support indexing |
| Stream processing | `LazyIterator(T, State)` | Values computed on-demand |

### View Types (Input Only)

View types provide **zero-copy read access** to Python collections. They are **consumer-only** - you can receive them as function parameters but cannot return them. This asymmetry exists because:

1. Views hold references to Python objects that must remain valid
2. The underlying Python object owns the memory
3. Returning a view would require the caller to manage Python object lifetimes

For returning collections, use the producer types (`Set`, `Dict`, `Iterator`, etc.) which create new Python objects.

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

## Allocator-Backed Returns (`Owned`)

When you need to return dynamically-sized data (e.g., formatted strings, variable-length arrays), use `pyoz.Owned(T)` instead of fixed-size stack buffers. `Owned(T)` pairs a heap-allocated value with its allocator — PyOZ converts the value to a Python object, then frees the backing memory automatically.

```zig
fn generate_report(count: i64) !pyoz.Owned([]const u8) {
    const allocator = std.heap.page_allocator;
    const result = try std.fmt.allocPrint(allocator, "Processed {d} items", .{count});
    return pyoz.owned(allocator, result);  // []u8 auto-coerced to []const u8
}
```

The `pyoz.owned(allocator, value)` constructor automatically coerces mutable slices (`[]u8`) to const (`[]const u8`), so `std.fmt.allocPrint` and `allocator.alloc` results work directly without `@as` casts.

**Supported wrappers:** `!Owned(T)` (error union) and `?Owned(T)` (optional) both work — PyOZ unwraps them before converting.

**Why not stack buffers?** A common pattern is `var buf: [4096]u8 = undefined;` — this works for small strings because `toPy` copies the data immediately, but it silently truncates output beyond 4096 bytes and is fragile. `Owned(T)` has no size limit and makes the allocation/deallocation explicit.

**Supported inner types:** Any slice type that PyOZ can convert — `[]const u8` (→ `str`), `[]const i64` (→ `list[int]`), etc.

## Class Instances

Pass your PyOZ classes between functions:

- `*const T` - Read-only access to instance
- `*T` - Mutable access to instance

The class must be registered in the same module.

## Raw Python Objects

For advanced cases, use `*pyoz.PyObject` to work directly with Python objects. You're responsible for reference counting and type checking.

**As parameters:** Accept any Python object and convert manually:

```zig
pub fn process(self: *MyClass, obj: *pyoz.PyObject) i64 {
    // Use pyoz.Conversions.fromPy() or the C API directly
    return pyoz.Conversions.fromPy(i64, obj) catch 0;
}
```

**As return type:** Return a raw Python object built via the C API:

```zig
pub fn children(self: *const MyClass) ?*pyoz.PyObject {
    const list = pyoz.py.PyList_New(2) orelse return null;
    // ... populate list with PyList_SetItem ...
    return list;
}
```

When returning `?*pyoz.PyObject`, the converter passes it through as-is — no additional conversion is applied. Return `null` to signal an error (set the exception first with `pyoz.raiseValueError()` etc.).

**Converting registered classes to PyObject:** When building raw Python containers that hold instances of your registered classes, use the module-level converter instead of `pyoz.Conversions`. The generic `pyoz.Conversions` has no class knowledge and will return `null` for class types.

```zig
pub const Module = pyoz.module(.{
    .name = "mymodule",
    .classes = &.{ pyoz.class("Node", Node) },
});

const Node = struct {
    value: i64,

    /// Build a Python list of Node objects using the module converter
    pub fn children(self: *const Node) ?*pyoz.PyObject {
        const list = pyoz.py.PyList_New(0) orelse return null;
        for (self.getChildren()) |child| {
            // Module.toPy knows about Node — pyoz.Conversions.toPy does NOT
            const obj = Module.toPy(Node, child) orelse {
                pyoz.py.Py_DecRef(list);
                return null;
            };
            _ = pyoz.py.PyList_Append(list, obj);
            pyoz.py.Py_DecRef(obj);
        }
        return list;
    }
};
```

## Callable (Python Callbacks)

Use `pyoz.Callable(ReturnType)` to accept Python functions, lambdas, or any callable object as a parameter. PyOZ handles argument conversion, the call, result conversion, and all reference counting automatically.

```zig
fn apply(callback: pyoz.Callable(i64), x: i64, y: i64) ?i64 {
    return callback.call(.{ x, y });
}
```

Python:
```python
apply(lambda x, y: x + y, 3, 4)   # 7
apply(lambda x, y: x * y, 3, 4)   # 12
apply(pow, 2, 10)                  # 1024
```

The return type is always optional (`?ReturnType`) — returns `null` (Python `None`) if the callback raises an exception. The exception propagates to Python.

For callbacks that return nothing, use `Callable(void)`. The `.call()` method returns `bool` (true = success, false = exception):

```zig
fn run_hook(callback: pyoz.Callable(void), value: i64) bool {
    return callback.call(.{value});
}
```

**Methods:**

| Method | Description |
|--------|-------------|
| `.call(.{ args... })` | Call with arguments (Zig tuple) |
| `.callNoArgs()` | Call with no arguments |
| `.obj` | Access the underlying `*PyObject` |

## Type Conversion Summary

| Direction | Zig | Python |
|-----------|-----|--------|
| Both | Integers, floats, bool, strings | int, float, bool, str |
| Both | `?T` | T or None |
| Both | Special types (Complex, DateTime, etc.) | Corresponding Python types |
| Input only | View types (ListView, BufferView, etc.) | list, dict, set, ndarray |
| Both | `*pyoz.PyObject` | Any Python object (advanced) |
| Input only | `*const T`, `*T` | Class instances |
| Input only | `pyoz.Callable(T)` | Functions, lambdas, any callable |
| Input only | `[N]T` | list or tuple (exact size) |
| Output only | Slices, Dict, Set | list, dict, set |
| Both | Zig tuple `struct { T, U }` | tuple (exact size) |
| Output only | `pyoz.Owned(T)` | Same as `T` (frees backing memory) |

## Next Steps

- [Errors](errors.md) - Exception handling
- [Functions](functions.md) - Function definitions
- [Classes](classes.md) - Class definitions

## Formatted Strings

`pyoz.fmt(format, args)` returns a lazily formatted `pyoz.Formatted` value that
converts to `str` wherever PyOZ converts return values, including `__repr__`:

```zig
pub fn __repr__(self: *const Vec2) pyoz.Formatted("Vec2({d:.2}, {d:.2})", struct { f64, f64 }) {
    return .{ .args = .{ self.x, self.y } };
}
```

See [`pyoz.fmt`](../reference/api.md#pyozfmtcomptime-format-args).
