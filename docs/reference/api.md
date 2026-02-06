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
    pub const __base__ = pyoz.bases.list;  // Inheritance
};
```

### Class Attributes

```zig
pub const classattr_PI: f64 = 3.14159;
pub const classattr_NAME: []const u8 = "value";
```
