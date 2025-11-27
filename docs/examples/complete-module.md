# Complete Module Example

This example demonstrates a complete PyOZ module with functions, classes, enums, exceptions, and constants.

## Source Code

```zig
// src/lib.zig
const std = @import("std");
const pyoz = @import("PyOZ");

// ============================================================================
// Functions
// ============================================================================

/// Add two integers
fn add(a: i64, b: i64) i64 {
    return a + b;
}

/// Divide with error handling
fn divide(a: f64, b: f64) !f64 {
    if (b == 0.0) return error.DivisionByZero;
    return a / b;
}

/// Function with optional parameters
fn greet(name: []const u8, greeting: ?[]const u8, times: ?i64) []const u8 {
    _ = name;
    _ = greeting orelse "Hello";
    _ = times orelse 1;
    return "Hello!";
}

/// CPU-intensive work that releases the GIL
fn compute(n: i64) i64 {
    const gil = pyoz.releaseGIL();
    defer gil.acquire();

    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        sum +%= @mod(i *% i, 1000000007);
    }
    return sum;
}

// ============================================================================
// Classes
// ============================================================================

const Point = struct {
    pub const __doc__: [*:0]const u8 = "A 2D point with x and y coordinates.";

    x: f64,
    y: f64,

    pub fn __new__(x: f64, y: f64) Point {
        return .{ .x = x, .y = y };
    }

    pub fn magnitude(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn scale(self: *Point, factor: f64) void {
        self.x *= factor;
        self.y *= factor;
    }

    pub fn __add__(self: *const Point, other: *const Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn __repr__(self: *const Point) []const u8 {
        _ = self;
        return "Point(...)";
    }

    pub fn origin() Point {
        return .{ .x = 0.0, .y = 0.0 };
    }
};

const Counter = struct {
    count: i64,
    step: i64,

    pub fn __new__(initial: i64, step: ?i64) Counter {
        return .{
            .count = initial,
            .step = step orelse 1,
        };
    }

    pub fn increment(self: *Counter) void {
        self.count += self.step;
    }

    pub fn decrement(self: *Counter) void {
        self.count -= self.step;
    }

    pub fn get(self: *const Counter) i64 {
        return self.count;
    }

    pub fn reset(self: *Counter) void {
        self.count = 0;
    }
};

// ============================================================================
// Enums
// ============================================================================

const Priority = enum(i32) {
    Low = 1,
    Medium = 2,
    High = 3,
    Critical = 4,
};

const Status = enum {
    pending,
    active,
    completed,
    cancelled,
};

// ============================================================================
// Module Definition
// ============================================================================

const MyModule = pyoz.module(.{
    .name = "mymodule",
    .doc = "A complete example PyOZ module",
    .funcs = &.{
        pyoz.func("add", add, "Add two integers"),
        pyoz.func("divide", divide, "Divide two numbers"),
        pyoz.kwfunc("greet", greet, "Greet someone"),
        pyoz.func("compute", compute, "CPU-intensive computation (releases GIL)"),
    },
    .classes = &.{
        pyoz.class("Point", Point),
        pyoz.class("Counter", Counter),
    },
    .enums = &.{
        pyoz.enumDef("Priority", Priority),
        pyoz.enumDef("Status", Status),
    },
    .consts = &.{
        pyoz.constant("VERSION", "1.0.0"),
        pyoz.constant("PI", 3.14159265358979),
        pyoz.constant("MAX_VALUE", @as(i64, 1000000)),
    },
    .exceptions = &.{
        pyoz.exception("ValidationError", .{ .doc = "Validation failed", .base = .ValueError }),
    },
    .error_mappings = &.{
        pyoz.mapError("DivisionByZero", .ValueError),
    },
});

pub export fn PyInit_mymodule() ?*pyoz.PyObject {
    return MyModule.init();
}
```

## Usage in Python

```python
import mymodule
from mymodule import Point, Counter, Priority, Status

# Constants
print(mymodule.VERSION)     # "1.0.0"
print(mymodule.PI)          # 3.14159265358979
print(mymodule.MAX_VALUE)   # 1000000

# Functions
print(mymodule.add(2, 3))           # 5
print(mymodule.divide(10, 2))       # 5.0
print(mymodule.greet("World"))      # "Hello!"
print(mymodule.greet("World", "Hi", 3))

# Error handling
try:
    mymodule.divide(1, 0)
except ValueError as e:
    print(f"Error: {e}")  # Error: DivisionByZero

# Classes
p1 = Point(3.0, 4.0)
print(p1.x, p1.y)           # 3.0 4.0
print(p1.magnitude())       # 5.0

p2 = Point(1.0, 1.0)
p3 = p1 + p2                # Uses __add__
print(p3.x, p3.y)           # 4.0 5.0

p1.scale(2.0)
print(p1.x, p1.y)           # 6.0 8.0

origin = Point.origin()     # Static method
print(origin.x, origin.y)   # 0.0 0.0

# Counter
c = Counter(0)
c.increment()
c.increment()
print(c.get())              # 2

c = Counter(10, 5)          # Start at 10, step by 5
c.increment()
print(c.get())              # 15

# Enums
print(Priority.High)        # Priority.High
print(Priority.High.value)  # 3

print(Status.active)        # Status.active
print(Status.active.value)  # "active"

for p in Priority:
    print(f"{p.name} = {p.value}")

# GIL release for threading
import threading
import time

def python_work():
    return sum(range(1000000))

# compute() releases GIL, allowing other threads to run
start = time.time()
t = threading.Thread(target=python_work)
t.start()
result = mymodule.compute(10000000)
t.join()
print(f"Completed in {time.time() - start:.2f}s")
```

## Build and Test

```bash
# Initialize (if starting fresh)
pyoz init mymodule

# Build for development
pyoz develop

# Test
python -c "import mymodule; print(mymodule.add(1, 2))"

# Build release wheel
pyoz build --release

# Publish
export PYPI_TOKEN="pypi-..."
pyoz publish
```

## Project Structure

```
mymodule/
├── src/
│   └── lib.zig
├── build.zig
├── build.zig.zon
├── pyproject.toml
└── dist/
    └── mymodule-1.0.0-cp311-cp311-linux_x86_64.whl
```
