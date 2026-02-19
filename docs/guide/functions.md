# Functions

PyOZ provides three ways to expose Zig functions to Python, depending on your parameter needs.

## Basic Functions (`pyoz.func`)

For functions with only required positional arguments:

```zig
fn add(a: i64, b: i64) i64 {
    return a + b;
}

.funcs = &.{
    pyoz.func("add", add, "Add two integers"),
},
```

All parameters are required and positional in Python.

## Optional Parameters (`pyoz.kwfunc`)

For functions where some parameters are optional, use `?T` types:

```zig
fn greet(name: []const u8, greeting: ?[]const u8, times: ?i64) []const u8 {
    const msg = greeting orelse "Hello";
    const n = times orelse 1;
    // ...
}

.funcs = &.{
    pyoz.kwfunc("greet", greet, "Greet someone"),
},
```

In Python: `greet("World")`, `greet("World", "Hi")`, or `greet("World", greeting="Hi", times=3)`

Parameters with `?T` default to `None` and can be passed by keyword.

## Named Arguments with Defaults (`pyoz.kwfunc_named`)

For complex functions with multiple optional parameters and non-None defaults, define an Args struct:

```zig
const GreetArgs = struct {
    name: []const u8,               // Required (no default)
    greeting: []const u8 = "Hello", // Optional, defaults to "Hello"
    times: i64 = 1,                 // Optional, defaults to 1
    excited: bool = false,          // Optional, defaults to false
};

fn greet(args: pyoz.Args(GreetArgs)) []const u8 {
    const a = args.value;
    // Use a.name, a.greeting, a.times, a.excited
}

.funcs = &.{
    pyoz.kwfunc_named("greet", greet, "Greet with options"),
},
```

Struct fields with defaults become optional keyword arguments. Fields without defaults are required.

## Return Types

| Zig Return | Python Result |
|------------|---------------|
| `i64`, `f64`, etc. | `int`, `float` |
| `[]const u8` | `str` |
| `bool` | `bool` |
| `void` | `None` |
| `?T` | `T` or `None` |
| `!T` | `T` or raises exception |
| `struct { T, U }` | `tuple` |
| `[]const T` | `list` |
| `pyoz.Owned(T)` | Same as `T` (frees backing memory) |
| `pyoz.Signature(T, "S")` | Stub shows `S` instead of inferred type |

## Error Handling

Functions returning `!T` (error union) automatically raise Python exceptions:

```zig
fn divide(a: f64, b: f64) !f64 {
    if (b == 0.0) return error.DivisionByZero;
    return a / b;
}
```

PyOZ automatically maps well-known error names to the correct Python exception (e.g., `error.DivisionByZero` becomes `ZeroDivisionError`, `error.TypeError` becomes `TypeError`). Unrecognized errors fall back to `RuntimeError`. Use explicit error mappings for custom error names or messages:

```zig
.error_mappings = &.{
    pyoz.mapError("InvalidInput", .ValueError),
    pyoz.mapErrorMsg("TooBig", .ValueError, "Value exceeds limit"),
},
```

See [Error Handling](errors.md) for the full mapping table and details.

## GIL Release

For CPU-intensive work, release the GIL to allow other Python threads to run:

```zig
fn heavy_compute(n: i64) i64 {
    const gil = pyoz.releaseGIL();
    defer gil.acquire();
    
    // Computation runs without GIL
    // Don't access Python objects here!
    var sum: i64 = 0;
    // ...
    return sum;
}
```

See [GIL Management](gil.md) for details.

## Stub Return Type Override

When a function returns `?T` only to signal errors (not to return `None` to Python), the generated stub shows `T | None` — which is misleading. Use `pyoz.Signature(T, "stub_string")` to override the stub annotation:

```zig
fn validate(n: i64) pyoz.Signature(?i64, "int") {
    if (n < 0) return pyoz.raiseValueError("must be non-negative");
    return .{ .value = n };
}
```

The stub shows `-> int` instead of `-> int | None`. At runtime, `Signature` is transparent — PyOZ unwraps the `.value` field automatically. See [Type Stubs: Return Type Override](stubs.md#return-type-override-signature) for more details.

## Docstrings

The third argument to function registrations becomes the Python docstring:

```zig
pyoz.func("add", add, "Add two integers.\n\nReturns the sum."),
```

## Summary

| Registration | When to Use |
|--------------|-------------|
| `pyoz.func(name, fn, doc)` | All required positional args |
| `pyoz.kwfunc(name, fn, doc)` | Optional args with `?T` (default to None) |
| `pyoz.kwfunc_named(name, fn, doc)` | Named kwargs with custom defaults via `Args(T)` |

## Next Steps

- [Types](types.md) - Type conversion reference
- [Errors](errors.md) - Exception handling
- [Classes](classes.md) - Defining classes
