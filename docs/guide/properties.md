# Properties

PyOZ provides three ways to define properties on classes.

## Automatic Field Properties

By default, all struct fields become read/write Python properties with automatic type conversion:

```zig
const Point = struct {
    x: f64,
    y: f64,
};
```

Python: `p.x`, `p.y` work as getters and setters automatically.

## Custom Getters/Setters (`get_X`/`set_X`)

Override default behavior or add computed properties using the `get_` and `set_` prefix convention:

```zig
const BoundedValue = struct {
    _value: f64,

    // Custom getter
    pub fn get_value(self: *const BoundedValue) f64 {
        return self._value;
    }

    // Custom setter with validation
    pub fn set_value(self: *BoundedValue, v: f64) void {
        self._value = @max(0.0, @min(100.0, v));  // Clamp to [0, 100]
    }
};
```

For **computed properties** (no backing field), just define `get_X` without a matching field:

```zig
pub fn get_length(self: *const Point) f64 {
    return @sqrt(self.x * self.x + self.y * self.y);
}

pub fn set_length(self: *Point, len: f64) void {
    // Scale point to have given length
    const current = @sqrt(self.x * self.x + self.y * self.y);
    if (current > 0) {
        const factor = len / current;
        self.x *= factor;
        self.y *= factor;
    }
}
```

Omit `set_X` to make a read-only property.

## Declarative Properties (`pyoz.property`)

For explicit configuration with documentation:

```zig
const Temperature = struct {
    _celsius: f64,
    const Self = @This();

    pub const celsius = pyoz.property(.{
        .get = struct {
            fn get(self: *const Self) f64 { return self._celsius; }
        }.get,
        .set = struct {
            fn set(self: *Self, v: f64) void {
                self._celsius = @max(-273.15, v);  // Clamp to absolute zero
            }
        }.set,
        .doc = "Temperature in Celsius",
    });

    // Read-only property (no .set)
    pub const kelvin = pyoz.property(.{
        .get = struct {
            fn get(self: *const Self) f64 { return self._celsius + 273.15; }
        }.get,
        .doc = "Temperature in Kelvin (read-only)",
    });
};
```

### Configuration Options

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `.get` | `fn(*const Self) T` | Yes | Getter function |
| `.set` | `fn(*Self, T) void` | No | Setter (omit for read-only) |
| `.doc` | `[*:0]const u8` | No | Property docstring |

## Property Docstrings

For `get_X`/`set_X` style, use the `fieldname__doc__` constant:

```zig
pub const length__doc__: [*:0]const u8 = "The vector length";
```

## Read-Only Properties

Three ways to make properties read-only:

1. **Only define getter** - no `set_X` function
2. **Use `pyoz.property` without `.set`**
3. **Frozen class** - set `pub const __frozen__: bool = true;` on the struct

## When to Use Each

| Approach | Best For |
|----------|----------|
| Automatic fields | Simple data containers |
| `get_X`/`set_X` | Custom logic, computed values |
| `pyoz.property()` | Explicit config, documentation |

## Next Steps

- [Classes](classes.md) - Full class reference
- [Types](types.md) - Type conversion
