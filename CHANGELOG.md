# Changelog

All notable changes to PyOZ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.13.6] - 2026-09-30

### Added
- **`pyoz.asyncThen(f, then)` and `pyoz.asyncMethodThen(f, then)`: async functions with a completion step.** The task still runs without Python; when it succeeds, `then(result, extra...)` runs on the event loop thread with Python attached, and the awaitable resolves to its result. `then`'s extra parameters follow the task's in the Python signature and may be `*pyoz.PyObject` / `?*pyoz.PyObject`, which PyOZ keeps alive until the step has run (and releases on cancellation). This covers work such as `await compile_async(grammar, classes=module)`, where the compiled result must be bound to Python objects.
- **`pyoz.func(...).withParams(...)` makes `?T` parameters optional.** When the names cover every parameter, the optional ones may be omitted or passed by keyword, as `.from` functions already allowed. Before, every argument had to be passed positionally.

## [0.13.5] - 2026-09-30

### Added
- **`__new__` can take `pyoz.Args(...)`.** The constructor then accepts keywords and defaults from the argument struct, like keyword functions, with no `__new____params__` and no `pyoz.withSource`: `pub fn __new__(args: pyoz.Args(struct { level: i64, line: i64 = 0 })) Notice`.
- **Field defaults in the default constructor.** A field with a default value may be omitted: with `struct { width: i64, height: i64 = 10 }`, `Options(3)` and `Options(3, height=4)` both work. A required field after a defaulted one can be passed by keyword.

### Fixed
- **`__init__` stubs ignored `__new__`.** The `.pyi` always listed the struct's public fields, so a class with a custom constructor got the wrong signature (`def __init__(self)` when all fields are private). Stubs now describe the real constructor: the `pyoz.Args` fields, or the `__new__` parameters with their names when known (`arg0, ..., /` otherwise) and `| None = None` for optional ones. Field defaults appear as `= ...`.

### Changed
- Constructor error messages follow one format for every constructor kind: `Cls() takes at most N positional arguments (M given)`, `Cls() missing required argument 'x'`, `Cls() argument 'x' has the wrong type`.

## [0.13.4] - 2026-09-30

### Fixed
- **`pyoz.func` with a `pyoz.Args(...)` function could not be called.** It compiled, but was registered as positional-only: keywords raised `takes no keyword arguments` and positional calls failed too. `pyoz.func` now detects `pyoz.Args` like `.from` and class methods do, so `pyoz.kwfunc` is optional.
- **Keyword functions ignored the module's `.error_mappings`.** Errors from `pyoz.kwfunc`, and from `.from` functions taking `pyoz.Args` or optional `?T` parameters, only used the built-in name-based fallback, so a mapped error surfaced as `RuntimeError` with the raw error name. They now use the same mappings as positional functions (new `wrapFunctionWithNamedKeywordsAndErrorMapping` and `wrapAutoKeywordFunctionWithErrorMapping`; the existing wrappers keep their signatures).

- **Constructors silently dropped keyword arguments.** `Diagnostic(1, 0, line=3)` built an object with `line = 0`, and unknown keywords were accepted. Constructors now take keywords by name: the field names for the default constructor, and for `__new__` the names from `__new____params__` or `pyoz.withSource`. Duplicate, missing and unknown arguments raise `TypeError`, and a `__new__` without known parameter names rejects keywords (`Cls() takes no keyword arguments`) instead of ignoring them.
- **Property getters returning `pyoz.Signature(...)`** returned `NULL` without an exception (`SystemError: error return without exception set`): the wrapper was not unwrapped. All three getter kinds (`get_X`, custom field getters, `pyoz.property`) now unwrap it, map returned errors to exceptions, and always set an exception on failure.
- **Zig tuple parameters** (`struct { i64, i64 }`) could be returned but not accepted: `fromPy` had no tuple case, so functions and `__new__` taking one failed with a bare `TypeError`. They now accept a Python tuple of the same length, with clear errors for a wrong length or item type.

### Changed
- **`get_X` / `set_X` are properties only with the accessor signature**: `get_X(self)` and `set_X(self, value)`. A function such as `get_item(self, index)` is now an ordinary method; previously it failed to compile with an error inside `properties.zig`. The rule lives in one place (`class/accessors.zig`) shared by the property table, the method table and stub generation.

## [0.13.3] - 2026-09-29

### Fixed
- **`abi3 = true` did not build a Stable ABI extension.** `pyoz build` only used it for the wheel tag: the module was compiled against the full C API of the building Python and tagged `cp310-abi3`, so pip would install it on other Python versions, where it can crash. `pyoz build` now enables abi3 in PyOZ's build through the environment (`PYOZ_ABI3`), which works with existing projects unchanged; new `build.zig` templates also accept `zig build -Dabi3=true`. **Wheels published as `abi3` with an earlier PyOZ should be rebuilt and republished.** CI now checks that an abi3 build uses `PyType_FromSpec`, not `PyType_Ready`.
- **ABI3 builds leaked every `str` argument.** Converting a `str` to `[]const u8` encoded it to a bytes object that was never freed (about 62 MB per 100,000 calls with a 600-character string). `PyUnicode_AsUTF8AndSize` is in the Limited API since Python 3.10, PyOZ's minimum, so both modes now use it directly. This affected parameters, dict keys, `pyoz.Args` fields, `Path`, `Decimal` and attribute names. Regression tests in both modes.

## [0.13.2] - 2026-09-29

### Fixed
- **`__del__` never ran for class instances returned from Zig functions**, so their resources leaked. `toPy` created them with `PyObject_New`, which left the wrapper uninitialized, including the flag that gates `__del__`. They now go through the class's `tp_new`, like `Cls()`: the freelist is used, `__dict__`/`__weakref__` slots are zeroed and `__del__` runs.
- **Cross-building Windows wheels from Linux failed to link** (`undefined symbol: Py_IncRef` and similar). Zig's `linkSystemLibrary` asks the host's pkg-config first, which answered for the Linux `python3` and dropped the Windows import library. The `build.zig` template now passes `.use_pkg_config = .no`; existing projects should make the same one-line change.

## [0.13.1] - 2026-09-29

### Fixed
- **Projects created with `pyoz init` failed to build** with `dependency is missing hash field`. Zig 0.16's `zig fetch --save` leaves an existing hash-less dependency entry untouched, so the generated `build.zig.zon` never got its hash. `pyoz init` now lets `zig fetch --save` add the entry, and falls back to the URL-only entry (with instructions) when offline. Projects created with 0.13.0 can add the `.hash = "..."` line that the build error prints, or delete the `.PyOZ` entry and run `zig fetch --save=PyOZ https://github.com/pyozig/PyOZ/archive/refs/tags/v0.13.1.tar.gz`.
- The release workflow now smoke-tests every release on Linux, macOS and Windows: `pip install pyoz`, `pyoz init` (without `--local`), `pyoz build`, install and import.

## [0.13.0] - 2026-09-29

