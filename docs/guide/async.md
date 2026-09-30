# Async

`pyoz.asyncFn` turns a Zig function into a Python function that returns an
`asyncio.Future`. It is built on Zig 0.16's `std.Io`.

```zig
const std = @import("std");
const pyoz = @import("PyOZ");

fn fetch_sum(io: std.Io, delay_ms: i64, a: i64, b: i64) !i64 {
    try io.sleep(.fromMilliseconds(delay_ms), .awake); // cancellation point
    return a + b;
}

fn greet(arena: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "hello, {s}!", .{name});
}

pub const Module = pyoz.module(.{
    .name = "mymod",
    .funcs = &.{
        pyoz.func("fetch_sum", pyoz.asyncFn(fetch_sum), "Sleep, then add"),
        pyoz.func("greet", pyoz.asyncFn(greet), "Build a greeting"),
    },
});
```

```python
import asyncio, mymod

async def main():
    print(await mymod.fetch_sum(100, 2, 3))            # 5
    print(await asyncio.gather(*(mymod.greet(n) for n in "abc")))
    async with asyncio.timeout(0.05):                  # cancels the Zig task
        await mymod.fetch_sum(10_000, 0, 0)

asyncio.run(main())
```

## How it works

- Each call runs `f` on its own `std.Io` task, **without the GIL** and without
  an attached Python thread state, so it runs in parallel with Python code and
  with other tasks on every CPython build (regular, free-threaded, ABI3).
- The returned future is *hot*: work starts immediately, as with
  `asyncio.create_task`. Call async functions from inside a coroutine (a
  running event loop is required).
- **Cancellation propagates into Zig.** Cancelling the Python task
  (`task.cancel()`, `asyncio.timeout`, `wait_for`, ...) cancels the Zig task:
  its next `Io` call (sleep, file, network, `io.checkCancel()`) returns
  `error.Canceled`. Long CPU loops should call `io.checkCancel()` periodically.
- The event loop never blocks on Zig. Workers never touch Python while
  finishing: completed jobs are pushed onto a lock-free per-loop queue and
  resolved in batches on the loop thread.

## Parameters and results

Optional leading parameters, in this order:

| Parameter | Provides |
|-----------|----------|
| `std.Io` | The runtime's `Io` (also available anywhere as `pyoz.io()`) |
| `std.mem.Allocator` | A per-call arena, freed after the result is converted |

Python-visible arguments (up to 8) are **copied** when the function is
called, so later changes to the Python objects do not affect the running task:

- integers, floats, bools, enums and optionals of those
- `[]const u8` (duplicated into the per-call arena)
- structs **by value** with no pointer fields, including PyOZ classes
  (`fn f(p: Point)`), `pyoz.Complex` and the datetime types

Types that could alias Python-owned memory (pointers, other slices, structs
containing them) are rejected at compile time. Argument conversion errors raise
`TypeError` immediately at the call site, not later from the future.

Results use the module's full conversion machinery, so async functions can
return PyOZ class instances (`!Point`), strings, lists, and so on. Errors map to
exceptions exactly like synchronous functions, **including the module's
`.error_mappings`** (`pyoz.mapError` / `pyoz.mapErrorMsg`).

Generated stubs annotate async functions as `-> Awaitable[T]`. Add
`.withParams("name, ...")` to the `pyoz.func` entry to give parameters real
names in stubs and `help()`.

Tested with asyncio's default loop and with **uvloop**.

## Completion step

The task runs without Python, so it cannot take or create Python objects.
`pyoz.asyncThen(f, then)` adds a second function that runs **on the event loop
thread with Python attached** once the task has succeeded. The awaitable
resolves to what `then` returns:

```zig
// Worker task: no Python
fn compileImpl(grammar: []const u8) !Parser { ... }

// Event loop thread: any Python API is allowed
fn bindImpl(parser: Parser, classes: ?*pyoz.PyObject) !Parser {
    var p = parser;
    if (classes) |obj| try p.bind(obj);
    return p;
}

.funcs = &.{
    pyoz.func("compile_async", pyoz.asyncThen(compileImpl, bindImpl), "Compile, then bind")
        .withParams("grammar, classes"),
},
```

