# API Reference

Quick reference for PyOZ's public API.

## Module Definition

### `pyoz.module(config)`

Define a Python module.

```zig
pub const MyModule = pyoz.module(.{
    .name = "mymodule",           // Required: module name
    .doc = "Description",          // Optional: docstring
    .from = &.{ ... },            // Optional: auto-scan namespaces
    .funcs = &.{ ... },           // Optional: functions
    .classes = &.{ ... },         // Optional: classes
    .enums = &.{ ... },           // Optional: enums
    .consts = &.{ ... },          // Optional: constants
    .exceptions = &.{ ... },      // Optional: custom exceptions
    .error_mappings = &.{ ... },  // Optional: error->exception mappings
    .gil_used = false,            // Optional: safe without the GIL (free-threaded CPython)
});
```

`.gil_used = false` declares that the module can run without the GIL on
free-threaded CPython (3.13t/3.14t); without it, importing the module re-enables
the GIL for the whole process. It has no effect on regular builds. See
[Free-Threading](../guide/free-threading.md).

## Auto-Scan (`.from`)

### `.from` Field

Auto-scan Zig namespaces to register all Python-compatible public declarations.

```zig
const math = @import("math.zig");

pub const MyModule = pyoz.module(.{
    .name = "mymodule",
    .from = &.{ math },
});
```

See [Auto-Scan Guide](../guide/from.md) for full details.

### `pyoz.source(namespace, options)`

Filter which declarations to export from a namespace.

```zig
pyoz.source(math, .{ .only = &.{ "add", "PI" } })
pyoz.source(math, .{ .exclude = &.{ "internal_helper" } })
```

`.only` and `.exclude` are mutually exclusive.

### `pyoz.withSource(namespace, source)`

Attach source text to a namespace for automatic `///` doc comment and parameter name extraction.

```zig
pyoz.withSource(@import("math.zig"), @embedFile("math.zig"))
```

Enables: real parameter names in `help()` / `inspect.signature()` / `.pyi` stubs, `///` doc comments as Python docstrings, `//!` module-level doc comments, and `///` above structs as class docstrings. Composes with `source()` and `sub()`. Source text is NOT embedded in the final binary.

### `pyoz.sub(name, namespace)`

Create a submodule from a namespace.

```zig
pyoz.sub("strings", string_utils)
pyoz.sub("io", pyoz.source(io_utils, .{ .exclude = &.{ "debug" } }))
```

### `pyoz.Exception(base, doc)`

Marker type for defining exceptions inside `.from` namespaces.

```zig
pub const MyError = pyoz.Exception(.ValueError, "Raised on invalid input");
```

### `pyoz.ErrorMap(mappings)`

Marker type for defining error-to-exception mappings inside `.from` namespaces.

```zig
pub const __errors__ = pyoz.ErrorMap(.{
    .{ "InvalidInput", .ValueError },
    .{ "TooBig", .ValueError, "Value exceeds limit" },
});
```

### Docstring Convention

With `withSource`, `///` doc comments are automatically extracted as docstrings and `//!` comments become the module docstring. Without `withSource`, use explicit constants:

```zig
pub fn add(a: i64, b: i64) i64 { return a + b; }
pub const add__doc__ = "Add two integers";       // docstring for add
pub const __doc__ = "Module docstring fallback";  // namespace-level docstring
```

Explicit `{name}__doc__` constants take priority over `///` comments.

## Functions

### `pyoz.func(name, fn, doc)`

Define a basic function.

```zig
pyoz.func("add", add, "Add two numbers")
```

### `.withParams(names)`

Name the Python-visible parameters of a `pyoz.func` entry. Zig reflection cannot
recover parameter names, so without it they appear as `arg0, arg1, ...` in
stubs and `help()`:

```zig
pyoz.func("fetch", pyoz.asyncFn(fetch), "Sleep, then add").withParams("delay_ms, a, b"),
```

When every parameter is named and the function has `?T` parameters, those are
optional and can be passed by keyword (`fetch(5, timeout=2)`).

For methods, use `pub const method__params__ = "a, b";` on the class.

### `pyoz.kwfunc(name, fn, doc)`

Define a function with named keyword arguments using `Args(T)`.

```zig
const GreetArgs = struct {
    name: []const u8,
    greeting: []const u8 = "Hello",
};

fn greet(args: pyoz.Args(GreetArgs)) []const u8 { ... }

pyoz.kwfunc("greet", greet, "Greet someone")
```

## Async

