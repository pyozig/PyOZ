# Changelog

All notable changes to PyOZ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
