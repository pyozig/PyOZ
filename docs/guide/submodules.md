# Submodules

PyOZ supports creating nested module structures, allowing you to organize your API hierarchically (e.g., `mymodule.math.sqrt()`).

## Creating Submodules

Use `.module_init` to add submodules during module initialization:

```zig
fn setupSubmodules(module: *pyoz.PyObject) callconv(.c) c_int {
    const mod = pyoz.Module{ .ptr = module };
    _ = mod.createSubmodule("math", "Math utilities", &math_methods) catch return -1;
    _ = mod.createSubmodule("io", "I/O utilities", &io_methods) catch return -1;
    return 0;
}

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .module_init = &setupSubmodules,
    // ...
});

pub export fn PyInit_mymodule() ?*pyoz.PyObject {
    return MyModule.init();
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

fn setupSubmodules(module: *pyoz.PyObject) callconv(.c) c_int {
    const mod = pyoz.Module{ .ptr = module };
    _ = mod.createSubmodule("math", "Math functions", &math_methods) catch return -1;
    return 0;
}

const MyLib = pyoz.module(.{
    .name = "mylib",
    .module_init = &setupSubmodules,
    .funcs = &.{ pyoz.func("version", version, "Get version") },
});

pub export fn PyInit_mylib() ?*pyoz.PyObject {
    return MyLib.init();
}
```

## Next Steps

- [Stubs](stubs.md) - Type stub generation
- [Functions](functions.md) - Function definitions