See the [Async guide](../guide/async.md) for semantics, cancellation and
performance.

### `pyoz.asyncFn(f)`

Wrap a Zig function so that calling it from Python returns an `asyncio.Future`.
`f` runs on its own `std.Io` task without the GIL. Optional leading parameters:
`std.Io` and `std.mem.Allocator` (per-call arena). Up to 8 Python-visible
parameters, copied at call time.

```zig
fn fetch(io: std.Io, ms: i64, a: i64, b: i64) !i64 {
    try io.sleep(.fromMilliseconds(ms), .awake);
    return a + b;
}
.funcs = &.{ pyoz.func("fetch", pyoz.asyncFn(fetch), "Sleep, then add") },
```

### `pyoz.asyncThen(f, then)`

`asyncFn` with a completion step: when `f` succeeds, `then(result, extra...)`
runs on the event loop thread with Python attached, and the awaitable resolves
to its result. The extra parameters follow `f`'s in the Python signature and may
be `*pyoz.PyObject` / `?*pyoz.PyObject` (kept alive until `then` has run).
`pyoz.asyncMethodThen(f, then)` is the method form.

```zig
fn compileImpl(grammar: []const u8) !Parser { ... }
fn bindImpl(parser: Parser, classes: ?*pyoz.PyObject) !Parser { ... }
pyoz.func("compile_async", pyoz.asyncThen(compileImpl, bindImpl), "...").withParams("grammar, classes"),
```

### `pyoz.asyncMethod(f)`

Async instance method. The `self` parameter type is the safety contract:
`self: T` runs on a copy; `self: *const T` borrows the object (frozen classes
without `*T` methods only); `self: *T` is a compile error.

```zig
fn slowNormImpl(self: *const Vec, io: std.Io) !f64 { ... }
pub const slow_norm = pyoz.asyncMethod(slowNormImpl);
```

### `pyoz.io()`

The process-wide `std.Io` runtime used by async functions; also usable from
synchronous functions.

### `pyoz.setAsyncConcurrency(n)`

Maximum number of async jobs running at once (default 256; further calls
queue). Must be called before the first async call; returns `false` otherwise.

### `pyoz.asyncLiveJobs()`

Number of async jobs not yet fully cleaned up. Useful for leak checks in tests.

## Classes

### `pyoz.class(name, T)`

Define a class from a Zig struct.

```zig
pyoz.class("Point", Point)
```

### `pyoz.base(Parent)`

Declare inheritance from another PyOZ class. The child struct must embed the parent as its first field named `_parent`.

```zig
const Animal = struct {
    name: []const u8,
    age: i64,

    pub fn speak(self: *const Animal) []const u8 {
        return "...";
    }
};

const Dog = struct {
    pub const __base__ = pyoz.base(Animal);

    _parent: Animal,       // Must be first field, must match parent type
    breed: []const u8,

    pub fn fetch(self: *const Dog) []const u8 {
        return "fetching!";
    }
};
```

Python constructor accepts flattened fields (parent fields first, then child fields):

```python
d = Dog("Rex", 3, "Labrador")   # name, age from Animal; breed from Dog
d.speak()                         # inherited method
d.fetch()                         # own method
isinstance(d, Animal)             # True
```

Rules:
- Parent class must be listed before child in the `classes` array
- Child's first field must be `_parent: ParentType`
- Parent methods and properties are inherited via Python's MRO
- `isinstance()` and type checks work correctly for subtypes

## Properties

### `pyoz.property(config)`

Define a property with custom getter/setter.

```zig
pub const celsius = pyoz.property(.{
    .get = struct {
        fn get(self: *const Self) f64 { return self._celsius; }
    }.get,
    .set = struct {
        fn set(self: *Self, v: f64) void { self._celsius = v; }
    }.set,
    .doc = "Temperature in Celsius",
});
```

## Enums

### `pyoz.enumDef(name, E)`

Define an enum (auto-detects IntEnum vs StrEnum).

```zig
pyoz.enumDef("Color", Color)      // enum(i32) -> IntEnum
pyoz.enumDef("Status", Status)    // enum -> StrEnum
```

## Constants

### `pyoz.constant(name, value)`

Define a module-level constant.

```zig
pyoz.constant("VERSION", "1.0.0")
pyoz.constant("PI", 3.14159)
pyoz.constant("MAX", @as(i64, 1000))
```

## Exceptions

### `pyoz.exception(name, opts)`

Define a custom exception.

