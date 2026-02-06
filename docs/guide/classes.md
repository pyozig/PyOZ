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

## Private Fields

Fields starting with an underscore (`_`) are treated as **private** and are not exposed to Python:

```zig
const MyClass = struct {
    // Public fields - exposed to Python
    name: []const u8,
    value: i64,
    
    // Private fields - NOT exposed to Python
    _internal_counter: i64,
    _cache: ?SomeType,
};
```

Private fields:

- Are **NOT** exposed as Python properties (accessing `obj._internal_counter` raises `AttributeError`)
- Are **NOT** included in `__init__` arguments (only `name` and `value` above)
- Are **NOT** included in generated `.pyi` type stubs
- Are zero-initialized when the object is created
- Can still be accessed and modified by Zig methods

This is useful for:

- Internal implementation details that shouldn't be part of the public API
- Fields with types that can't be converted to Python (e.g., Zig-specific structs)
- Caches, buffers, or state that users shouldn't manipulate directly

```zig
const Counter = struct {
    count: i64,           // Public: users can read/write this
    _step: i64,           // Private: internal implementation detail
    
    pub fn increment(self: *Counter) void {
        self.count += self._step;  // Methods can access private fields
    }
};
```

Python usage:
```python
c = Counter(0)      # Only public field in __init__
c.count             # OK: 0
c.increment()       # OK: uses _step internally
c._step             # AttributeError: private field not exposed
```

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

## Generic Type Syntax (`__class_getitem__`)

Enable `MyClass[int]` subscript syntax (PEP 560) by declaring a single constant:

```zig
const Point = struct {
    x: f64,
    y: f64,

    pub const __class_getitem__ = true;
};
```

Python:
```python
Point[int]          # returns types.GenericAlias on Python 3.9+
Point[int, float]   # multiple type parameters
```

This is useful for type annotations and generic patterns:
```python
def transform(points: list[Point[float]]) -> Point[float]:
    ...
```

Works in ABI3 mode. On Python 3.8, falls back to returning the class itself.

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

### Freelist (Object Pooling)

For classes that are frequently created and destroyed, enable a freelist to reuse deallocated objects instead of going through the allocator:

```zig
const Token = struct {
    kind: i64,
    start: i64,
    end: i64,

    pub const __freelist__: usize = 32;  // pool up to 32 objects
};
```

When an object is garbage-collected, it's pushed onto the freelist instead of being freed. The next `Token(...)` call reuses a pooled object, skipping allocation. Objects are fully re-initialized on reuse.

Only applies to simple types (no `__dict__`, no weakrefs). The freelist is a fixed-size static array — once full, excess objects are freed normally.

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

## Custom Cleanup (`__del__`)

Define `__del__` to run custom cleanup when Python garbage-collects your object. This is called during `tp_dealloc`, before the object is freed.

```zig
const Resource = struct {
    handle: i64,
    _freed: bool,

    pub fn __new__(handle: i64) Resource {
        return .{ .handle = handle, ._freed = false };
    }

    pub fn __del__(self: *Resource) void {
        // Free C memory, close file handles, release resources, etc.
        self._freed = true;
        self.handle = -1;
    }

    pub fn is_valid(self: *const Resource) bool {
        return self.handle >= 0 and !self._freed;
    }
};
```

Python:
```python
r = Resource(42)
r.is_valid()  # True
del r         # __del__ runs automatically
```

**Signature:** `pub fn __del__(self: *Self) void`

`__del__` is called before weakref cleanup, `__dict__` cleanup, and object deallocation, so all fields and state are still accessible. Works in both normal and ABI3 modes. Types that don't define `__del__` have zero overhead — the check is resolved at compile time.

Use this for C interop structs that allocate memory, open file descriptors, or hold external resources that need explicit cleanup.

## Method Chaining

Methods returning `*Self` or `*const Self` enable chaining. PyOZ automatically handles Python reference counting:

```zig
pub fn add(self: *Builder, n: i64) *Builder {
    self.value += n;
    return self;
}
```

Python: `b.add(1).add(2).add(3)`

## Cross-Class References

When a module defines multiple classes, methods on one class can accept or return instances of another class in the same module. PyOZ handles this automatically — no special syntax needed.

```zig
const Point = struct {
    x: f64,
    y: f64,

    pub fn magnitude(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }
};

const Line = struct {
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,

    /// Returns a Point — cross-class return
    pub fn start_point(self: *const Line) Point {
        return .{ .x = self.x1, .y = self.y1 };
    }

    /// Accepts two Points — cross-class arguments
    pub fn from_points(p1: *const Point, p2: *const Point) Line {
        return .{ .x1 = p1.x, .y1 = p1.y, .x2 = p2.x, .y2 = p2.y };
    }
};

const MyModule = pyoz.module(.{
    .name = "geometry",
    .classes = &.{
        pyoz.class("Point", Point),
        pyoz.class("Line", Line),
    },
});
```

Python:
```python
import geometry

p1 = geometry.Point(1.0, 2.0)
p2 = geometry.Point(4.0, 6.0)

line = geometry.Line.from_points(p1, p2)  # accepts Point instances
start = line.start_point()                # returns a Point instance
print(start.magnitude())                  # full Point API works
```

Cyclic references work too — class A methods can accept/return class B and vice versa, as long as both are registered in the same module.

## Next Steps

- [Properties](properties.md) - Custom getters/setters
- [Types](types.md) - Type conversion reference
- [Errors](errors.md) - Exception handling
