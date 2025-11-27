# GIL Management

Python's Global Interpreter Lock (GIL) prevents multiple threads from executing Python bytecode simultaneously. PyOZ provides utilities to release the GIL during CPU-intensive Zig code, allowing other Python threads to run concurrently.

## When to Release the GIL

**DO release** when:
- Performing CPU-intensive computations
- Doing I/O operations (file, network)
- Calling external C libraries that don't need Python
- Processing large arrays without Python object access

**DON'T release** when:
- Accessing Python objects (`*pyoz.PyObject`)
- Calling Python C API functions
- Using PyOZ conversion functions
- The operation is very short (overhead not worth it)

## Releasing the GIL

Use `pyoz.releaseGIL()` with defer for automatic reacquisition:

```zig
fn heavy_compute(n: i64) i64 {
    const gil = pyoz.releaseGIL();
    defer gil.acquire();  // Always reacquire before returning
    
    // Computation runs without GIL
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        sum +%= @mod(i *% i, 1000000007);
    }
    return sum;
}
```

## API Reference

### From Python Threads (most common)

| Function | Description |
|----------|-------------|
| `pyoz.releaseGIL()` | Release GIL, returns `GILGuard` |
| `GILGuard.acquire()` | Reacquire GIL (call before returning) |

### From Non-Python Threads

| Function | Description |
|----------|-------------|
| `pyoz.acquireGIL()` | Acquire GIL from a Zig thread, returns `GILState` |
| `GILState.release()` | Release GIL when done |

## Best Practices

### 1. Always Use `defer`

```zig
const gil = pyoz.releaseGIL();
defer gil.acquire();  // Guaranteed reacquisition even on errors
```

### 2. Extract Data Before Releasing

```zig
fn process(obj: *pyoz.PyObject) void {
    // Extract data while holding GIL
    const value = pyoz.Conversions.fromPy(i64, obj) catch return;
    
    const gil = pyoz.releaseGIL();
    defer gil.acquire();
    
    // Use extracted value, NOT the Python object
    _ = process_value(value);
}
```

### 3. Keep GIL-Free Sections Focused

```zig
fn process(data: pyoz.BufferView(f64), callback: *pyoz.PyObject) ?f64 {
    // Phase 1: Computation without GIL
    var result: f64 = 0;
    {
        const gil = pyoz.releaseGIL();
        defer gil.acquire();
        for (data.data) |v| result += expensive_math(v);
    }
    
    // Phase 2: Python callback (needs GIL - already reacquired)
    return call_python_callback(callback, result);
}
```

## Common Mistake

**Never hold Python references across GIL release:**

```zig
// WRONG - obj may be garbage collected!
fn bad(obj: *pyoz.PyObject) void {
    const gil = pyoz.releaseGIL();
    _ = obj;  // Dangerous!
    gil.acquire();
}
```

## Next Steps

- [NumPy](numpy.md) - NumPy array integration
- [Functions](functions.md) - Function definitions
