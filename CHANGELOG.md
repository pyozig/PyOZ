# Changelog

All notable changes to PyOZ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.1] - Unreleased

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
