# Submodules

PyOZ supports creating nested module structures, allowing you to organize your API hierarchically (e.g., `mymodule.math.sqrt()`).

## Creating Submodules

Use `mod.createSubmodule()` during module initialization:

```zig
pub export fn PyInit_mymodule() ?*pyoz.PyObject {
    const module = MyModule.init() orelse return null;
    const mod = pyoz.Module{ .ptr = module };

    _ = mod.createSubmodule("math", "Math utilities", &math_methods) catch return null;
    _ = mod.createSubmodule("io", "I/O utilities", &io_methods) catch return null;

    return module;
}
```

## Defining Submodule Methods

Create a method array with `pyoz.methodDef()` and terminate with `pyoz.methodDefSentinel()`:

```zig
fn math_sqrt(x: f64) !f64 {
    if (x < 0) return error.NegativeValue;
    return @sqrt(x);
}

fn math_pow(base: f64, exp: f64) f64 {
    return std.math.pow(f64, base, exp);
}

var math_methods = [_]pyoz.PyMethodDef{
    pyoz.methodDef("sqrt", &pyoz.wrapFunc(math_sqrt), "Square root"),
    pyoz.methodDef("pow", &pyoz.wrapFunc(math_pow), "Power"),
    pyoz.methodDefSentinel(),  // Required terminator
};
```

## API Reference

| Function | Description |
|----------|-------------|
| `pyoz.methodDef(name, fn, doc)` | Create method definition |
| `pyoz.methodDefSentinel()` | Required null terminator |
| `pyoz.wrapFunc(fn)` | Wrap Zig function for submodule use |
| `mod.createSubmodule(name, doc, methods)` | Create and attach submodule |

## Usage in Python

```python
import mymodule
from mymodule import math

# Via parent module
mymodule.math.sqrt(16)  # 4.0

# Direct import
math.pow(2, 10)         # 1024.0
```

## Complete Example

```zig
const std = @import("std");
const pyoz = @import("PyOZ");

// Main module
fn version() []const u8 { return "1.0.0"; }

// Math submodule functions
fn math_sqrt(x: f64) !f64 {
    if (x < 0) return error.NegativeValue;
    return @sqrt(x);
}

var math_methods = [_]pyoz.PyMethodDef{
    pyoz.methodDef("sqrt", &pyoz.wrapFunc(math_sqrt), "Square root"),
    pyoz.methodDefSentinel(),
};

const MyLib = pyoz.module(.{
    .name = "mylib",
    .funcs = &.{ pyoz.func("version", version, "Get version") },
});

pub export fn PyInit_mylib() ?*pyoz.PyObject {
    const module = MyLib.init() orelse return null;
    const mod = pyoz.Module{ .ptr = module };
    _ = mod.createSubmodule("math", "Math functions", &math_methods) catch return null;
    return module;
}
```

## Next Steps

- [Stubs](stubs.md) - Type stub generation
- [Functions](functions.md) - Function definitions
