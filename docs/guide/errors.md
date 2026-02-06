# Errors and Exceptions

PyOZ provides comprehensive error handling: returning Zig errors as Python exceptions, raising exceptions directly, catching exceptions, and defining custom exception types.

## Returning Zig Errors

Functions returning error unions (`!T`) automatically raise Python exceptions:

```zig
fn divide(a: f64, b: f64) !f64 {
    if (b == 0.0) return error.DivisionByZero;
    return a / b;
}
```

By default, errors become `RuntimeError` with the error name as the message. Use error mappings for specific exception types.

## Error Mapping

Map Zig errors to Python exception types at the module level:

```zig
.error_mappings = &.{
    pyoz.mapError("InvalidInput", .ValueError),
    pyoz.mapError("NotFound", .KeyError),
    pyoz.mapErrorMsg("TooBig", .ValueError, "Value exceeds limit"),
},
```

| Function | Description |
|----------|-------------|
| `pyoz.mapError(name, exc)` | Map error to exception type, uses error name as message |
| `pyoz.mapErrorMsg(name, exc, msg)` | Map error with custom message |

### Available Exception Types

`.Exception`, `.ValueError`, `.TypeError`, `.RuntimeError`, `.IndexError`, `.KeyError`, `.AttributeError`, `.StopIteration`

## Custom Exceptions

Define module-specific exception types:

```zig
.exceptions = &.{
    // Full syntax with documentation
    pyoz.exception("ValidationError", .{ .doc = "Raised when validation fails", .base = .ValueError }),
    // Shorthand syntax
    pyoz.exception("MyError", .RuntimeError),
},
```

Custom exceptions are importable and work like any Python exception:

```python
from mymodule import ValidationError
raise ValidationError("Invalid input")
```

### Raising Custom Exceptions from Zig

Use `getException()` with the index from the `.exceptions` array:

```zig
fn validate(n: i64) ?i64 {
    if (n < 0) {
        MyModule.getException(0).raise("Value must be non-negative");
        return null;
    }
    return n;
}
```

## Raising Built-in Exceptions

Raise Python exceptions directly using helper functions:

| Function | Exception Type |
|----------|----------------|
| `pyoz.raiseValueError(msg)` | `ValueError` |
| `pyoz.raiseTypeError(msg)` | `TypeError` |
| `pyoz.raiseRuntimeError(msg)` | `RuntimeError` |
| `pyoz.raiseKeyError(msg)` | `KeyError` |
| `pyoz.raiseIndexError(msg)` | `IndexError` |
| `pyoz.raiseException(type, msg)` | Custom type |

Return `null` from a `?T` function after raising an exception to propagate it to Python.

## Catching Python Exceptions

When calling Python code from Zig, catch exceptions with `pyoz.catchException()`:

```zig
if (pyoz.catchException()) |*exc| {
    defer @constCast(exc).deinit();  // Always required!
    
    if (exc.isValueError()) {
        // Handle ValueError
    } else {
        exc.reraise();  // Re-raise unknown exceptions
    }
}
```

### PythonException Methods

| Method | Description |
|--------|-------------|
| `.isValueError()`, `.isTypeError()`, etc. | Check exception type |
| `.matches(exc_type)` | Check against specific type |
| `.getMessage()` | Get exception message |
| `.reraise()` | Re-raise the exception |
| `.deinit()` | Clean up (required!) |

### Exception Utility Functions

| Function | Description |
|----------|-------------|
| `pyoz.catchException()` | Catch pending exception |
| `pyoz.exceptionPending()` | Check if exception pending |
| `pyoz.clearException()` | Clear pending exception |

## Optional Return Pattern

Return `?T` (optional) to indicate errors via `null`:

```zig
fn safe_sqrt(x: f64) ?f64 {
    if (x < 0) {
        _ = pyoz.raiseValueError("Cannot take sqrt of negative number");
        return null;
    }
    return @sqrt(x);
}
```

The raise functions return `Null` (Zig's null literal type), so you can combine them into a one-liner:

```zig
fn safe_sqrt(x: f64) ?f64 {
    if (x < 0) return pyoz.raiseValueError("Cannot take sqrt of negative number");
    return @sqrt(x);
}
```

This works with any optional return type (`?i64`, `?f64`, `?[]const u8`, `?*pyoz.PyObject`, etc.).

!!! warning "Always use optional return types with raise functions"
    PyOZ-wrapped functions must return `null` (via `?T`) to signal errors to Python. Setting an exception and returning a non-null value causes Python's `SystemError: returned a result with an exception set`.

**When returning `null`:**

- If an exception is set: exception propagates to Python
- If no exception: returns Python `None`

## Best Practices

1. **Use error unions for recoverable errors** - They're idiomatic Zig and map cleanly to Python exceptions
2. **Map domain-specific errors** - Makes your API more Pythonic
3. **Use custom exceptions for API clarity** - Helps users catch specific error types
4. **Always clean up caught exceptions** - Call `.deinit()` in a defer
5. **Re-raise unknown exceptions** - Don't silently swallow unexpected errors

## Next Steps

- [Enums and Constants](enums.md) - Enums and module constants
- [Types](types.md) - Type conversion reference