```zig
// Full syntax
pyoz.exception("MyError", .{ .doc = "...", .base = .ValueError })

// Shorthand
pyoz.exception("MyError", .ValueError)
```

### Exception Bases

`.Exception`, `.ValueError`, `.TypeError`, `.RuntimeError`, `.IndexError`, `.KeyError`, `.AttributeError`, `.StopIteration`

### Raising Exceptions

```zig
// One-liner (in functions returning ?T):
if (bad) return pyoz.raiseValueError("message");

// Two-line (discard return, then return null):
_ = pyoz.raiseValueError("message");
return null;
```

All raise functions: `raiseValueError`, `raiseTypeError`, `raiseRuntimeError`, `raiseKeyError`, `raiseIndexError`, `raiseAttributeError`, `raiseMemoryError`, `raiseOSError`, and [many more](../guide/errors.md).

### `pyoz.fmt(comptime format, args)`

Lazily formatted message using Zig's `std.fmt` syntax. Returns a
`pyoz.Formatted(format, @TypeOf(args))` value that captures the arguments and
formats nothing until it is consumed: by any `raise*` function, or when it is
returned from a function or method and converted to a Python `str`.

```zig
// With raise functions:
return pyoz.raiseValueError(pyoz.fmt("value {d} exceeds limit {d}", .{ val, limit }));

// As a return type (the format is written once, in the signature):
pub fn __repr__(self: *const Vec2) pyoz.Formatted("Vec2({d:.2}, {d:.2})", struct { f64, f64 }) {
    return .{ .args = .{ self.x, self.y } };
}
```

Messages up to 512 bytes are formatted on the consumer's stack with no heap
allocation; longer ones use one exact-size allocation and are never truncated.
Slices inside `args` must still be valid when the value is consumed (slices
into `self` are fine; slices into a local buffer of the returning function are
not). To format into your own buffer, use `std.fmt.bufPrintZ`.

### Catching Exceptions

```zig
if (pyoz.catchException()) |*exc| {
    defer @constCast(exc).deinit();
    if (exc.isValueError()) { ... }
    else exc.reraise();
}
```

## Error Mapping

### `pyoz.mapError(name, exc)`

Map Zig error to Python exception.

```zig
pyoz.mapError("OutOfBounds", .IndexError)
```

### `pyoz.mapErrorMsg(name, exc, msg)`

Map with custom message.

```zig
pyoz.mapErrorMsg("InvalidInput", .ValueError, "Input is invalid")
```

## Types

### Input Types

| Type | Python |
|------|--------|
| `pyoz.ListView(T)` | `list` |
| `pyoz.DictView(K, V)` | `dict` |
| `pyoz.SetView(T)` | `set` |
| `pyoz.IteratorView(T)` | Any iterable |
| `pyoz.BufferView(T)` | NumPy array (read) |
| `pyoz.BufferViewMut(T)` | NumPy array (write) |

### Output Types

| Type | Python |
|------|--------|
| `pyoz.Dict(K, V)` | `dict` |
| `pyoz.Set(T)` | `set` |
| `pyoz.FrozenSet(T)` | `frozenset` |

| `pyoz.Formatted(fmt, Args)` | `str` (from `pyoz.fmt`) |

### Special Types

| Type | Python |
|------|--------|
| `pyoz.Complex` | `complex` |
| `pyoz.Date` | `datetime.date` |
| `pyoz.Time` | `datetime.time` |
| `pyoz.DateTime` | `datetime.datetime` |
| `pyoz.TimeDelta` | `datetime.timedelta` |
| `pyoz.Bytes` | `bytes` or `bytearray` |
| `pyoz.ByteArray` | `bytearray` |
| `pyoz.MemoryView` | `memoryview` |
| `pyoz.BytesLike` | `bytes`, `bytearray`, or `memoryview` |
| `pyoz.Path` | `str` or `pathlib.Path` |
| `pyoz.Decimal` | `decimal.Decimal` |

## Allocator-Backed Returns

### `pyoz.Owned(T)`

Wrapper for returning heap-allocated values. PyOZ converts the inner value to a Python object, then frees the backing memory.

```zig
fn make_report(count: i64) !pyoz.Owned([]const u8) {
    const allocator = std.heap.page_allocator;
    const result = try std.fmt.allocPrint(allocator, "Report: {d} items", .{count});
    return pyoz.owned(allocator, result);
}
```

### `pyoz.owned(allocator, value)`

Create an `Owned` wrapper. Auto-coerces `[]u8` → `[]const u8`.

