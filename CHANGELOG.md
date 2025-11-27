# Changelog

All notable changes to PyOZ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