```python
parser = await mymod.compile_async(text)
parser = await mymod.compile_async(text, classes=my_ast_module)
```

- `then`'s first parameter is the task's result. Its other parameters follow
  the task's in the Python signature (8 in total) and may be
  `*pyoz.PyObject` / `?*pyoz.PyObject`, or any type `asyncFn` accepts.
- Python objects are borrowed by `then`: PyOZ keeps them alive until it has
  run and releases them afterwards, also when the awaitable is cancelled.
- `then` is skipped when the task fails or the awaitable is cancelled. If the
  task's result owns resources, those cases do not reach `then`.
- `then` may return an error (mapped like any other), or raise a Python
  exception and return `null` from an optional return type.
- It runs on the event loop, so keep it short: do the heavy work in the task.

With `.withParams(...)` naming every parameter, `?T` parameters are optional
and can be passed by keyword, as in the example above.

`pyoz.asyncMethodThen(f, then)` is the same for [async methods](#async-methods).

## Async methods

`pyoz.asyncMethod` works like `asyncFn` for instance methods. The task runs on
another thread while Python can keep using the object, so **the type of `self`
is the safety contract**, enforced at compile time:

| `self` parameter | Meaning | Allowed when |
|---|---|---|
| `self: T` | Runs on a **copy** taken at call time; the task's mutations never reach the Python object | fields are pointer-free |
| `self: *const T` | **Borrows** the object; it is kept alive until the Zig task has been joined (also after cancellation) | class is `__frozen__` and has no `*T` methods |
| `self: *T` | — | never (compile error) |

```zig
const Vec = struct {
    pub const __frozen__ = true;
    x: f64,
    y: f64,

    fn slowNormImpl(self: *const Vec, io: std.Io, ms: i64) !f64 {
        try io.sleep(.fromMilliseconds(ms), .awake);
        return @sqrt(self.x * self.x + self.y * self.y);
    }
    pub const slow_norm = pyoz.asyncMethod(slowNormImpl);
};

const Counter = struct {
    value: i64,
    pub fn inc(self: *Counter) void { self.value += 1; }

    fn valueLaterImpl(self: Counter, io: std.Io, ms: i64) !i64 {
        try io.sleep(.fromMilliseconds(ms), .awake);
        return self.value; // the value at call time
    }
    pub const value_later = pyoz.asyncMethod(valueLaterImpl);
};
```

Keep the implementation function non-`pub` so it is not also exposed as a
regular method. On free-threaded builds the copy is taken inside the object's
critical section, so it is always a consistent snapshot.

## Async protocols

Classes can implement Python's async dunders, so instances work with
`async for`, `await obj` and `async with`:

| Method | Python | Result becomes |
|---|---|---|
| `__aiter__(self: *T) *T` | `async for x in obj` | the async iterator (usually `self`) |
| `__anext__(self: *T) ?V` | next item | awaitable of `V`; `null` ends the iteration (`StopAsyncIteration`) |
| `__await__(self: *const T) V` | `await obj` | awaitable of `V` |
| `__aenter__(self: *T) *T` | `async with obj as r` | awaitable of `r` (`*T` returning `self` gives back the same object) |
| `__aexit__(self: *T, exc_type: ?*PyObject, exc: ?*PyObject, tb: ?*PyObject) bool` | leaving the block | awaitable of the result; `true` suppresses the exception |

What PyOZ does with the return value decides how the awaitable behaves:

- **A plain Zig value** (`i64`, `[]const u8`, `*T` returning `self`, `void`, …)
  becomes a completed awaitable. It never suspends, so it needs no running event
  loop and works under asyncio, trio, anyio, or a bare `coro.send(None)`.
- **A `pyoz.asyncFn` result** is the `asyncio.Future` itself, so the work runs
  on a `std.Io` task. In `__anext__`, a task returning `null` ends the iteration.
  `pyoz.Future(f)` names the result type of calling `pyoz.asyncFn(f)`.
- **A raw `*PyObject`** is taken to already be an awaitable (for example a
  coroutine from calling a Python `async def`) and is used as is.
- **Errors** returned from the dunder raise immediately. Errors from a task
  surface when it is awaited, as with `asyncFn`.

`__anext__` usually mutates the iterator (a cursor, a buffer), so it takes
`self: *T` and runs under the object's lock on free-threaded builds. Advance the
cursor there and hand the slow part to a task:

```zig
fn fetchPageImpl(io: std.Io, page: i64, pages: i64) !?i64 {
    try io.sleep(.fromMilliseconds(10), .awake); // e.g. a network call
    if (page >= pages) return null;             // end of stream, found by the task
    return page * 10;
}
const fetchPage = pyoz.asyncFn(fetchPageImpl);

const Pages = struct {
    pages: i64,
    _next: i64 = 0,

    pub fn __aiter__(self: *Pages) *Pages {
        return self;
    }

    pub fn __anext__(self: *Pages) !pyoz.Future(fetchPageImpl) {
        defer self._next += 1;
        return fetchPage(self._next, self.pages);
    }
};
```

```python
async for item in mymod.Pages(3):
    print(item)                           # 0, 10, 20
await anext(mymod.Pages(0), "empty")      # "empty"
```

If the end is known up front, declare `!?pyoz.Future(f)`, return `null` without
starting a task, and otherwise `return try fetchPage(...)`. An awaitable object can hand its whole `__await__` to a
task with `pyoz.asyncMethod`:

```zig
const Delayed = struct {
    value: i64,
    ms: i64,

    fn awaitImpl(self: Delayed, io: std.Io) !i64 {
        try io.sleep(.fromMilliseconds(self.ms), .awake);
        return self.value;
    }
    pub const __await__ = pyoz.asyncMethod(awaitImpl);
};
```

An async context manager with immediate results:

```zig
const Session = struct {
    open: bool = false,

    pub fn __aenter__(self: *Session) *Session {
        self.open = true;
        return self;
    }

    pub fn __aexit__(self: *Session, exc_type: ?*pyoz.PyObject, exc: ?*pyoz.PyObject, tb: ?*pyoz.PyObject) bool {
        _ = .{ exc_type, exc, tb };
        self.open = false;
        return false; // don't suppress exceptions
    }
};
```

Stubs declare `async def __anext__(self) -> V`, `def __await__(self) ->
Generator[Any, Any, V]`, and `async def __aenter__` / `__aexit__`, so type
checkers accept `async for`, `await` and `async with` on these classes. All of
this also works in ABI3 mode.

## Concurrency limit

Under `std.Io.Threaded` each running job occupies one OS thread. At most 256
jobs run at once by default; further calls queue and start as others finish,
so any number of tasks can be awaited. Change it before the first async call:

```zig
_ = pyoz.setAsyncConcurrency(1024);
```

## Io backend

PyOZ uses `std.Io.Threaded`. Zig 0.16 also ships evented backends (io_uring on
Linux, GCD on macOS, kqueue on BSD), which would make large numbers of
concurrently sleeping tasks cheaper, but in 0.16.0 none of them compile when
used as an `Io` (and Windows has none). The backend is selected in one place, so
PyOZ can switch without API changes once they mature.

## Performance

Measured against `loop.run_in_executor` with a `ThreadPoolExecutor`
(ReleaseFast, CPython 3.12):

| | `pyoz.asyncFn` | `run_in_executor` |
|---|---|---|
| Sequential `await` | ~41 µs | ~46–54 µs |
| `gather` of 20,000 tasks | ~13 µs / task | ~37 µs / task |

## Next Steps

- [Free-Threading](free-threading.md) - Running without the GIL
- [GIL Management](gil.md) - Releasing the GIL in synchronous code
- [Errors](errors.md) - Error mappings, which also apply to async functions
