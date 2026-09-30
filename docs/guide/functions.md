# Functions

PyOZ provides two ways to expose Zig functions to Python, depending on your parameter needs.

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

## Keyword Arguments (`pyoz.kwfunc`)

For functions with optional or keyword parameters, define an Args struct using `pyoz.Args(T)`:

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
    pyoz.kwfunc("greet", greet, "Greet with options"),
},
```

In Python: `greet("World")`, `greet("World", "Hi")`, or `greet("World", greeting="Hi", times=3)`

`pyoz.func` works too: a function whose only parameter is `pyoz.Args(T)` is
detected and registered with keyword arguments either way. Errors returned
from keyword functions go through the module's `.error_mappings`, like
positional functions.

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

## Async Functions

Wrap a function with `pyoz.asyncFn` to make it awaitable from asyncio; it runs
on a `std.Io` task without the GIL and supports cancellation:

```zig
fn fetch(io: std.Io, ms: i64) !i64 {
    try io.sleep(.fromMilliseconds(ms), .awake);
    return ms;
}
.funcs = &.{ pyoz.func("fetch", pyoz.asyncFn(fetch), "Sleep, then return") },
```

```python
await mymod.fetch(100)
```

See [Async](async.md) for parameters, cancellation and performance.

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
| `pyoz.kwfunc(name, fn, doc)` | Named kwargs with defaults via `Args(T)` |

## Auto-Scan Alternative

If your function names match between Zig and Python (which they usually do), you can skip explicit registration entirely using `.from`. PyOZ auto-detects functions, their calling convention (`Args(T)` → kwargs), and `name__doc__` docstrings:

```zig
// math.zig
pub fn add(a: i64, b: i64) i64 { return a + b; }
pub const add__doc__ = "Add two integers";
```

```zig
// root
pub const Example = pyoz.module(.{
    .name = "example",
    .from = &.{ @import("math.zig") },
});
```

See [Auto-Scan (.from)](from.md) for the full guide.

## Next Steps

- [Auto-Scan (.from)](from.md) - Zero-boilerplate module definitions
- [Types](types.md) - Type conversion reference
- [Errors](errors.md) - Exception handling
- [Classes](classes.md) - Defining classes
