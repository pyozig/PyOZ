# API Reference

Quick reference for PyOZ's public API.

## Module Definition

### `pyoz.module(config)`

Define a Python module.

```zig
const MyModule = pyoz.module(.{
    .name = "mymodule",           // Required: module name
    .doc = "Description",          // Optional: docstring
    .funcs = &.{ ... },           // Optional: functions
    .classes = &.{ ... },         // Optional: classes
    .enums = &.{ ... },           // Optional: enums
    .consts = &.{ ... },          // Optional: constants
    .exceptions = &.{ ... },      // Optional: custom exceptions
    .error_mappings = &.{ ... },  // Optional: error->exception mappings
});
```

## Functions

### `pyoz.func(name, fn, doc)`

Define a basic function.

```zig
pyoz.func("add", add, "Add two numbers")
```

### `pyoz.kwfunc(name, fn, doc)`

Define a function with optional parameters.

```zig
pyoz.kwfunc("greet", greet, "Greet someone")
```

### `pyoz.kwfunc_named(name, fn, doc)`

Define a function with named keyword arguments using `Args(T)`.

```zig
const GreetArgs = struct {
    name: []const u8,
    greeting: []const u8 = "Hello",
};

fn greet(args: pyoz.Args(GreetArgs)) []const u8 { ... }

pyoz.kwfunc_named("greet", greet, "Greet someone")
```

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

Inline string formatter using Zig's `std.fmt` syntax. Returns `[*:0]const u8`.

```zig
// Use with raise functions for dynamic error messages:
return pyoz.raiseValueError(pyoz.fmt("value {d} exceeds limit {d}", .{ val, limit }));

// General formatting:
const msg = pyoz.fmt("hello {s}", .{"world"});
```

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

### Special Types

| Type | Python |
|------|--------|
| `pyoz.Complex` | `complex` |
| `pyoz.Date` | `datetime.date` |
| `pyoz.Time` | `datetime.time` |
| `pyoz.DateTime` | `datetime.datetime` |
| `pyoz.TimeDelta` | `datetime.timedelta` |
| `pyoz.Bytes` | `bytes` |
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
