# Quick Start

This guide walks you through creating your first PyOZ module using the `pyoz` CLI.

## Prerequisites

### Option 1: Download Prebuilt Binaries

Download the latest `pyoz` binary for your platform from the [GitHub Releases](https://github.com/dzonerzy/PyOZ/releases) page and add it to your PATH.

### Option 2: Build from Source

```bash
git clone https://github.com/dzonerzy/PyOZ.git
cd PyOZ
zig build
```

The `pyoz` binary will be in `zig-out/bin/`. Add it to your PATH or use the full path.

## Your First Module

### Step 1: Initialize a Project

```bash
pyoz init mymodule
cd mymodule
```

This creates a project with:

```
mymodule/
├── build.zig
├── build.zig.zon
├── pyproject.toml
├── README.md
├── .gitignore
└── src/
    └── lib.zig       # Your module code
```

### Step 2: Edit Your Module

Open `src/lib.zig` - it already contains a starter template:

```zig
const pyoz = @import("PyOZ");

// ============================================================================
// Define your functions here
// ============================================================================

/// Add two integers
fn add(a: i64, b: i64) i64 {
    return a + b;
}

/// Multiply two floats
fn multiply(a: f64, b: f64) f64 {
    return a * b;
}

/// Greet someone by name
fn greet(name: []const u8) ![]const u8 {
    _ = name;
    return "Hello from mymodule!";
}

// ============================================================================
// Module definition
// ============================================================================

pub const Module = pyoz.module(.{
    .name = "mymodule",
    .doc = "mymodule - A Python extension module built with PyOZ",
    .funcs = &.{
        pyoz.func("add", add, "Add two integers"),
        pyoz.func("multiply", multiply, "Multiply two floats"),
        pyoz.func("greet", greet, "Return a greeting"),
    },
    .classes = &.{},
});

// Module initialization function
pub export fn PyInit_mymodule() ?*pyoz.PyObject {
    return Module.init();
}
```

### Step 3: Build the Wheel

```bash
pyoz build
```

This compiles your module and creates a wheel in `dist/`:

```
dist/
└── mymodule-0.1.0-cp310-cp310-linux_x86_64.whl
```

### Step 4: Install and Test

```bash
pip install dist/mymodule-*.whl
python -c "import mymodule; print(mymodule.add(2, 3))"  # 5
```

## Development Workflow

PyOZ provides several commands to streamline your workflow:

| Command | Description |
|---------|-------------|
| `pyoz build` | Build a debug wheel |
| `pyoz build --release` | Build an optimized release wheel |
| `pyoz develop` | Build and install in development mode (symlinked) |
| `pyoz publish` | Publish wheel(s) to PyPI |

For detailed CLI options, see the [CLI Reference](cli/build.md).

## Adding a Class

Edit `src/lib.zig` to add a class:

```zig
const pyoz = @import("PyOZ");
const std = @import("std");

// Define a struct - it becomes a Python class
const Point = struct {
    x: f64,
    y: f64,

    // Methods take *const Self or *Self as first parameter
    pub fn magnitude(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn scale(self: *Point, factor: f64) void {
        self.x *= factor;
        self.y *= factor;
    }

    // Static methods don't take self
    pub fn origin() Point {
        return .{ .x = 0.0, .y = 0.0 };
    }
};

pub const Module = pyoz.module(.{
    .name = "mymodule",
    .doc = "Module with a Point class",
    .funcs = &.{},
    .classes = &.{
        pyoz.class("Point", Point),
    },
});

pub export fn PyInit_mymodule() ?*pyoz.PyObject {
    return Module.init();
}
```

Use it from Python:

```python
import mymodule

# Create instances (fields become __init__ parameters)
p = mymodule.Point(3.0, 4.0)
print(p.x, p.y)           # 3.0 4.0
print(p.magnitude())      # 5.0

# Mutating methods work
p.scale(2.0)
print(p.x, p.y)           # 6.0 8.0

# Static methods
origin = mymodule.Point.origin()
print(origin.x, origin.y) # 0.0 0.0
```

## Error Handling

Zig errors automatically become Python exceptions:

```zig
fn divide(a: f64, b: f64) !f64 {
    if (b == 0.0) {
        return error.DivisionByZero;
    }
    return a / b;
}

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .funcs = &.{
        pyoz.func("divide", divide, "Divide two numbers"),
    },
    // Map Zig errors to Python exceptions
    .error_mappings = &.{
        pyoz.mapError("DivisionByZero", .RuntimeError),
    },
});
```

```python
import mymodule

try:
    mymodule.divide(10, 0)
except RuntimeError as e:
    print(f"Error: {e}")  # Error: DivisionByZero
```

## Module Constants

Add compile-time constants to your module:

```zig
const MyModule = pyoz.module(.{
    .name = "mymodule",
    .funcs = &.{},
    .consts = &.{
        pyoz.constant("VERSION", "1.0.0"),
        pyoz.constant("PI", 3.14159265358979),
        pyoz.constant("MAX_SIZE", @as(i64, 1000)),
        pyoz.constant("DEBUG", false),
    },
});
```

```python
import mymodule

print(mymodule.VERSION)   # "1.0.0"
print(mymodule.PI)        # 3.14159265358979
print(mymodule.MAX_SIZE)  # 1000
print(mymodule.DEBUG)     # False
```

## Enums

Define Python enums from Zig enums:

```zig
// Integer enum (becomes IntEnum)
const Color = enum(i32) {
    Red = 1,
    Green = 2,
    Blue = 3,
};

// String enum (becomes StrEnum) - no explicit integer type
const Status = enum {
    pending,
    active,
    completed,
};

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .funcs = &.{},
    // Auto-detects IntEnum vs StrEnum based on tag type
    .enums = &.{
        pyoz.enumDef("Color", Color),
        pyoz.enumDef("Status", Status),
    },
});
```

```python
import mymodule

# Color is an IntEnum
print(mymodule.Color.Red)        # Color.Red
print(mymodule.Color.Red.value)  # 1

# Status is a StrEnum
print(mymodule.Status.pending)        # Status.pending
print(mymodule.Status.pending.value)  # "pending"
```

## Next Steps

- [Functions Guide](guide/functions.md) - Optional parameters, keyword arguments
- [Classes Guide](guide/classes.md) - Magic methods, operators, inheritance
- [Properties Guide](guide/properties.md) - Computed properties, getters/setters
- [Type Mappings](guide/types.md) - Complete type conversion reference
- [Error Handling](guide/errors.md) - Custom exceptions, error mapping
- [CLI Reference](cli/build.md) - Detailed CLI options
