# Changelog

All notable changes to PyOZ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
