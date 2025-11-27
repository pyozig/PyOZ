# Classes

PyOZ exposes Zig structs as Python classes automatically. Define a struct, register it with `pyoz.class()`, and PyOZ generates a full Python class with constructor, properties, and methods.

## Defining a Class

```zig
const Point = struct {
    x: f64,
    y: f64,
};

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .classes = &.{
        pyoz.class("Point", Point),
    },
});
```

This automatically creates:

- A constructor: `Point(x=1.0, y=2.0)`
- Read/write properties for `x` and `y`
- Automatic type conversion between Zig and Python

## Constructors

By default, the constructor accepts all struct fields as arguments. For custom initialization, define `__new__`:

```zig
pub fn __new__(initial: i64, step: ?i64) Counter {
    return .{ .count = initial, .step = step orelse 1 };
}
```

Optional parameters (`?T`) become keyword arguments with `None` as default.

## Methods

PyOZ auto-detects method types based on the first parameter:

| First Parameter | Method Type | Python Usage |
|-----------------|-------------|--------------|
| `*Self` or `*const Self` | Instance method | `obj.method()` |
| `comptime cls: type` | Class method | `Class.method()` |
| Anything else | Static method | `Class.method()` |

Use `*const Self` for methods that don't modify the instance.

## Docstrings

Add documentation using special constants:

| Constant | Purpose |
|----------|---------|
| `pub const __doc__` | Class docstring |
| `pub const fieldname__doc__` | Field docstring |
| `pub const methodname__doc__` | Method docstring |

All must be `[*:0]const u8` type.

## Magic Methods

PyOZ supports Python's special methods. Define them as regular Zig functions with matching names.

### Operators

| Category | Methods |
|----------|---------|
| Arithmetic | `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`, `__mod__`, `__pow__`, `__matmul__` |
| Unary | `__neg__`, `__pos__`, `__abs__`, `__invert__` |
| Comparison | `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__` |
| Bitwise | `__and__`, `__or__`, `__xor__`, `__lshift__`, `__rshift__` |
| In-place | `__iadd__`, `__isub__`, `__imul__`, etc. |
| Reflected | `__radd__`, `__rsub__`, `__rmul__`, etc. |

**Signature pattern:** Binary operators take `(self: *const T, other: *const T)` and return `T`. In-place operators take `(self: *T, other: *const T)` and return `void`. Reflected operators take `(self: *const T, other: *pyoz.PyObject)` for handling Python scalars.

### String Representation

| Method | Purpose |
|--------|---------|
| `__repr__` | Developer representation (shown in REPL) |
| `__str__` | User-friendly string (`str(obj)`) |
| `__hash__` | Hash value for use in sets/dicts |

### Type Conversion

| Method | Purpose |
|--------|---------|
| `__bool__` | Boolean evaluation (`if obj:`) |
| `__int__` | `int(obj)` |
| `__float__` | `float(obj)` |
| `__index__` | Used in slicing, `range()`, etc. |
| `__complex__` | `complex(obj)` |

### Callable Objects

Define `__call__` to make instances callable:

```zig
pub fn __call__(self: *const Adder, x: i64) i64 {
    return self.value + x;
}
```

Python: `adder = Adder(10); adder(5)  # 15`

## Protocols

### Sequence Protocol

Make your class behave like a list:

| Method | Python Syntax |
|--------|---------------|
| `__len__` | `len(obj)` |
| `__getitem__(index: i64) !T` | `obj[i]` |
| `__setitem__(index: i64, value: T) !void` | `obj[i] = value` |
| `__delitem__(index: i64) !void` | `del obj[i]` |
| `__contains__(value: T) bool` | `value in obj` |

Return errors (e.g., `error.IndexOutOfBounds`) to raise Python exceptions. Negative indices are passed as-is; handle them in your implementation.

### Iterator Protocol

| Method | Purpose |
|--------|---------|
| `__iter__(self: *T) *T` | Return iterator (usually self) |
| `__next__(self: *T) ?T` | Return next item or `null` for StopIteration |
| `__reversed__(self: *T) *T` | Return reversed iterator |

Store iteration state in instance fields.

### Context Manager Protocol

| Method | Purpose |
|--------|---------|
| `__enter__(self: *T) *T` | Enter `with` block, return context |
| `__exit__(self: *T) bool` | Exit block; return `true` to suppress exceptions |

### Descriptor Protocol

For custom attribute behavior on other classes:

| Method | Purpose |
|--------|---------|
| `__get__(self, obj: ?*PyObject) T` | Attribute access |
| `__set__(self, obj: ?*PyObject, value: T)` | Attribute assignment |
| `__delete__(self, obj: ?*PyObject)` | Attribute deletion |

### Dynamic Attributes

| Method | Purpose |
|--------|---------|
| `__getattr__(name: []const u8) !T` | Called when attribute not found |
| `__setattr__(name: []const u8, value: *PyObject)` | Called for all attribute assignments |
| `__delattr__(name: []const u8) !void` | Called when deleting attribute |

## Class Configuration

### Frozen (Immutable) Classes

```zig
pub const __frozen__: bool = true;
```

Prevents attribute modification. Frozen classes should implement `__hash__` and `__eq__`.

### Feature Flags

```zig
pub const __features__ = .{ .dict = true, .weakref = true };
```

- `.dict = true` - Enables dynamic attribute storage (`obj.custom = "value"`)
- `.weakref = true` - Enables weak references

### Class Attributes

Prefix constants with `classattr_` to make them class-level:

```zig
pub const classattr_PI: f64 = 3.14159;
```

Python: `Circle.PI  # 3.14159`

### Inheritance

Extend Python built-in types:

```zig
pub const __base__ = pyoz.bases.list;  // or pyoz.bases.dict
```

Use `pyoz.object(self)` to get the underlying Python object for calling Python API functions.

For dict subclasses, implement `__missing__` to handle missing keys.

## GC Support

For classes holding Python object references, implement garbage collection hooks:

| Method | Purpose |
|--------|---------|
| `__traverse__(visitor: pyoz.GCVisitor) c_int` | Report held references |
| `__clear__()` | Release references to break cycles |

Call `visitor.call(self.stored_obj)` for each `?*PyObject` field.

## Method Chaining

Methods returning `*Self` or `*const Self` enable chaining. PyOZ automatically handles Python reference counting:

```zig
pub fn add(self: *Builder, n: i64) *Builder {
    self.value += n;
    return self;
}
```

Python: `b.add(1).add(2).add(3)`

## Next Steps

- [Properties](properties.md) - Custom getters/setters
- [Types](types.md) - Type conversion reference
- [Errors](errors.md) - Exception handling
