# Enums and Constants

PyOZ supports exposing Zig enums as Python enums (`IntEnum` or `StrEnum`) and defining module-level constants.

## Enums

Use `pyoz.enumDef()` to expose a Zig enum. PyOZ automatically detects the Python enum type:

```zig
.enums = &.{
    pyoz.enumDef("Color", Color),
    pyoz.enumDef("Status", Status),
},
```

### Auto-Detection Rules

| Zig Definition | Python Type | Values |
|----------------|-------------|--------|
| `enum(i32) { Red = 1, Green = 2 }` | `IntEnum` | Integer values |
| `enum { pending, active }` | `StrEnum` | Field names as strings |

**IntEnum** - Use when you have explicit integer tags:
```zig
const HttpStatus = enum(i32) { OK = 200, NotFound = 404 };
```

**StrEnum** - Use for plain enums without explicit values:
```zig
const TaskStatus = enum { pending, in_progress, completed };
```

### Using Enums in Python

```python
from mymodule import HttpStatus, TaskStatus

# IntEnum - compare with integers
HttpStatus.OK == 200          # True
HttpStatus(404)               # HttpStatus.NotFound

# StrEnum - compare with strings  
TaskStatus.pending == "pending"  # True

# Iterate
for status in HttpStatus:
    print(f"{status.name} = {status.value}")
```

### Reserved Keywords

Zig keywords need escaping with `@""`:

```zig
const LogLevel = enum { debug, info, warning, @"error" };
```

In Python, use them normally: `LogLevel.error`

### Enums in Functions

Enums work as parameters and return types:

```zig
fn get_color_name(color: Color) []const u8 {
    return switch (color) {
        .Red => "red",
        .Green => "green",
    };
}
```

## Constants

Use `pyoz.constant()` for module-level constants:

```zig
.consts = &.{
    pyoz.constant("VERSION", "1.0.0"),
    pyoz.constant("PI", 3.14159),
    pyoz.constant("MAX_VALUE", @as(i64, 1000000)),
    pyoz.constant("DEBUG", false),
},
```

### Supported Types

| Zig Type | Python Type |
|----------|-------------|
| Integers (`i32`, `i64`, etc.) | `int` |
| Floats (`f32`, `f64`) | `float` |
| `bool` | `bool` |
| `[]const u8` | `str` |

Use `@as()` to specify exact integer/float types when needed.

## Class-Level Constants

Use the `classattr_` prefix for class attributes:

```zig
const Circle = struct {
    radius: f64,
    
    pub const classattr_PI: f64 = 3.14159;
    pub const classattr_UNIT: []const u8 = "meters";
};
```

```python
Circle.PI    # 3.14159
Circle.UNIT  # "meters"
```

## Next Steps

- [Functions](functions.md) - Function definitions
- [Classes](classes.md) - Class definitions