```zig
const data = try allocator.alloc(u8, 1024);
return pyoz.owned(allocator, data);  // returns Owned([]const u8)
```

Supports `!Owned(T)` (error union) and `?Owned(T)` (optional) return types.

## Stub Return Type Override

### `pyoz.Signature(T, "stub_string")`

Override the `.pyi` stub return type annotation while preserving runtime behavior. `T` is the actual Zig return type; `"stub_string"` is written verbatim into the generated stub.

```zig
fn validate(n: i64) pyoz.Signature(?i64, "int") {
    if (n < 0) return pyoz.raiseValueError("must be non-negative");
    return .{ .value = n };
}
```

At runtime, `Signature` is a struct with a `.value` field — PyOZ unwraps it automatically. Works for module-level functions and class methods (instance, static, class).

| Usage | Stub Output |
|-------|-------------|
| `pyoz.Signature(?i64, "int")` | `-> int` |
| `pyoz.Signature(?*PyObject, "list[Node]")` | `-> list[Node]` |
| `pyoz.Signature(?Node, "Node")` | `-> Node` |

## Strong References

### `pyoz.Ref(T)`

Strong reference to a Python-managed object of type `T`. Prevents use-after-free via automatic refcounting.

```zig
const Child = struct {
    _owner: pyoz.Ref(Owner),
    tag: i64,
};
```

| Method | Description |
|--------|-------------|
| `ref.set(py_obj)` | Store reference (INCREFs new, DECREFs old) |
| `ref.get(class_infos)` | Get `?*const T` to referenced data |
| `ref.getMut(class_infos)` | Get `?*T` to referenced data |
| `ref.object()` | Get raw `?*PyObject` (borrowed) |
| `ref.clear()` | Release reference (DECREF + set null) |

Ref fields are automatically excluded from Python properties, `__init__`, and stubs.

### `Module.selfObject(T, ptr)`

Recover the wrapping `*PyObject` from a `*const T` data pointer. Used to obtain the PyObject needed for `Ref(T).set()`.

```zig
fn make_child(owner: *const Owner, tag: i64) Child {
    var child = Child{ .tag = tag, ._owner = .{} };
    child._owner.set(MyModule.selfObject(Owner, owner));
    return child;
}
```

## GIL Control

### `pyoz.releaseGIL()`

Release the GIL for CPU-intensive work.

```zig
const gil = pyoz.releaseGIL();
defer gil.acquire();
// Work without GIL
```

On free-threaded CPython there is no GIL to release, but the call still detaches
the thread state, which also suspends the per-object critical section of the
method being executed (see [Free-Threading](../guide/free-threading.md)).

### `pyoz.acquireGIL()`

Acquire GIL from non-Python thread.

```zig
const gil = pyoz.acquireGIL();
defer gil.release();
// Python operations
```

## Submodules

### `mod.createSubmodule(name, doc, methods)`

Create a submodule.

```zig
var methods = [_]pyoz.PyMethodDef{
    pyoz.methodDef("func", &pyoz.wrapFunc(fn), "doc"),
    pyoz.methodDefSentinel(),
};

const mod = pyoz.Module{ .ptr = module };
_ = mod.createSubmodule("sub", "Submodule doc", &methods);
```

## Class Features

### Magic Methods

Arithmetic: `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`, `__mod__`, `__pow__`, `__neg__`, `__pos__`, `__abs__`

Comparison: `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`

Bitwise: `__and__`, `__or__`, `__xor__`, `__invert__`, `__lshift__`, `__rshift__`

Sequence: `__len__`, `__getitem__`, `__setitem__`, `__delitem__`, `__contains__`

Iterator: `__iter__`, `__next__`, `__reversed__`

Other: `__repr__`, `__str__`, `__hash__`, `__bool__`, `__call__`, `__enter__`, `__exit__`

### Class Options

```zig
const MyClass = struct {
    pub const __doc__: [*:0]const u8 = "Class docstring";
    pub const __frozen__: bool = true;  // Immutable
    pub const __lock__: bool = false;   // Free-threaded builds: skip per-object locking
    pub const __freelist__ = 8;         // Object pool (ignored on free-threaded builds)
    pub const __features__ = .{ .dict = true, .weakref = true };
    pub const __base__ = pyoz.bases.list;  // Inherit from builtin
    pub const __base__ = pyoz.base(Parent);  // Inherit from PyOZ class
};
```

### Class Attributes

```zig
pub const classattr_PI: f64 = 3.14159;
pub const classattr_NAME: []const u8 = "value";
```