**Breaking:** requires Zig 0.16.0 and Python 3.10+; existing projects need a few `build.zig` edits (including one line for macOS); `pyoz.fmt` returns `pyoz.Formatted` (see Changed); wheels are now portable and tagged `manylinux_2_17_*` / `macosx_13_0_*`. Step-by-step instructions: [Upgrading to 0.13](https://pyoz.dev/upgrading/).

### Added
- **[Upgrading to 0.13](https://pyoz.dev/upgrading/) guide**, verified by migrating a project generated by the 0.12 CLI.
- **Editable installs (PEP 660).** `pip install -e .` works through `pyoz.backend` (new `build_editable` hook), and `pyoz develop` now builds and pip-installs a standard editable wheel (`__editable__.*.pth` + dist-info) instead of symlinking into site-packages. Rebuilds are picked up without reinstalling; `pip uninstall` removes it.
- **Portable wheels, tagged from the binary.** `pyoz build` builds wheels for a baseline CPU, glibc 2.17 on Linux (`manylinux_2_17_*`, accepted by PyPI) and macOS 13.0, and reads the platform tag from the built module (highest glibc symbol version, allowed shared libraries, minimum macOS version, architecture), like auditwheel. `--native` builds for the exact machine. `linux-platform-tag` selects the glibc floor (`manylinux_2_28_x86_64` builds against glibc 2.28). ([#58](https://github.com/pyozig/PyOZ/issues/58))
- **Cross-building wheels: `pyoz build --target <targets>|all --python <3.X[t]>`.** One machine builds wheels for Linux, macOS and Windows on x86_64 and aarch64, for any CPython 3.10–3.14 including free-threaded 3.13t/3.14t. Headers and Windows import libraries for other platforms or versions come from python-build-standalone, verified against its SHA256SUMS and cached.
- **Complete wheel metadata from `[project]`** (PEP 621/639): readme (file or text, any content type), SPDX `license` expressions and legacy license tables, `license-files` shipped in `.dist-info/licenses/` (by default `LICEN[CS]E*`, `COPYING*`, `NOTICE*`, `AUTHORS*`), classifiers, keywords, authors, maintainers, URLs, `dependencies`, `optional-dependencies`, and `entry_points.txt` from `[project.scripts]`/`gui-scripts`/`entry-points`. `pyoz publish` sends the same metadata, so PyPI shows the classifiers and license. Parsing uses a real TOML reader (multi-line arrays, inline tables). ([#58](https://github.com/pyozig/PyOZ/issues/58))
- **Source installs without Zig:** when no Zig 0.16 is on `PATH`, `pyoz.backend` requests the `ziglang` package in pip's isolated build environment and builds with its compiler, so `pip install git+...` and sdists work anywhere. `pyoz build` warns when `zig` is a different minor release. ([#60](https://github.com/pyozig/PyOZ/issues/60))
- **`pyoz.Args(...)` keyword arguments on class methods** (instance, static and class methods), with defaults shown in `help()` and fields expanded in stubs. Contributed by [@marselester](https://github.com/marselester). ([#59](https://github.com/pyozig/PyOZ/pull/59))
- **`.withParams("a, b")`** on `pyoz.func` entries names Python-visible parameters in stubs and `help()` (previously always `arg0, arg1`). ([#61](https://github.com/pyozig/PyOZ/issues/61))
- **Async protocols on classes: `__aiter__`, `__anext__`, `__await__`, `__aenter__`, `__aexit__`.** Instances work with `async for`, `await obj` and `async with`, and `anext(it, default)` works as well. Plain Zig return values become awaitables that complete immediately and need no running event loop, so they work under asyncio, trio or a bare `coro.send(None)`. Returning a `pyoz.asyncFn` result runs the work on a `std.Io` task, and in `__anext__` a `null` result from the task ends the iteration. The new `pyoz.Future(f)` names that result type. The slots take the per-object lock on free-threaded builds, work in ABI3 mode, and generate `async def` / `Generator[...]` stubs.
- **`pyoz.asyncMethod`: async instance methods.** The `self` parameter type is the safety contract, enforced at compile time: `self: T` runs on a copy taken at call time (pointer-free fields); `self: *const T` borrows the object, which is kept alive until the Zig task is joined, and is only allowed on `__frozen__` classes with no `*T` methods; `self: *T` is rejected.
- **Async functions on `std.Io`: `pyoz.asyncFn(f)`.** Calling the function from Python returns an `asyncio.Future`; `f` runs on its own `std.Io` task without the GIL. Optional leading `std.Io` and `std.mem.Allocator` (per-call arena) parameters. Cancelling the Python task cancels the Zig task (`error.Canceled` at its next `Io` call). Bounded thread use (`pyoz.setAsyncConcurrency`, default 256) with unbounded queued concurrency. About 3x the throughput of `run_in_executor` for bulk `gather`. Works on regular, free-threaded and ABI3 builds.
- **Free-threading stress tests in the suite**: on free-threaded interpreters, many threads hammer one object (ArrayList appends that race on reallocation, plus read-modify-write), share one iterator through its `__next__` slot and one async iterator through `__anext__`, and six event loops run async jobs in parallel; they run on multi-core CI runners in Debug and ReleaseSafe and skip on GIL builds.
- **Free-threaded CPython (PEP 703) support.** `.gil_used = false` module option declares GIL-free operation (previously every PyOZ import re-enabled the GIL). Every class method, property and protocol slot runs in a per-object critical section on free-threaded builds (`__lock__ = false` opts out); zero cost on regular builds. `pyoz build` produces `cpXY-cpXYt` wheels. CI tests 3.14t.
- `pyoz.io()`, `pyoz.asyncLiveJobs()`, `pyoz.Formatted`.
- **Async functions can return PyOZ class instances** and take pointer-free structs (including PyOZ classes) by value; up to 8 parameters; module `.error_mappings` apply to async errors; stubs emit `Awaitable[T]`. Tested on asyncio and uvloop, and cross-linked for Windows (x86_64/ARM64), macOS (x86_64/arm64) and Linux (x86_64/aarch64).

### Changed
- **Python 3.10 is now the minimum** (3.8 and 3.9 are end-of-life). ABI3 builds use `Py_LIMITED_API = 0x030A0000` and produce `cp310-abi3` wheels; generated projects declare `requires-python = ">=3.10"`; CI tests 3.10–3.14 and 3.14t. `abi.zig`'s version checks now derive from the same constant (they previously read a build option no build script defined).
- **Zig 0.16.0 is now required.** The library, build scripts, CLI, `pypi/` backend and the project templates generated by `pyoz init` all target Zig 0.16 (`std.Io`, `std.process.Init`, module-level `link_libc`/`linkSystemLibrary`). Projects created with an older `pyoz init` need the same `build.zig` changes: `.link_libc = true` on the module instead of `lib.linkLibC()`, and `addLibraryPath`/`linkSystemLibrary(name, .{})` called on the module.
- **Pure-Zig wheel compression.** The vendored miniz C library is removed; DEFLATE now uses `std.compress.flate`. The CLI is a single static binary with no libc dependency.
- **`pyoz init` no longer runs `zig build` twice.** The package fingerprint is generated directly and the dependency hash is pinned with `zig fetch --save`. Generated `build.zig.zon` files declare `minimum_zig_version = "0.16.0"`.
- **`pyoz test` and `pyoz bench` share one implementation.**
- **PyPI upload errors show the server's message** instead of only the HTTP status, with a hint for common causes; they no longer claim "the version already exists" for every HTTP 400. The Python `pyoz` command exits with the error instead of a traceback. ([#58](https://github.com/pyozig/PyOZ/issues/58))
- **Keyword-argument errors follow CPython:** `f() got an unexpected keyword argument 'x'` (previously unknown keywords were silently ignored), `got multiple values for argument 'x'`, `missing required argument 'x'`, `takes at most N positional arguments`. A specific conversion error (e.g. `OverflowError`) is no longer replaced by a generic `TypeError`, `help()` shows the real defaults (`exponent=2.0`, not `exponent=None`), and `Path`/buffer arguments passed through `pyoz.Args` are released after the call. ([#59](https://github.com/pyozig/PyOZ/pull/59))
- **Fixed-size array parameters accept tuples** as well as lists, and stubs say `list[T] | tuple[T, ...]`. A wrong length raises `ValueError: expected N items, got M` (previously a `TypeError` whose message was the Zig error name). ([#61](https://github.com/pyozig/PyOZ/issues/61))
- **The Zig version is defined once** (`version.zig`); a CLI test checks every other copy (`build.zig.zon` files, the pip backend, CI workflows, installation docs).
- **Python 3.14 supported and tested.**
- **`pyoz.fmt` is now lazy and lifetime-safe (breaking).** It returns a `pyoz.Formatted` value that is rendered by its consumer (every `raise*` function, and any return-value conversion to `str`). Code that declared a `[*:0]const u8` return type for `pyoz.fmt` results must use `pyoz.Formatted("fmt", struct { ... })` (and `return .{ .args = .{ ... } }`) instead; this is a compile error, not a silent change.

### Fixed
- **Examples returned pointers into dead stack frames** (`join_strings`, `decimal_double` in both examples), and one returned a shared static buffer that races under free-threading (`iter_join`). They passed in Debug but failed in release builds with Zig 0.16's optimizer. They now return heap memory via `pyoz.Owned`; `Owned(pyoz.Decimal)` is supported. CI now also runs every test suite in ReleaseSafe.
- **`pip install .` failed for every project using `pyoz.backend`** (`ModuleNotFoundError: No module named '_pyoz'`: the backend imported the native module by the wrong name). CI now builds the pyoz wheel and runs `pip install .` and `pip install -e .` on a generated project.
- **`pyoz publish` only uploads wheels for the current name and version**; leftovers from earlier builds in `dist/` are skipped instead of failing with HTTP 400.
- **Windows ReleaseSafe builds** failed inside Zig 0.16's translation of MinGW's `_FORTIFY_SOURCE` wrappers; `_FORTIFY_SOURCE` is now undefined for the Python header import on Windows.
- **`pyoz.fmt` returned a pointer into a dead stack frame** when used as a `__repr__`/`__str__` return value. Messages longer than 4 KB were replaced by "fmt: message too long"; they are now rendered in full. `repr` via `pyoz.fmt` is ~12% faster.
- **Free-threaded builds:** static object headers wrote `1` into `ob_tid`; the class freelist raced (now disabled on free-threaded builds); lazy datetime/decimal/pathlib caches raced (now lock-free), including an ABI3 datetime ordering bug where a class could be used before it was published; Python library name missed the `t` ABI flag.
- **Wheel RECORD is now spec-compliant.** Every file is listed with its `sha256=` digest and size; previously entries had no hashes.
- **Wheel and `.dist-info` names are normalized** (`My-Pkg` → `my_pkg`) as the binary distribution format requires.
- **Reproducible wheels:** ZIP timestamps honor `SOURCE_DATE_EPOCH`.
- **Cross-compiling generated projects to Windows** now installs `name.pyd` (the template chose the extension from the host OS instead of the target).
- **Windows wheels with nested Python packages** use `/` in ZIP entry names instead of `\`.
- **ABI3 builds under Zig 0.16:** built-in type objects (`PyLong_Type`, ...) are referenced via `@extern`, since 0.16's C translator rejects extern variables of opaque type under `Py_LIMITED_API`.
- **ABI3 classes defining `__eq__` without `__hash__`** failed to compile (`PyObject_HashNotImplemented` was cast as a function body rather than a pointer).
- **Double free in Python detection** when `sysconfig` returned an empty include path.
- **Child processes killed by a signal** no longer trip a union-field safety check in `pyoz build`/`test`/`bench`/`develop`.
- **TestPyPI uploads prefer `TEST_PYPI_TOKEN`** over `PYPI_TOKEN` when both are set.
- **`pyoz init` with an invalid name** no longer leaves an empty directory behind.
- **Generated README** referenced a nonexistent `pyoz build-wheel` command.
- **macOS builds of generated projects failed to link** (`undefined symbol: _PyErr_Occurred`, ...): the template never allowed the interpreter-provided C API symbols to be undefined. New projects set `linker_allow_shlib_undefined` on macOS; existing ones need the one-line change in the [upgrading guide](https://pyoz.dev/upgrading/).
- **macOS wheels were uninstallable:** the tag used the build machine's full macOS version (e.g. `macosx_14_5_arm64`), but pip only generates `macosx_N_0` tags for macOS 11 and later.
- **Linux wheels were not portable:** built for the build machine's CPU features and glibc, tagged `linux_*` (rejected by PyPI), and the documented `manylinux` override only relabelled them. The `pyoz` package's own wheels were tagged `manylinux2014`/`macosx_11_0` while built against glibc 2.28/2.34 and macOS 13.
- **Windows non-ABI3 modules linked `python3.lib`,** which only exports the Stable ABI; they now link `python3XY[t].lib`.
- **Free-threaded builds: protocol slots were not locked.** `__repr__`, `__iter__`/`__next__`, operators, `__getitem__`/`__setitem__`, `__call__`, rich comparison and the buffer protocol ran without the object's critical section on free-threaded CPython (only methods and properties took it). A new stress test drives `__next__` from many threads.
- **Explicit-target builds on Debian/Ubuntu** could not find the multiarch `pyconfig.h`; PyOZ's `build.zig` now provides it.
- **sdists** include `py-packages`, README and license files, skip build output, and use the normalized file name (PEP 625).

## [0.12.2] - 2026-03-16

### Added
- **`pyoz.MemoryView`** — New type for accepting Python `memoryview` objects. Provides read-only `data: []const u8` access to the underlying buffer. Call `.release()` when done.
- **`pyoz.BytesLike`** — New unified type that accepts Python `bytes`, `bytearray`, or `memoryview`. Provides read-only `data: []const u8` regardless of source type. Call `.release()` when done (no-op for bytes/bytearray).
- **`anytype` and `comptime` limitations documented** — The `.from` auto-scan guide now explains why functions with `anytype` or `comptime` parameters are skipped and shows the typed-wrapper workaround.
- **`abi3 = true` configuration documented** — The `[tool.pyoz]` configuration reference now includes the `abi3` option.
- **ByteArray, MemoryView, BytesLike in docs** — Added to both the types guide and API reference.

### Changed
- **Removed bridge module — user module is now the root module** — `pyoz init` no longer generates a separate `_pyoz_bridge.zig` module. Instead, the comptime decl-analysis block is inlined directly in the user's `lib.zig`, making it the library's root module. This enables Zig root-module features like `std_options` (custom logging, panic handlers, etc.) that were previously inaccessible because the bridge was the root. The `build.zig` template is also simplified (no `WriteFiles`, no extra `createModule`).

### Fixed
- **Private fields with non-zero-initializable types** — Private fields (underscore prefix) whose types contain non-nullable pointers (e.g. `std.heap.ArenaAllocator`, `std.mem.Allocator`) no longer cause a compile error. Previously, all private fields were zero-initialized via `std.mem.zeroes`, which fails for types that cannot be set to zero. Now uses a smarter `initDefault` that: (1) uses the field's default value if one is defined in the struct, (2) zero-initializes if the type supports it, or (3) leaves the field as `undefined` for types that cannot be zeroed — the user's `__new__` function must initialize these fields.
- **Integer overflow now raises `OverflowError`** — Converting a Python `int` to a small Zig integer type (e.g. `u8`, `i16`, `u32`) now performs a range check and raises `OverflowError` if the value doesn't fit. Previously, values were silently truncated via `@truncate` (C-style wrapping), so `u8` receiving 256 would silently become 0.
- **Class method errors now map to correct Python exceptions** — Zig errors returned from class methods (`__getitem__`, `__len__`, `__call__`, `__iter__`, `__next__`, `__repr__`, `__hash__`, comparisons, number protocol, mapping protocol, etc.) are now mapped to their corresponding Python exception types via `mapWellKnownError`. Previously, all class method errors were hardcoded to `RuntimeError`. For example, `error.IndexOutOfBounds` now raises `IndexError`, `error.ValueError` raises `ValueError`, `error.Overflow` raises `OverflowError`, etc. Affects 13 error sites across 8 class protocol files.
- **`ListView.get()` sets IndexError/TypeError** — `ListView.get(index)` now sets `IndexError` for out-of-bounds access and `TypeError` for element conversion failures, instead of returning silent `null` with no Python exception set.
- **Negative index on unsigned `__getitem__` now raises `IndexError`** — Classes with `usize` index in `__getitem__` (mapping protocol) now raise `IndexError` instead of `OverflowError` when accessed with a negative index. Previously, Python's C API `OverflowError` from converting a negative int to unsigned was propagated directly.

## [0.12.1] - 2026-03-04

### Added
- **Auto-kwargs for `?T` params in `.from`** — Functions discovered via `.from` that have optional (`?T`) parameters now automatically support keyword arguments without requiring `pyoz.Args(T)`. Required params stay positional-only, optional params become keyword-capable. For example, `fn add(a: i64, b: i64, multiplier: ?i64)` generates the Python signature `add(a, b, /, multiplier=None)` and can be called as `add(1, 2, multiplier=5)`. Requires source text (via `pyoz.withSource()`, `__source__()`, or `__params__`) for parameter name extraction. A compile-time warning is emitted if `?T` params are used without source text.
- **`.funcs` and `.classes` are now optional in `pyoz.module()`** — When using `.from` for all declarations, you no longer need to specify empty `.funcs = &.{}` and `.classes = &.{}`.

### Changed
- **Enum stubs show type annotations instead of values** — Generated `.pyi` stubs for enums now use `field: int` / `field: str` instead of exposing the actual values (`field = 0` / `field = "name"`).

### Fixed
- **Source parser performance: eagerly-parsed source caching** — `withSource` now eagerly parses the source file once and shares the pre-parsed data across all lookups, eliminating redundant comptime tokenization. Previously, Zig's comptime evaluator re-parsed the source for every doc/param lookup (92× for a 24-class file), causing 2m+ compile times. Now compiles in ~3s. Also eliminates source text leaking into debug symbols (the old `SourceInfo("entire source...")` generic type name is replaced with `ParsedSource`).
- **`pub inline fn` and `pub noinline fn` doc comments now extracted** — The source parser now correctly skips `inline`, `noinline`, and `export` keywords between `pub` and `fn`, so doc comments on `pub inline fn` declarations are properly extracted for Python docstrings and stubs.
- **Package mode no longer requires underscore prefix in `module-name`** — Package layout detection now uses `py-packages` containing the project name, instead of requiring the module name to start with `_`. Users can now use `module-name = "liburing"` with `py-packages = ["liburing"]` and `from .liburing import *` in `__init__.py`. The underscore convention still works but is no longer required. Affects `pyoz develop`, `pyoz build`, `pyoz test`, `pyoz bench`, and wheel building.
- **`build.zig` templates now include guidance for custom C include paths** — The generated `build.zig` includes comments showing that `addIncludePath` and `addObjectFile` must be added to `user_lib_mod`, not `lib.root_module` (which is the bridge module in 0.12.0). This prevents `@cImport` failures when wrapping C libraries.
- **Better compile error for `kwfunc` without `pyoz.Args(T)`** — When using explicit `kwfunc` with a parameter not wrapped in `pyoz.Args(T)`, the compiler now shows a clear error message with the fix, instead of the cryptic `type 'u32' has no members`.

## [0.12.0] - 2026-03-01

### Added
- **Automatic `PyInit_` export — zero boilerplate module initialization** — `pyoz.module()` now auto-exports the `PyInit_<name>` function via `@export` in a comptime block. The build system generates a bridge module that forces Zig's lazy analysis, so the user only needs `pub const Module = pyoz.module(.{ .name = "mymod", ... });` — no manual `pub export fn PyInit_mymod` needed. Works with both standard and `--package` layouts. The module const must be `pub`. Existing projects with manual `PyInit_` exports should remove them to avoid duplicate symbol errors.
- **`.from` auto-scan API** — New module config field `.from = &.{ @import("my_funcs.zig") }` that auto-discovers and registers public declarations from Zig namespaces. Eliminates repetitive `pyoz.func()`/`pyoz.class()`/`pyoz.constant()` boilerplate when the Python name matches the Zig identifier. Supports functions, classes, enums, constants, and exceptions. Docstrings are provided via `{name}__doc__` convention, or automatically extracted from `///` doc comments when using `pyoz.withSource()`. Works with `pyoz.source()` for filtering (`.only`/`.exclude`) and `pyoz.sub()` for submodules.
- **`pyoz.source(namespace, .{ .only = &.{"a", "b"} })` / `.exclude`** — Filter which declarations from a `.from` namespace are exported. Use `.only` to whitelist or `.exclude` to blacklist specific names.
- **`pyoz.sub("name", namespace)` submodule support** — Declare submodules from `.from` namespaces. Functions, constants, classes, and enums in the submodule namespace are registered under `module.name`.
- **`pyoz.Exception(base, doc)` and `pyoz.ErrorMap()` markers** — Declare custom exceptions and error-to-exception mappings inside `.from` namespaces.
- **`.from` auto-detects `pyoz.Args(T)` for keyword arguments** — Functions using `pyoz.Args(T)` in `.from` namespaces are automatically wrapped with named kwargs support, identical to explicit `kwfunc` registration.
- **`.from` deduplication** — Explicit config entries (`.funcs`, `.classes`, etc.) always take priority over `.from`-scanned declarations with the same name. Duplicate names across multiple `.from` entries produce a compile error with guidance to use `pyoz.source()` filtering.
- **`.from` stub generation** — `.pyi` stubs are automatically generated for all `.from`-scanned declarations, including functions, classes, enums, and constants.
- **`__text_signature__` support for `help()` and `inspect.signature()`** — All functions (module-level and class methods) now embed a CPython Argument Clinic-style signature in `ml_doc`. `help(func)` shows proper parameter names instead of `add(...)`. Keyword argument functions using `pyoz.Args(T)` show field names and defaults (e.g. `safe_sqrt(value, default=None)`). Class methods correctly use `self`/`$type` conventions. When `withSource` is used for a `.from` namespace, real Zig parameter names are used (e.g. `count_words(s, /)` instead of `count_words(arg0, /)`); without source, positional args fall back to `arg0`/`arg1`.
- **`pyoz.withSource(@import("f.zig"), @embedFile("f.zig"))` — comptime source introspection** — New wrapper for `.from` entries that enables automatic extraction of `///` doc comments as Python docstrings, `//!` module-level doc comments as `module.__doc__`, real function parameter names for `__text_signature__` and `.pyi` stubs, and `///` comments above structs as class `__doc__`. No boilerplate needed in the `.from` file — just wrap the `@import` at the module config site. Uses `std.zig.Tokenizer` at comptime — source text is NOT embedded in the final binary. Explicit `{name}__doc__` and `{name}__params__` constants still take priority for backward compatibility. A legacy per-file `__source__` function/constant is also supported.

### ⚠️ Breaking Changes — Migration from 0.11.x

🔧 **`build.zig` must be updated.** The build system now uses a bridge module pattern to auto-export `PyInit_`. Projects created with `pyoz init` on 0.11.x need their `build.zig` replaced. The easiest way is to re-run `pyoz init --path` in your project directory (backs up existing files), or manually update `build.zig` to match the new template — see the [generated build.zig](https://github.com/pyozig/PyOZ/blob/dev/src/cli/project.zig) for the current template.

🗑️ **Remove manual `PyInit_` exports.** If your `lib.zig` contains `pub export fn PyInit_mymod`, delete it. The auto-export now handles this. Keeping it causes a `exported symbol collision` compile error.

🔓 **Make the module const `pub`.** Change `const MyMod = pyoz.module(.{...});` to `pub const MyMod = pyoz.module(.{...});`. The bridge module needs to see it to trigger the auto-export.

🔄 **`kwfunc` now requires `pyoz.Args(T)`.** The old `kwfunc` that accepted functions with `?T` optional parameters is removed. Wrap your kwargs in a struct:
```zig
// Before (0.11.x)
fn greet(name: ?[]const u8, times: ?i32) []const u8 { ... }
pyoz.kwfunc("greet", greet, "Greet someone")

// After (0.12.0)
fn greet(args: pyoz.Args(struct { name: ?[]const u8 = null, times: ?i32 = null })) []const u8 {
    const name = args.value.name orelse "World";
    ...
}
pyoz.kwfunc("greet", greet, "Greet someone")
```

### Changed
- **`kwfunc` renamed from `kwfunc_named`** — The old `kwfunc` (which generated unusable `arg0`/`arg1` kwarg names due to Zig's `@typeInfo` not exposing parameter names) is removed. `kwfunc_named` is renamed to `kwfunc` and is now the only way to register keyword argument functions. All kwargs functions must use `pyoz.Args(T)` for real parameter names.
- **Removed broken `?T` kwargs auto-detection** — Functions with optional `?T` parameters are no longer auto-detected as keyword argument functions (in both `.from` and explicit registration). The `?T` detection generated unusable `arg0`/`arg1` names. Use `pyoz.Args(T)` instead for proper named kwargs support.

### Fixed
- **`.from` enums with unsigned integer tags (`enum(u8)`, `enum(u16)`, etc.) registered as StrEnum instead of IntEnum** — The `isIntEnum` detection in `from.zig` used a flawed heuristic (checking signedness + exhaustiveness) that only recognized signed tags like `enum(i32)`. Unsigned explicit tags like `enum(u8)` fell through and were incorrectly registered as StrEnum, causing `.value` to return string names instead of integer values. Fixed by matching the proven logic from `enums.zig` — checking against standard integer types (`u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`, `isize`, `c_int`, `c_long`), which correctly distinguishes user-specified tags from Zig's auto-generated non-standard bit-width tags (`u1`, `u2`, `u3`, ...).
- **Build-time `PyInit_` symbol validation** — `pyoz build`/`pyoz dev` now validates that the compiled `.so`/`.pyd` exports the expected `PyInit_<module_name>` symbol after building. Catches mismatches between `module-name` in `pyproject.toml` and the Zig export function, printing a clear warning with the exact fix needed. Prevents the confusing `ImportError: dynamic module does not define module export function` at runtime.
- **Stub `.pyi` filename uses `module-name` instead of project `name`** — When `module-name` differs from the project name (e.g., `module-name = "_liburing"` with `name = "liburing"`), the stub file was incorrectly named `liburing.pyi` instead of `_liburing.pyi`. Now uses `config.getModuleName()` so the stub filename matches the actual `.so`/`.pyd`.
- **`py-packages` now supports Python src-layout** — `py-packages = ["mypkg"]` now searches `src/mypkg/` first (PEP 517 src-layout) before falling back to `mypkg/` (flat layout). Previously only flat layout was supported, causing `Warning: Python package directory not found` for src-layout projects and missing `__init__.py` in wheels.
- **Stub generation crash on non-`Args(T)` kwfunc parameters** — `@hasDecl` in `stubs.zig` was called on non-struct types (e.g., `?[]const u8`, `?bool`) when generating stubs for functions with optional parameters, causing a comptime error. Now checks `@typeInfo(...) == .@"struct"` before calling `@hasDecl`.
- **PyPI wheel: `_pyoz.so` placed inside `pyoz/` package** — The native extension `_pyoz.so` was previously installed at the top level of `site-packages/`, polluting the namespace. Now placed inside `pyoz/_pyoz.so` with a relative import (`from ._pyoz import ...`), keeping the package self-contained.
- **PyPI `pyoz` CLI updated to `pyoz.Args(T)` for 0.12.0 compatibility** — The `pypi/src/lib.zig` CLI wrapper functions used raw `?T` optional parameters with `kwfunc`, which is no longer supported in 0.12.0. Updated to use `pyoz.Args(T)` structs. Also added bridge module to `pypi/build.zig` for auto-export.

## [0.11.5] - 2026-02-28

### Fixed
- **Stub generation `@setEvalBranchQuota` exceeded with large modules** - Modules with many functions and classes would fail to compile with `evaluation exceeded 100000 backwards branches` in stub, test, and benchmark generation. Fixed by raising `@setEvalBranchQuota` to `std.math.maxInt(u32)` in all comptime generation call sites: `generateModuleStubs`, `generateImports` in `stubs.zig`, and the stubs/tests/benchmarks section embedding plus qualified name generation in `root.zig`.
- **CLI linker error on systems with GCC 15+** - `zig build cli` failed with `unhandled relocation type R_X86_64_PC64` on Linux systems with recent GCC/binutils (15+), which emit `.sframe` sections that Zig's linker cannot handle. Fixed by targeting `musl` for the CLI executable on Linux, using Zig's bundled musl instead of the system glibc toolchain. The CLI is now a fully static binary with zero external dependencies.
- **`__del__` called on failed `__new__` causing segfault** - When a user-defined `__new__` returned an error or `null` (e.g., via `raiseValueError`), PyOZ still called `__del__` during deallocation of the failed object, leading to a segfault on uninitialized data. Now an `_initialized` flag is tracked on each object: it is set only when `__init__`/`__new__` succeeds, and `__del__` is skipped if the flag is unset. This matches Python semantics where `__del__` is never called if `__new__` raises. Works in both ABI3 and non-ABI3 modes.
- **`__new__` error union errors always raised `RuntimeError`** - When a class `__new__` returning `!T` hit an error, it was always raised as `RuntimeError` regardless of the error name. Now uses the existing `mapWellKnownError()` function so `error.OutOfMemory` raises `MemoryError`, `error.ValueError` raises `ValueError`, `error.IndexOutOfBounds` raises `IndexError`, etc. — matching the behavior already in place for regular functions and methods since v0.11.0.

## [0.11.4] - 2026-02-19

### Added
- **`pyoz.Signature(T, "python_type")` -- stub return type override** - New comptime wrapper type that overrides the Python type annotation in generated `.pyi` stubs without affecting runtime behavior. Use this when the Zig return type doesn't map cleanly to the desired Python type, most commonly when `?T` is used for CPython exception signaling (returning `null` + `PyErr_SetString`) rather than representing Python `None`. For example, `fn probe() pyoz.Signature(?Dict, "dict[str, bool]")` generates `def probe() -> dict[str, bool]` instead of the incorrect `def probe() -> dict[str, bool] | None`. Also supports `pyoz.Signature(?void, "Never")` for functions that only raise. Works uniformly on module-level functions, class instance/static/class methods, `__call__`, `__new__`, and `allowThreads`/`allowThreadsTry`.
- **`PyMemoryView_Check`** - Added type check function for `memoryview` objects, following the same `isTypeOrSubtype` pattern as other type checks. Uses `PyMemoryView_Type` which is part of the stable ABI since Python 3.2, so works across 3.8–3.13 in both normal and ABI3 modes.

### Fixed
- **Comptime branch quota exceeded with large modules** - Modules with many functions would fail to compile with `evaluation exceeded 1000 backwards branches` in `anyFuncUsesDateTime`/`anyFuncUsesDecimal`. Fixed by setting `@setEvalBranchQuota(std.math.maxInt(u32))` in both functions.

### Refactored
- **Type check functions** - `PySet_Check`, `PyFrozenSet_Check`, `PyBytes_Check`, `PyByteArray_Check`, and `PyObject_TypeCheck` now use the shared `isTypeOrSubtype` helper for consistency.

### Removed
- **`method__returns__` class method stub override** - The `pub const method_name__returns__: []const u8 = "..."` convention for overriding class method return type stubs has been removed in favor of the unified `pyoz.Signature(T, "python_type")` approach, which works identically for both module-level functions and class methods.

## [0.11.3] - 2026-02-10

### Fixed
- **pip-installed pyoz test/bench on Windows** - Deduplicated test/bench runner logic in the pip package (`pypi/src/lib.zig`) by delegating to `commands.runTests`/`commands.runBench` instead of maintaining a separate copy. The previous duplicate code had hardcoded `zig-out/lib/` paths and no package mode support, causing test failures on Windows.

## [0.11.2] - 2026-02-10

### Fixed
- **Windows build support** - Fixed 77 `lld-link: undefined symbol` errors when building PyOZ projects on Windows. The generated `build.zig` template now accepts `-Dpython-lib-dir` and `-Dpython-lib-name` options, and `pyoz build` passes them automatically on Windows to link against `python3.lib` (stable ABI). Windows requires all symbols resolved at link time, unlike Linux/macOS which resolve Python symbols at runtime.
- **Windows output path** - Fixed `FileNotFound` error during wheel creation on Windows. Zig places DLLs (`.pyd`) in `zig-out/bin/` on Windows, not `zig-out/lib/`. The builder, test runner, and benchmark runner now use the correct output directory per platform.
- **Package mode test/bench imports** - In package layout (module name starts with `_`), the generated test and benchmark scripts now also `import ravn` (the package name) in addition to `import _ravn`, so users can write `assert ravn.add(2, 3) == 5` in their tests. The test/bench runners also detect package mode, copy the `.pyd`/`.so` into the package directory, and add the project root to `PYTHONPATH`.
- **ASCII tree output for `pyoz init`** - Replaced UTF-8 box-drawing characters with ASCII in the project structure output, fixing garbled display on Windows PowerShell.

## [0.11.1] - 2026-02-10

### Added
- **Multi-phase module initialization (PEP 489)** - PyOZ now uses `PyModuleDef_Init` + `Py_mod_exec` slot instead of the legacy `PyModule_Create` single-phase init. This is required for sub-interpreter support (PEP 554) and is the modern standard for Python extension modules. Simple modules (`return Module.init()`) work unchanged. Modules that need post-init work (e.g., adding submodules) should use the new `.module_init` callback in the module config instead of doing work after `init()` in `PyInit_*`.

### Fixed
- **`get_X`/`set_X` computed properties no longer exposed as methods** - When a class defines `get_user_data()` and `set_user_data()`, PyOZ correctly creates a `user_data` property but previously also exposed `get_user_data()` and `set_user_data()` as callable methods, cluttering the API. Now computed property accessors are filtered from the method table (`methods.zig`) and stub generation (`stubs.zig`), so only the `X` property appears in Python. The filter correctly handles: `get_X` as computed property getter, `set_X` with matching `get_X` as computed property setter, and `set_X` as field setter override. Standalone `set_X` without a matching getter or field is still exposed as a method.

## [0.11.0] - 2026-02-09

### Added
- **`pyoz init --package` -- Python package directory layout** - New `--package` flag for `pyoz init` that scaffolds a project with a proper Python package directory. Instead of installing a flat `.so` directly into site-packages, the extension is placed inside a package directory with an `__init__.py` that re-exports all native symbols. The native module is automatically prefixed with an underscore (e.g., `_myproject.so`) to avoid name collisions with the package directory. `pyoz build` and `pyoz develop` automatically detect package mode when `module-name` starts with `_` and a `py-packages` entry matches the project name, placing the `.so` and `.pyi` inside the package directory in wheels and development installs. This enables combining native extensions with pure Python code in the same importable package.
- **`pyoz.Owned(T)` -- allocator-backed return types** - New generic wrapper for returning heap-allocated data from Zig functions and methods. `Owned(T)` pairs a value with its allocator; PyOZ converts the inner value to a Python object then automatically frees the backing memory. This eliminates the need for fixed-size stack buffers when building dynamic strings or data. The `pyoz.owned(allocator, value)` constructor auto-coerces mutable slices (`[]u8`) to const (`[]const u8`), so `std.fmt.allocPrint` results can be returned directly without `@as` casts. Supports all return type wrappers: `!Owned(T)` (error union), `?Owned(T)` (optional). Works with any slice type that `toPy` handles.
- **`pyoz.fmt()` -- inline string formatter** - New utility function for formatting strings using Zig's `std.fmt` syntax. Returns a `[*:0]const u8` suitable for passing to `PyErr_SetString`, raise functions, or any API that copies the string immediately. The 4096-byte buffer lives in the caller's stack frame (the function is `inline`), so it is safe to use in one-liners like `return pyoz.raiseValueError(pyoz.fmt("value {d} exceeds limit {d}", .{ val, limit }))`. Eliminates the need for manual `bufPrintZ` boilerplate when building dynamic error messages.
- **`pyoz.base(Parent)` -- single inheritance between PyOZ classes** - New function for declaring that one PyOZ-defined Zig struct inherits from another. The child struct declares `pub const __base__ = pyoz.base(Animal);` and embeds the parent as `_parent: Animal` (must be the first field). PyOZ sets `tp_base` to the parent's type object so `isinstance()`, Python's MRO, and method/property inheritance all work automatically. The child's `__init__` accepts a flattened argument list (parent fields first, then child fields). Parent methods and properties are inherited via MRO — no duplication needed. Works in both non-ABI3 (static type object) and ABI3 (`PyType_FromSpecWithBases`) modes. Comptime validation ensures correct struct layout and parent registration order. Stub generation emits `class Dog(Animal):` with the correct flattened `__init__` signature.
- **`pyoz test` -- inline embedded tests** - New CLI command that builds the module, extracts embedded Python test code from the compiled `.so`, and runs it with `unittest` (stdlib, zero dependencies). Tests are defined inline in the Zig module definition using `pyoz.@"test"("name", \\body)` for assertion tests and `pyoz.testRaises("name", "ExceptionType", \\body)` for exception tests. The generated Python file uses `unittest.TestCase` with proper `assertRaises` context managers. Supports `--verbose/-v` for detailed output and `--release/-r` to build in release mode before testing.
- **`pyoz bench` -- inline embedded benchmarks** - New CLI command that builds the module in release mode, extracts embedded Python benchmark code, and runs it with `timeit` (stdlib). Benchmarks are defined inline using `pyoz.bench("name", \\body)`. The generated script times each benchmark over 100,000 iterations and prints a formatted results table with ops/s. Both commands are available in the Zig CLI (`src/cli`) and Python wrapper (`pyoz test` / `pyoz bench`).
- **`pyoz.TestDef` and `pyoz.BenchDef` types** - New struct types for defining inline tests and benchmarks. `pyoz.@"test"()` creates assertion-based tests, `pyoz.testRaises()` creates exception-checking tests, and `pyoz.bench()` creates benchmarks. These are passed to `pyoz.module()` via the new `.tests` and `.benchmarks` optional config fields.
- **Binary section embedding for tests and benchmarks** - Test and benchmark Python code is generated at comptime and embedded into the compiled `.so` as named sections (`.pyoztest` / `.pyozbenc` on ELF/PE, `__DATA,__pyoztest` / `__DATA,__pyozbenc` on Mach-O), using the same magic-header pattern as stubs (`PYOZTEST` / `PYOZBENC` + 8-byte LE length + content).
- **Generic section extraction in `symreader.zig`** - New `extractNamedSection()` infrastructure that parameterizes section name and magic string across ELF/PE/Mach-O formats. `extractTests()` and `extractBenchmarks()` are thin wrappers. Existing `extractStubs()` is unchanged.
- **Syntax checking before test/bench execution** - `pyoz test` and `pyoz bench` now run `python3 -m py_compile` on the generated Python file before executing it. If the user's inline test/benchmark code has syntax errors, a clear error message with line numbers is shown instead of a confusing runtime traceback.

### Fixed
- **`__hash__` correctness for classes defining `__eq__`** - When a class defines `__eq__` (or any comparison dunder) without explicitly defining `__hash__`, PyOZ now sets `tp_hash = PyObject_HashNotImplemented`, making instances correctly unhashable (raises `TypeError` on `hash()`, cannot be added to sets or used as dict keys). Previously, these classes silently retained the default id-based hash, violating Python semantics. This fix works for both ABI3 and non-ABI3 modes. Classes that define both `__eq__` and `__hash__` continue to work as before.
- **Computed property setters returning `?void` or `!void` caused compile error** - When a `set_X` computed property setter returned an optional (`?void`) or error union (`!void`) instead of plain `void`, the generated wrapper in `properties.zig` discarded the return value, which Zig rejects for non-void types. This prevented using the `return pyoz.raiseValueError("msg")` one-liner pattern in property setters. All three setter code paths (`generateSetter` for field-based custom setters, `generateComputedSetter` for computed properties, and `generatePyozPropertySetter` for `pyoz.property()` API setters) now handle `?void`, `!void`, and plain `void` return types using the same three-branch dispatch pattern used throughout the rest of the codebase (`attributes.zig`, `descriptor.zig`, `sequence.zig`, etc.). Also fixed `generateSetter`'s existing error union branch to preserve already-set Python exceptions instead of overwriting them.
- **Zig errors now map to correct Python exception types** - Previously, all Zig errors (including `error.TypeError`, `error.IndexOutOfBounds`, `error.DivisionByZero`, etc.) were incorrectly raised as `RuntimeError` in Python. Now `setError()` in `wrappers.zig` and `setErrorFromMapping()` in `errors.zig` use a new `mapWellKnownError()` function that first tries an exact match against all `ExcBase` enum variants (covering all 50+ standard Python exceptions like `TypeError`, `ValueError`, `IndexError`, `KeyError`, `ZeroDivisionError`, `AttributeError`, `FileNotFoundError`, `PermissionError`, `MemoryError`, `NotImplementedError`, `StopIteration`, etc.), then checks common Zig-idiomatic aliases (`DivisionByZero` -> `ZeroDivisionError`, `OutOfMemory` -> `MemoryError`, `IndexOutOfBounds` -> `IndexError`, `KeyNotFound` -> `KeyError`, `FileNotFound` -> `FileNotFoundError`, `PermissionDenied` -> `PermissionError`, etc.), and falls back to `RuntimeError` only for truly unrecognized errors.

## [0.10.5] - 2026-02-09

### Added
- **`pyoz.Ref(T)` -- strong Python object references** - New generic type that allows one PyOZ-managed Zig struct to hold a strong reference to another Python object, preventing use-after-free when the referenced object is garbage collected. `Ref(T)` wraps a `?*PyObject` with automatic `Py_IncRef` on `set()` and `Py_DecRef` on `clear()` and object deallocation. Ref fields are automatically excluded from Python properties, `__init__` parameters, stub generation, and auto-doc signatures. Freelist-safe: references are released in `tp_dealloc` before freelist push, and `std.mem.zeroes` on pop ensures no double-free.
- **`Module.selfObject(T, ptr)` helper** - Recovers the wrapping `*PyObject` from a `*const T` data pointer using compile-time offset math. Used to obtain the PyObject needed for `Ref(T).set()` from within methods that receive `self: *const T`.

## [0.10.4] - 2026-02-09

### Fixed
- **Optional return types from methods raised `RuntimeError` instead of returning `None`** - When a Zig method returned `?T` (optional) and the value was `null`, PyOZ raised `RuntimeError: method returned null` instead of returning Python `None`. This affected instance methods, static methods, class methods, `__call__`, `__get__`, `__iter__`, `__repr__`/`__str__`, and number protocol operations. The method dispatch now correctly returns `None` for null optionals (matching the behavior of standalone functions and the conversion system). Improved error messages for `__len__` and `__new__` optional null returns, which are legitimately errors since Python requires concrete values from those slots.

## [0.10.3] - 2026-02-07

### Added
- **PEP 517 build backend** - Added `pyoz.backend` module implementing PEP 517 hooks (`build_wheel`, `build_sdist`, `get_requires_for_build_wheel`). Projects generated by `pyoz init` now set `build-backend = "pyoz.backend"` so `pip install .` works out of the box. Previously, `build-backend = "pyoz.build"` pointed to the `build` function rather than a proper backend module.

### Fixed
- **Methods returning `[]T` on class `T` caused compile error** - When a method on a registered class `T` returned `[]T` (a slice of its own type), PyOZ's method chaining detection misidentified the slice as a `*const T` self-pointer. The return type dispatch now checks for single-item pointers (`.size == .one`) before entering the self-return path, so slices correctly convert to Python lists. The same fix was applied to `__iter__` return handling.

## [0.10.2] - 2026-02-07

### Added
- **Error union and optional return types in all dunder methods** - All magic methods (`__new__`, `__add__`, `__repr__`, `__len__`, `__call__`, `__eq__`, `__iter__`, `__get__`, `__setattr__`, etc.) now support three return conventions: plain `T` (always succeeds), `!T` (error union — Zig errors automatically become Python exceptions), and `?T` (optional — return `null` after calling `pyoz.raiseValueError()` etc.). Previously, only regular functions and a few protocol methods like `__getitem__` supported error unions. This enables raising exceptions from `__new__`, comparison operators, number protocol methods, and all other dunder methods.

### Fixed
- **Cross-compilation from Linux to macOS/Windows** - The PyPI wheel build (`build_wheels.py`) now downloads CPython headers at build time instead of using host Python's platform-specific headers. Previously, cross-compiling from Linux used the host's `pyconfig.h` (a Debian multiarch stub), which failed for non-Linux targets. The build script now extracts headers from the official CPython source tarball, stages the correct `pyconfig.h` per target (Unix LP64 or `PC/pyconfig.h` for Windows), and passes them to Zig via `-Dpython-headers-dir`.
- **Windows .pyd crash on import** - Windows builds previously used `linker_allow_shlib_undefined` which left Python C API symbols as NULL pointers (Windows doesn't support lazy symbol resolution like Unix). The `.pyd` now links against a proper `python3.lib` import library generated at build time from CPython's `stable_abi.toml` using `zig dlltool`, so all `Py_*` symbols resolve correctly against `python3.dll` at load time.

## [0.10.1] - 2026-02-06

### Fixed
- **libpython linking broke abi3 portability** - The 0.10.0 wheels linked against `libpython3.12.so` (the CI's Python version), causing `ImportError` on any other Python version. On Linux/macOS, the extension no longer links against libpython at all (symbols come from the interpreter at runtime). On Windows, it links against `python3.dll` (the version-agnostic stable ABI DLL) instead of `python3XX.dll`.

## [0.10.0] - 2026-02-06

### Added
- **Native PyPI package** - The `pyoz` pip package is now a native Python extension module built with PyOZ itself (dogfooding). Instead of embedding a CLI binary and forwarding via subprocess, the package exposes `init()`, `build()`, `develop()`, `publish()`, and `version()` as directly callable Python functions. This enables programmatic usage in custom `setup.py` scripts, CI pipelines, and build automation.
- **ABI3 (Stable ABI) wheels** - The `pyoz` pip package now builds with Python's Stable ABI (`abi3`), targeting Python 3.8+. A single `cp38-abi3-{platform}` wheel works across all Python versions (3.8, 3.9, 3.10, ..., 3.13+), reducing the number of wheels from one-per-Python-version-per-platform to one-per-platform. Cross-compilation from a single CI runner (ubuntu) is supported since abi3 headers are platform-agnostic.

### Fixed
- **`pyoz init` now patches dependency hash** - When creating a project with a remote PyOZ URL dependency, `pyoz init` now automatically patches the `.hash` field in `build.zig.zon` by running `zig build` a second time after fingerprint patching. Previously, users had to manually fix the missing hash error on first build.
- **`raise*` functions no longer require `inline`** - All `raise*` functions (`raiseRuntimeError`, `raiseValueError`, etc.) are now declared `inline`. Previously, calling them from a non-inline function caused a compilation error (`call to function with comptime-only return type '@TypeOf(null)' is evaluated at comptime`) because the `Null` return type is comptime-only. Users had to manually add `inline` to their own wrapper functions as a workaround.

## [0.9.0] - 2026-02-06

### Added
- **`module-name` config option** - New `[tool.pyoz]` field that decouples the native `.so` name from the pip package name. Set `module-name = "_mypackage"` to produce `_mypackage.so`, allowing a Python wrapper package with the same base name (e.g., `mypackage/`) to coexist. This enables the standard Python pattern used by `_sqlite3`/`sqlite3`, `_json`/`json`, etc.
- **`include-ext` config option** - New `[tool.pyoz]` field to control which file extensions are included from `py-packages` directories. Defaults to `["py"]` for backwards compatibility. Set `["*"]` to include all files, or list specific extensions like `["py", "zig", "json"]`. Useful for packaging template files, data files, or other non-Python assets alongside your Python code.
- **`Module.toPy()` / `Module.fromPy()`** - Module types now expose class-aware converters. Use `Module.toPy(MyClass, instance)` to convert registered class instances to Python objects when building raw Python containers (lists, dicts) manually. Unlike `pyoz.Conversions` (which has no class knowledge), the module converter knows about all registered classes and can wrap them into proper Python wrapper objects. Also exposes `Module.ClassConverter` for direct access to the full converter type.
- **Stub `method__returns__` convention** - Declare `pub const children__returns__: []const u8 = "list[Node]"` on a class struct to override the return type annotation in generated `.pyi` stubs. Useful for methods returning `?*pyoz.PyObject` where the concrete Python type is known to the developer.
- **Stub `method__params__` convention** - Declare `pub const find__params__: []const u8 = "rule_name"` on a class struct to override parameter names in generated `.pyi` stubs. Accepts comma-separated names (excluding `self`). Falls back to `arg0, arg1, ...` when not declared. Needed because Zig's `@typeInfo` does not expose function parameter names.

### Fixed
- **Stub generator: duplicate class for exception+class** - When a type was registered as both a class and an exception (e.g., `ParseError`), the stub generator emitted two separate `class` definitions. Now they are merged into a single `class ParseError(Exception):` definition with all methods, properties, and the class docstring.
- **Stub generator: dunder return types were `Any`** - Magic methods like `__iter__`, `__next__`, `__getitem__`, `__call__`, `__enter__` used hardcoded `Any` return types. Now they introspect the actual Zig function signatures: `__iter__` returns `Iterator[Element]`, `__next__` unwraps the optional to the element type, `__getitem__` shows the actual key and value types, `__enter__` resolves to the class name when returning `*Self`, and `__call__` introspects its full signature.
- **Stub generator: class `__doc__` was placeholder** - Class docstrings declared via `pub const __doc__` were detected but emitted as `"""..."""` instead of the actual content. Now the full docstring text is propagated to the `.pyi` file.
- **Stub generator: method docstrings were ignored** - Method docstrings declared via `pub const method__doc__` (e.g., `magnitude__doc__`) were explicitly skipped during stub generation. Now they are emitted as Python docstrings in the generated `.pyi` file.
- **`get_*` property scanner treated non-functions as getters** - The computed property system (`properties.zig`) and stub generator (`stubs.zig`) scanned for `get_*` declarations but didn't verify they were functions. Declarations like `get_error__doc__` (a `[*:0]const u8` docstring for a `get_error` method) were misinterpreted as computed property getters, causing "type '[*:0]const u8' not a function" errors. Both scanners now skip non-function `get_*` declarations.
- **`__repr__`/`__str__` use-after-free** - Fixed a memory safety bug where returning `[]const u8` from a stack-local `bufPrint` buffer in `__repr__` or `__str__` caused undefined behavior. The callee's stack frame was destroyed before PyOZ could copy the data into a Python string. Both methods now support a buffered signature `fn __repr__(self: *const T, buf: []u8) []const u8` where PyOZ provides a 4096-byte buffer that stays alive through the `toPy` call. The legacy 1-parameter signature still works for string literals.
- **`raiseValueError` and friends required `comptime` or `inline`** - Removed unnecessary `comptime` qualifier from the message parameter on all raise functions (`raiseValueError`, `raiseTypeError`, `raiseException`, custom `raise`, etc.). The `comptime` restriction prevented calling these from non-inline contexts and added no value since `PyErr_SetString` is a runtime C call. String literals still work as before; runtime strings are now also accepted.
- **Slot-handled dunders double-registered as methods** - The method table generator (`methods.zig`) was registering protocol dunders like `__repr__`, `__str__`, `__hash__`, `__add__`, etc. as regular Python methods in addition to their protocol slots. This caused compilation errors when the dunder's signature didn't match the regular method wrapper expectations (e.g., the new buffered `__repr__` with `[]u8` parameter). Now only slot-handled dunders are excluded; other dunders like `__enter__`, `__exit__`, and `__missing__` still pass through to the method table as intended.
- **`pyoz init` remote fingerprint generation** - Previously, `pyoz init` (without `--local`) generated a random fingerprint for `build.zig.zon` that Zig would reject on first build, requiring manual fix-ups. Now both local and remote paths use the same strategy: write without fingerprint, run `zig build`, and patch with the suggested value. Extracted shared `patchFingerprint` helper used by both code paths.

### Documentation
- **Raw `*pyoz.PyObject` as return type** - Documented that `*pyoz.PyObject` works as both parameter and return type in class methods. Added examples for building and returning raw Python objects from Zig methods.
- **One-liner raise pattern** - Documented that `raiseValueError()` and friends return `Null`, enabling `return pyoz.raiseValueError("msg")` as a one-liner in any function returning an optional type.
- **GC `__traverse__`/`__clear__` example** - Added a complete code example showing correct signatures (`c_int` return, by-value `GCVisitor`), visitor return value checking, and `Py_DecRef` cleanup in `__clear__`.

## [0.8.0] - 2026-02-06

### Added
- **PyPI distribution** - PyOZ CLI is now available via `pip install pyoz`. The package bundles pre-built statically-linked binaries for all major platforms (Linux x86_64/aarch64, macOS x86_64/arm64, Windows x86_64/arm64). No runtime dependencies required.
- **Automated wheel building** - Added `pypi/build_wheels.py` script that creates platform-tagged wheels from cross-compiled Zig binaries. Supports building for all 6 target platforms from a single machine.
- **CI/CD PyPI publishing** - Release workflow now automatically builds and publishes wheels to PyPI when a version tag is pushed.

## [0.7.1] - 2026-02-06

### Fixed
- **Cross-class references now work between module classes** - When a module defines multiple classes (e.g., `Point` and `Line`), methods on one class can now accept or return instances of another class in the same module. Previously, class method wrappers only knew about their own class (or no classes at all), so cross-class conversions would fail with `TypeError` or `SystemError`. The fix threads the full `class_infos` list through the entire class generation pipeline — from `generateClass()` through every protocol builder (methods, lifecycle, properties, number, sequence, mapping, descriptor, repr, attributes, iterator, callable, comparison) — so every converter sees all sibling classes. Cyclic references (A references B and B references A) work correctly thanks to Zig's comptime memoization.
- **Comparison operators now support cross-class types** - `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__` previously hardcoded the `other` parameter to be the same type as `self`. Now the comparison protocol introspects each method's signature and uses the class-aware converter, so `__eq__(self: *const A, other: *const B) bool` works correctly.
- **`__int__`, `__float__`, `__index__` now use class-aware converter** - These number protocol methods were using the old zero-class `Conversions.toPy()` instead of the class-aware `Conv.toPy()`, which would have failed if they returned a custom class type.
- **Class parameters now supported by value and by pointer** - Methods can now accept class instances either by pointer (`fn foo(p: *const Point)`) or by value (`fn foo(p: Point)`). Previously only pointer parameters worked for cross-class references; by-value parameters would fail with `TypeError` because the struct branch of `fromPy` didn't check registered class types.

## [0.7.0] - 2026-02-06

### Added
- **Complete Python exception hierarchy** - Added all missing exception types from the CPython hierarchy, covering every exception from `BaseException` down through all subclasses including `NameError`, `UnboundLocalError`, `ReferenceError`, `SyntaxError`, `IndentationError`, `TabError`, `StopAsyncIteration`, and all 11 Warning types (`Warning`, `DeprecationWarning`, `UserWarning`, `RuntimeWarning`, etc.)
- **Ergonomic raise functions returning `Null`** - All `raise*` functions now return `@TypeOf(null)` (aliased as `Null`), enabling one-liner error returns: `return pyoz.raiseValueError("bad input")`. The `null` literal coerces to any optional type (`?*PyObject`, `?i64`, `?f64`, etc.)
- **21 new raise functions** - `raiseAssertionError`, `raiseFloatingPointError`, `raiseLookupError`, `raiseNameError`, `raiseUnboundLocalError`, `raiseReferenceError`, `raiseStopAsyncIteration`, `raiseSyntaxError`, `raiseUnicodeError`, `raiseModuleNotFoundError`, `raiseBlockingIOError`, `raiseBrokenPipeError`, `raiseChildProcessError`, `raiseConnectionAbortedError`, `raiseConnectionRefusedError`, `raiseConnectionResetError`, `raiseFileExistsError`, `raiseInterruptedError`, `raiseIsADirectoryError`, `raiseNotADirectoryError`, `raiseProcessLookupError`
- **17 new `PythonException.is*` methods** - `isMemoryError`, `isOSError`, `isNotImplementedError`, `isOverflowError`, `isFileNotFoundError`, `isPermissionError`, `isTimeoutError`, `isConnectionError`, `isEOFError`, `isImportError`, `isNameError`, `isSyntaxError`, `isRecursionError`, `isArithmeticError`, `isBufferError`, `isSystemError`, `isUnicodeError`
- **`ExcBase` enum expanded to 60+ variants** - Users can now use any standard Python exception as a base for custom exceptions via `pyoz.exception("MyError", .SyntaxError)` or any other variant
- **`PyExc` struct covers the full hierarchy** - Programmatic access to every built-in Python exception type
- **`__del__` hook for custom cleanup** - Structs can now define `pub fn __del__(self: *Self) void` which PyOZ calls during `tp_dealloc` before freeing the Python object. This allows releasing C memory, closing file handles, invalidating resources, etc. Works in both normal and ABI3 modes with zero runtime cost for types that don't define it.
- **`Callable(ReturnType)` wrapper for Python callbacks** - Type-safe wrapper for accepting and invoking Python callables from Zig. Handles automatic argument marshalling (Zig→Python conversion), result conversion (Python→Zig), full refcounting, and exception propagation. Supports any number of arguments via `.call(.{args})`, a `.callNoArgs()` shortcut, and `Callable(void)` for callbacks with no return value. Works in ABI3 mode.
- **`__class_getitem__` support (PEP 560)** - Structs can declare `pub const __class_getitem__ = true;` to enable `MyClass[int]` generic type syntax. Returns `types.GenericAlias` on Python 3.9+, falls back gracefully on 3.8. Works in ABI3 mode.
- **`allowThreads` / `allowThreadsTry`** - Ergonomic GIL release wrappers. Call any function without the GIL in one line: `pyoz.allowThreads(compute, .{data})`. `allowThreadsTry` supports error-returning functions with `defer`-based GIL restoration.
- **Freelist / Object Pooling** - Structs can declare `pub const __freelist__: usize = N;` to cache up to N deallocated objects for reuse, avoiding allocator overhead for frequently created/destroyed objects. Objects are automatically re-initialized on reuse.
- **Mixed Zig/Python packages** - New `py-packages = ["mypackage"]` option in `[tool.pyoz]` section of `pyproject.toml`. Pure Python packages are included in wheels and symlinked in develop mode, enabling hybrid Zig+Python projects.
- **Optional constructor arguments** - `__new__` functions can now use optional types (`?f64`, `?i64`, etc.) for trailing parameters. Omitted arguments default to `null`, enabling `MyClass(1.0)` when `y: ?f64` and `z: ?f64` are optional.
- **Signal handling (`checkSignals`)** - New `pyoz.checkSignals()` function for cooperative Ctrl+C / KeyboardInterrupt support in long-running Zig code. Returns `error.Interrupted` when a signal is pending (Python exception already set). Error wrappers now preserve already-set Python exceptions instead of overwriting them.

### Changed
- **Raise functions now take `comptime message`** - All raise functions accept `comptime message: [*:0]const u8` instead of runtime strings, which enables the `@TypeOf(null)` return type

## [0.6.2] - 2026-02-06

### Added
- **Auto-generated `__repr__` for classes without custom `__repr__`** - Classes that don't define a `__repr__` method now automatically get a repr in the form `ClassName(field1=val1, field2=val2)`. Private fields (starting with `_`) are excluded from the output.
- **Auto-generated `tp_doc` for classes without `__doc__`** - Classes that don't declare a `__doc__` string now get an auto-generated docstring showing the constructor signature and field types, e.g. `SimplePoint(x, y)\n\nAttributes:\n    x: float\n    y: float`. This makes `help(MyClass)` useful out of the box.
- **`ClassInfo` struct for the conversion system** - Introduced `ClassInfo` (pairing a custom name with a Zig type) to thread custom class names through the entire comptime pipeline, replacing bare `type` arrays.
- **`getWrapperWithName(name, T)`** - New comptime function that generates a class wrapper using the provided custom name, ensuring a single consistent type instantiation across registration and conversion.

### Changed
- **All protocol signatures normalized to `(name, T, Parent)`** - Every protocol that accepts a class name now takes it as the first parameter for consistency: `NumberProtocol`, `SequenceProtocol`, `MappingProtocol`, `IteratorProtocol`, `CallableProtocol`, `DescriptorProtocol`, `ReprProtocol`, `AttributeProtocol`, and `MethodBuilder`.
- **All protocols now use class-aware converters** - `SequenceProtocol`, `MappingProtocol`, and `DescriptorProtocol` now use `getSelfAwareConverter(name, T)` instead of the generic `Conversions`, matching the pattern already used by `NumberProtocol`, `CallableProtocol`, `IteratorProtocol`, and `MethodBuilder`.
- **Conversion system uses `ClassInfo` instead of bare types** - `Converter`, all wrapper functions in `wrappers.zig`, and `extractClassInfo` in `root.zig` now work with `[]const ClassInfo` to ensure custom class names are used everywhere.

### Fixed
- **`help(module)` now lists all registered classes** - Classes were missing from `help(module)` because their `__module__` attribute was `builtins` instead of the module name. Fixed by setting `tp_name` to the qualified form `"module.ClassName"`, which Python uses to derive `__module__` automatically.
- **Custom class names now propagate through the entire system** - Previously, `getWrapper(T)` used `@typeName(T)` which produced internal Zig paths like `os.linux.kernel_timespec`. When using external types with `py.class("Timespec", std.os.linux.kernel_timespec)`, the custom name now correctly appears in `__repr__`, `tp_doc`, error messages, and `help()` output.
- **Fixed dual comptime instantiation bug** - Registration and conversion previously created separate type instantiations (one with the custom name, one with `@typeName`), causing objects returned from functions to lack properties and methods. Both paths now use the same `getWrapperWithName` instantiation.

## [0.6.1] - 2026-02-05

### Added
- **Private Fields Convention** - Fields starting with underscore (`_`) are now treated as private:
  - Private fields are NOT exposed to Python as properties
  - Private fields are NOT included in `__init__` arguments
  - Private fields are NOT included in generated `.pyi` type stubs
  - Private fields are zero-initialized and only accessible via Zig methods
  - Example:
    ```zig
    const MyClass = struct {
        name: []const u8,      // Public - exposed to Python
        value: i64,            // Public - exposed to Python
        _internal: i64,        // Private - hidden from Python
        _cache: ?SomeType,     // Private - hidden from Python
    };
    ```

### Fixed
- **Property getter exception handling** - When a field's type cannot be converted to Python, accessing the property now correctly raises a `TypeError` instead of returning `NULL` without setting an exception (which caused undefined behavior)
- **Custom class names now work correctly** - When registering a class with `pyoz.class("CustomName", T)`, the Python-visible class name (`__name__`) now correctly uses the custom name instead of the Zig type name. This affects both ABI3 and non-ABI3 modes.
- **Improved error message preservation** - When conversion code sets a Python exception (via `PyErr_SetString`) before returning a Zig error, that exception is now preserved instead of being overwritten with a generic `RuntimeError`. This ensures users see the actual error message rather than just the error enum name.
- **BufferView.get2D/set2D no longer panic on wrong dimensions** - The `get2D()` and `set2D()` methods on `BufferView` and `BufferViewMut` now raise a `ValueError` with a descriptive message ("get2D requires a 2D array" / "set2D requires a 2D array") instead of panicking when called on non-2D arrays. This prevents crashes when Python users pass 1D arrays to functions expecting 2D arrays.

### Security
- **Fixed integer overflow in sequence protocol for unsigned index types** - When a class's `__getitem__`, `__setitem__`, or `__delitem__` uses an unsigned integer type (e.g., `usize`) for the index parameter, negative indices from Python would previously cause an `@intCast` overflow. This resulted in a panic in safe/debug builds or undefined behavior (out-of-bounds memory access) in release builds. PyOZ now implements Python-style negative index wrapping (`arr[-1]` → `arr[len-1]`) for unsigned index types, and raises `IndexError` for indices that are still negative after wrapping (e.g., `arr[-100]` on an 8-element array).

- **Fixed buffer protocol crash on negative shape/ndim values** - When consuming buffers via `BufferView`, PyOZ now validates that `ndim` and all shape dimensions are non-negative before casting to unsigned types. Previously, a buffer with negative shape values (from a buggy `__buffer__` implementation) would cause an `@intCast` panic in safe mode or memory corruption in release mode. PyOZ now raises `ValueError` with a clear message ("Buffer has negative shape dimension" or "Buffer has negative ndim"). This affects both standard and ABI3 modes.

- **Fixed BufferView.get2D/set2D crash on negative strides** - The `get2D()` and `set2D()` methods now validate that strides are non-negative before casting to unsigned types. Previously, a buffer with negative strides would cause an `@intCast` panic in safe mode or memory corruption in release mode. PyOZ now raises `ValueError` with a clear message ("Buffer has negative strides").

- **Fixed integer conversion crash on overflow** - When converting Python integers to smaller Zig integer types (e.g., `u8`, `i16`), values that exceed the target type's range now wrap (truncate) like C instead of causing an `@intCast` panic. For example, passing `300` to a function expecting `u8` now results in `44` (300 mod 256) instead of crashing.

- **Added null buffer pointer validation** - PyOZ now validates that the buffer data pointer is not null before creating a BufferView. A malicious `__buffer__` implementation that returns success but sets `buf` to NULL now raises `ValueError` instead of crashing.

## [0.6.0] - 2025-11-30

### Added
- **Initial attempt at ABI3 (Stable ABI) Support** - Build Python extensions compatible with Python 3.8+
  - Enable via `-Dabi3=true` build option or `abi3 = true` in pyproject.toml
  - Uses Python's Limited API (`Py_LIMITED_API = 0x03080000`) for forward compatibility
  - Single wheel works across Python 3.8, 3.9, 3.10, 3.11, 3.12, 3.13+
  - Wheel tags correctly use `cp38-abi3-platform` format
  - Comprehensive example module demonstrating all ABI3-compatible features

- **ABI3-Compatible Features** - Most PyOZ features work in ABI3 mode:
  - All basic types: int, float, bool, strings, bytes, complex, datetime, decimal, path
  - Collections: list, dict, set (via Views)
  - Classes with all magic methods: `__add__`, `__sub__`, `__mul__`, `__eq__`, `__lt__`, etc.
  - Context managers: `__enter__`, `__exit__`
  - Descriptors: `__get__`, `__set__`, `__delete__`
  - Dynamic attributes: `__getattr__`, `__setattr__`, `__delattr__`
  - Iterators: `__iter__`, `__next__`, `__reversed__`
  - Callable objects: `__call__` with multiple arguments
  - Hashable/frozen classes: `__hash__`, `__frozen__`
  - Class attributes via `classattr_*` prefix
  - Computed properties via `get_X`/`set_X` pattern
  - `pyoz.property()` API for explicit property definitions
  - GIL management: `releaseGIL()`, `acquireGIL()` (stable ABI functions)
  - Enums (IntEnum and StrEnum)
  - Custom exceptions with inheritance
  - Error mappings
  - In-place operators: `__iadd__`, `__ior__`, `__iand__`, etc.
  - Reflected operators: `__radd__`, `__rmul__`, etc.
  - Matrix operators: `__matmul__`, `__rmatmul__`, `__imatmul__`
  - Type coercion: `__int__`, `__float__`, `__bool__`, `__complex__`, `__index__`
  - `Iterator(T)` and `LazyIterator(T, State)` producers
  - `BufferView(T)` for read-only numpy array access

- **ABI3 Configuration in pyproject.toml**:
  ```toml
  [tool.pyoz]
  abi3 = true  # Enable ABI3/Limited API mode
  ```

- **ABI3 Limitations** - Features NOT available in ABI3 mode:
  - `BufferViewMut(T)` - Mutable buffer access requires unstable API
  - `__base__` inheritance - Extending Python built-in types (list, dict) not supported
  - `__dict__` / `__weakref__` support - Requires type flag access
  - `__buffer__` producer protocol - Buffer export requires unstable structures
  - Submodules - Module hierarchy requires `tp_dict` access
  - GC protocol (`__traverse__`, `__clear__`) - May work but needs verification

- **`Iterator(T)` producer type** - Return Python lists from Zig slices
  - Eager evaluation: converts slice to Python list immediately
  - Use for small, known data sets
  ```zig
  fn get_fibonacci() pyoz.Iterator(i64) {
      const fibs = [_]i64{ 1, 1, 2, 3, 5, 8, 13, 21, 34, 55 };
      return .{ .items = &fibs };
  }
  ```

- **`LazyIterator(T, State)` producer type** - Return lazy Python iterators
  - Generates values on-demand, memory efficient for large/infinite sequences
  - State struct must implement `pub fn next(self: *@This()) ?T`
  ```zig
  const RangeState = struct {
      current: i64, end: i64, step: i64,
      pub fn next(self: *@This()) ?i64 {
          if (self.current >= self.end) return null;
          const val = self.current;
          self.current += self.step;
          return val;
      }
  };
  fn lazy_range(start: i64, end: i64, step: i64) pyoz.LazyIterator(i64, RangeState) {
      return .{ .state = .{ .current = start, .end = end, .step = step } };
  }
  ```

- **`ByteArray` producer support** - Return Python `bytearray` from Zig
  - Previously `ByteArray` was consumer-only (could only receive from Python)
  - Now supports bidirectional conversion

### Changed
- **Type markers are now `pub const`** - All internal type markers (`_is_pyoz_*`) are now public
  - Fixes cross-module `@hasDecl` detection which requires public declarations
  - Affected types: `Set`, `FrozenSet`, `Dict`, `Iterator`, `LazyIterator`, `ListView`, `DictView`, `SetView`, `IteratorView`, `BufferView`, `BufferViewMut`, `Complex`, `DateTime`, `Date`, `Time`, `TimeDelta`, `Bytes`, `ByteArray`, `Path`, `Decimal`

- **View types now use distinct markers** - Consumer (View) types have separate markers from producer types
  - `_is_pyoz_set_view` vs `_is_pyoz_set`
  - `_is_pyoz_dict_view` vs `_is_pyoz_dict`
  - `_is_pyoz_list_view` (no producer equivalent, use slices)
  - `_is_pyoz_iterator_view` vs `_is_pyoz_iterator`
  - `_is_pyoz_buffer` vs `_is_pyoz_buffer_mut`

- **`conversion.zig` refactored to use markers consistently**
  - All type detection now uses `@hasDecl(T, "_is_pyoz_*")` instead of direct type comparison
  - Improves extensibility and consistency across the codebase

- **`stubs.zig` updated for new types**
  - `Iterator(T)` generates `list[T]` type hint (eager, returns list)
  - `LazyIterator(T, State)` generates `Iterator[T]` type hint (lazy iterator)
  - `Dict(K, V)` producer now properly detected via `_is_pyoz_dict` marker
  - `BufferViewMut(T)` now properly detected via `_is_pyoz_buffer_mut` marker
  - Added `Iterator` to typing imports for lazy iterator support

### Documentation
- **Types guide updated** - Added Iterator vs LazyIterator section with usage examples
- **View type asymmetry explained** - Documented why Views are consumer-only

### Fixed
- **Incorrect wheel ABI tag** - Wheels were incorrectly tagged as `abi3` even though PyOZ doesn't use `Py_LIMITED_API`
  - Changed from `cp312-abi3-platform` to correct `cp312-cp312-platform` format
  - ABI3 support will be added in a future release with proper Limited API compliance

- **Misleading Linux platform tag** - Changed default from `manylinux_2_17` to `linux_x86_64`/`linux_aarch64`
  - `manylinux` tags promise glibc compatibility that we can't guarantee without building in manylinux containers
  - Users can now override via `linux-platform-tag` in pyproject.toml for proper manylinux builds

- **Hardcoded macOS platform tag** - Now detects actual macOS version at runtime
  - Previously hardcoded `macosx_10_9_x86_64` and `macosx_11_0_arm64`
  - Now uses Python's `platform.mac_ver()` to detect actual OS version (e.g., `macosx_14_5_arm64`)

### Added
- **`linux-platform-tag` configuration option** in pyproject.toml
  ```toml
  [tool.pyoz]
  # Override Linux platform tag for manylinux builds
  linux-platform-tag = "manylinux_2_17_x86_64"
  ```
  - Allows users building in manylinux Docker containers to use proper manylinux tags
  - Default remains `linux_x86_64` / `linux_aarch64` for honest compatibility

## [0.5.0] - 2025-11-27

### Added
- **Full documentation site** at [pyoz.dev](https://pyoz.dev)
  - Complete guide covering functions, classes, properties, types, errors, enums, NumPy, GIL, submodules, and type stubs
  - CLI reference for `pyoz init`, `pyoz build`, `pyoz develop`, `pyoz publish`
  - Built with MkDocs and Material theme with dark/light mode support
  - Auto-deployed via webhook on push to main

- **Declarative property API** - New `pyoz.property()` for cleaner property definitions
  ```zig
  .properties = &.{
      pyoz.property("length", .{ .get = "get_length", .set = "set_length" }),
      pyoz.property("area", .{ .get = "get_area" }),  // read-only
  },
  ```
  - Explicit property declaration instead of relying on `get_`/`set_` naming convention
  - Supports read-only, write-only, and read-write properties
  - Old `get_X`/`set_X` convention still works for backward compatibility

### Changed
- **README rewritten** - Minimal, focused README with links to documentation site
- **CI workflow** - Now only runs on pull requests, not on push

### Fixed
- **Enum literal type checking** - Fixed compile error when checking exception enum literals
- **Property stub generation** - Properties now correctly generate type stubs

## [0.4.0] - 2025-11-27

### Added
- **Automatic `.pyi` stub generation** - Type stubs are now generated at compile time
  - Full Python type hints for all exported functions, classes, methods, and properties
  - Supports complex types: `list[T]`, `dict[K, V]`, `tuple[...]`, `Optional[T]`, `Union[...]`
  - Docstrings are included in generated stubs
  - Stubs are automatically embedded in the compiled binary and extracted during wheel building
  - Works with stripped binaries via dedicated `.pyozstub` section that survives stripping
  - New `--no-stubs` flag for `pyoz build` to disable stub generation
  - New `--stubs` flag (default) to explicitly enable stub generation

- **Strip support in pyproject.toml** - Binary stripping now fully functional
  - Added `strip = true` option in `[tool.pyoz]` section
  - Stubs survive stripping via section-based embedding with `PYOZSTUB` magic header
  - Works with all optimization levels including `ReleaseSmall`

- **Cross-platform symreader** - Extract embedded data from compiled modules
  - Supports ELF (Linux), PE (Windows), and Mach-O (macOS) binary formats
  - Section-based extraction (`.pyozstub`) for stripped binaries
  - Symbol-based extraction (`__pyoz_stubs_data__`, `__pyoz_stubs_len__`) as fallback
  - Comprehensive test suite with cross-compiled test binaries for all formats

- **Symreader tests in build.zig** - Test infrastructure for binary format parsing
  - Cross-compiles test stub libraries for x86_64-linux, x86_64-windows, x86_64-macos
  - Tests ELF, PE, and Mach-O parsers with real binaries
  - Uses `b.addWriteFiles()` to inject test code at build time

### Changed
- Generated `build.zig` template now includes `-Dstrip` option support
- Stubs are embedded in both symbol form (for non-stripped) and section form (for stripped)
- Section names: `.pyozstub` (ELF/PE), `__DATA,__pyozstub` (Mach-O)

## [0.3.1] - 2025-11-26

### Added
- **Cross-platform CI testing for example module** - Tests on Linux, Windows, and macOS
  - New `example-module` job in CI workflow testing 3 platforms × 4 Python versions (3.10-3.13)
  - Comprehensive test coverage: basic functions, classes, magic methods, `__base__` inheritance, iterator views, dict/set views, datetime types, error handling, custom exceptions, NumPy buffers, and submodules
  - Added `examples/**` to CI trigger paths
  - Added format checking for `examples/` directory

### Fixed
- **macOS Python 3.13 crash during interpreter shutdown** - Fixed use-after-free in submodule creation
  - `createSubmodule` was allocating `PyModuleDef` on the stack, but Python stores a reference to it
  - When the function returned, the stack memory became invalid
  - During Python's GC traversal at shutdown, accessing the freed memory caused a crash
  - Fix: Use a comptime-generated static struct to hold the `PyModuleDef`
- **Windows support** - PyOZ now works correctly on Windows
  - Replaced `python3-config` with `sysconfig` module for cross-platform Python detection
  - Fixed library naming (`python313` on Windows vs `python3.13` on Unix)
  - Fixed example module extension (`.pyd` on Windows vs `.so` on Unix)
  - Fixed crash when inheriting from Python built-in types (`__base__`)
    - On Windows, DLL data imports (like `PyList_Type`) require runtime address resolution
    - Comptime initialization used import thunk address instead of actual type object
    - Added runtime `initBase()` for Windows while preserving comptime on Linux/macOS

### Changed
- Python detection now uses `sysconfig` module (standard library since Python 3.2) on all platforms
- `python3-config` is no longer required on any platform

## [0.3.0] - 2025-11-26

### Added
- **Universal iterator support via IteratorView** - Accept any Python iterable
  - `IteratorView(T)` for accepting any iterable (list, tuple, set, generator, range, etc.)
  - Methods: `next()`, `count()`, `collect()`, `forEach()`, `find()`, `any()`, `all()`
  - Zero-copy: wraps Python iterator directly, no data copying
  - Works with generators, ranges, and custom iterables
- `PyIter_Check()` and `PyObject_IsIterable()` Python C API bindings
- `Iterator(T)` and `LazyIterator(T, State)` types for returning iterators (placeholder for future)

### Fixed
- **Use-after-free bug in Path conversion for pathlib.Path objects** - Python 3.9 compatibility
  - `PyPath_AsString()` was decref'ing the string before returning, causing segfaults
  - Added `PyPath_AsStringWithRef()` to return both string slice and owning PyObject
  - Path struct now stores Python object reference and releases it after function call
  - Proper cleanup in function wrappers ensures no memory leaks

### Changed
- **Major internal refactoring of class generation** - Improved maintainability
  - Split monolithic `class.zig` (2,887 lines) into 16 modular files
  - New `src/lib/class/` directory with protocol-specific modules:
    - `mod.zig` - Main orchestrator combining all protocols
    - `wrapper.zig` - PyWrapper struct builder
    - `lifecycle.zig` - Object lifecycle (new, init, dealloc)
    - `number.zig` - Number protocol (~700 lines of numeric operations)
    - `sequence.zig` - Sequence protocol
    - `mapping.zig` - Mapping protocol
    - `comparison.zig` - Rich comparison
    - `repr.zig` - String representation (__repr__, __str__, __hash__)
    - `iterator.zig` - Iterator protocol (__iter__, __next__)
    - `buffer.zig` - Buffer protocol
    - `descriptor.zig` - Descriptor protocol
    - `attributes.zig` - Attribute access (__getattr__, __setattr__)
    - `callable.zig` - Callable protocol (__call__)
    - `properties.zig` - Property generation (getters/setters)
    - `methods.zig` - Method wrappers (instance, static, class)
    - `gc.zig` - Garbage collection support
  - All comptime generation preserved - no functionality changes
  - Public API unchanged - fully backward compatible

## [0.2.0] - 2025-11-26

### Added
- **NumPy array support via BufferView** - Zero-copy access to numpy arrays
  - `BufferView(T)` for read-only access to numpy arrays
  - `BufferViewMut(T)` for mutable (in-place) access
  - Supported dtypes: `f64`, `f32`, `i64`, `i32`, `i16`, `i8`, `u64`, `u32`, `u16`, `u8`
  - Complex number support: `complex128` (`pyoz.Complex`), `complex64` (`pyoz.Complex32`)
  - Both C-contiguous and Fortran-contiguous array layouts supported
  - 2D array support with `rows()`, `cols()`, `get2D()`, `set2D()` methods
  - Automatic buffer release after function call
- `Complex32` type for 32-bit complex numbers (two f32s)
- Complex number arithmetic methods: `add`, `sub`, `mul`, `conjugate`, `magnitude`
- Comprehensive test suite for numpy/BufferView functionality
- Fair comparison with Ziggy-Pydust in README documentation

## [0.1.2] - 2025-11-26

### Added
- CI workflow for automated testing and format checking
- Support for Python 3.9, 3.10, 3.11, 3.12, and 3.13

### Fixed
- Python 3.12+ compatibility: handle `ob_refcnt` anonymous union (PEP 683 immortal objects)
- Python 3.9 compatibility: reimplement type check functions to avoid cImport macro issues
- Python 3.12+ compatibility: use extern declarations for GIL functions to avoid `PyThreadState` struct issues

### Changed
- First stable release (no longer alpha)
- Type check functions (`PyLong_Check`, `PyFloat_Check`, etc.) reimplemented for cross-version compatibility
- `PyThreadState` defined as opaque type for broader Python version support

## [0.1.1-alpha] - 2025-11-26

### Added
- Deflate compression for wheel packages using miniz (58% smaller wheels)
- Virtual environment detection in `pyoz develop` (auto-installs to venv site-packages)
- README.md content included in wheel METADATA for PyPI project descriptions

### Changed
- Default ZIP compression method changed from STORE to DEFLATE

## [0.1.0-alpha] - 2025-11-26

### Added
- Initial release of PyOZ
- Core library for creating Python extension modules in Zig
- CLI tool (`pyoz`) for project management
  - `pyoz init` - Create new projects (with `--local` flag for development)
  - `pyoz build` - Build extension modules (debug/release)
  - `pyoz develop` - Install in development mode
  - `pyoz publish` - Publish to PyPI/TestPyPI
- Automatic type conversions between Python and Zig
  - Primitives: int, float, bool, strings
  - Collections: list, dict, set, frozenset, tuple
  - Special types: datetime, complex, decimal, bytes, path
  - 128-bit integers (i128/u128)
- Full class support with automatic method detection
  - Instance methods (takes `*Self` or `*const Self`)
  - Static methods (no self parameter)
  - Class methods (`comptime cls: type` first parameter)
  - Computed properties (`get_X`/`set_X` pattern)
- Comprehensive Python protocol support
  - Comparison: `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`
  - Numeric: `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`, `__mod__`, `__pow__`, etc.
  - In-place operators: `__iadd__`, `__isub__`, etc.
  - Reflected operators: `__radd__`, `__rsub__`, etc.
  - Unary: `__neg__`, `__pos__`, `__abs__`, `__invert__`
  - Type coercion: `__int__`, `__float__`, `__bool__`, `__index__`, `__complex__`
  - Sequence/Mapping: `__len__`, `__getitem__`, `__setitem__`, `__delitem__`, `__contains__`
  - Iterator: `__iter__`, `__next__`, `__reversed__`
  - Context manager: `__enter__`, `__exit__`
  - Callable: `__call__`
  - Attribute access: `__getattr__`, `__setattr__`, `__delattr__`
  - Descriptor: `__get__`, `__set__`, `__delete__`
  - Buffer protocol: `__buffer__` (numpy compatible)
  - Object: `__repr__`, `__str__`, `__hash__`
- GIL control (`releaseGIL()`, `acquireGIL()`, `withGIL()`)
- Exception handling and custom exceptions
- Error mapping (Zig errors to Python exceptions)
- `__dict__` support for dynamic attributes
- Weak reference support
- GC support (`__traverse__`, `__clear__`)
- Frozen classes (`__frozen__`)
- Class inheritance (`__base__`)
- Docstrings for classes, methods, and properties
- Auto-generated `__slots__` from struct fields
- Cross-compilation support for 6 platforms (Linux/macOS/Windows x x86_64/aarch64)

### Notes
- This is an alpha release - API may change
- No abi3 (stable ABI) support yet
- No async/await support yet
