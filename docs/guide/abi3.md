# ABI3 (Stable ABI)

Python's Stable ABI (ABI3) allows building extensions that work across multiple Python versions without recompilation. A single wheel built for Python 3.10 works on 3.11, 3.12, 3.13, 3.14 and future versions.

## Enabling ABI3

Enable via build flag (`zig build -Dabi3=true`) or in pyproject.toml:

```toml
[tool.pyoz]
abi3 = true
```

When enabled, PyOZ uses only stable ABI functions (`Py_LIMITED_API = 0x030A0000`) and generates wheels with `cp310-abi3-platform` tags.

## What Works in ABI3

**All basic types** work fully: integers (including i128/u128), floats, booleans, strings, bytes, complex numbers, datetime types, decimals, and paths.

**Collections** work as consumers via View types (ListView, DictView, SetView, IteratorView) and as producers via Iterator and LazyIterator. BufferView provides read-only NumPy array access.

**Classes** are created via `PyType_FromSpec`, the stable API for type creation. All standard class features work:

- Instance, static, and class methods
- Computed properties (both `get_X`/`set_X` pattern and `pyoz.property()` API)
- Class attributes via `classattr_` prefix
- Frozen/immutable classes with `__frozen__`
- Docstrings for classes, methods, and fields

**Magic methods** have full support across all protocols:

- Arithmetic: `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`, `__mod__`, `__pow__`, `__matmul__`
- Unary: `__neg__`, `__pos__`, `__abs__`, `__invert__`
- Comparison: `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`
- Bitwise: `__and__`, `__or__`, `__xor__`, `__lshift__`, `__rshift__`
- In-place operators: `__iadd__`, `__isub__`, `__imul__`, `__iand__`, `__ior__`, etc.
- Reflected operators: `__radd__`, `__rsub__`, `__rmul__`, `__rmatmul__`
- Type coercion: `__int__`, `__float__`, `__bool__`, `__index__`, `__complex__`
- String representation: `__repr__`, `__str__`, `__hash__`
- Sequences: `__len__`, `__getitem__`, `__setitem__`, `__delitem__`, `__contains__`
- Iterators: `__iter__`, `__next__`, `__reversed__`
- Callable: `__call__`
- Context managers: `__enter__`, `__exit__`
- Descriptors: `__get__`, `__set__`, `__delete__`
- Dynamic attributes: `__getattr__`, `__setattr__`, `__delattr__`

**GIL management** functions (`PyEval_SaveThread`, `PyEval_RestoreThread`) are part of the stable ABI, so `releaseGIL()` and `acquireGIL()` work normally.

**Enums** work for both IntEnum (numeric values) and StrEnum (string values).

**Custom exceptions** work with full inheritance support.

**Lazy iterators** allow creating memory-efficient generators that yield values on demand.

## Limitations

The following features are **not available** in ABI3 mode:

**BufferViewMut** - Mutable buffer access requires internal buffer protocol structures not exposed in the stable ABI. Use read-only `BufferView` instead, or avoid ABI3 if you need in-place NumPy modifications.

**Buffer producer (`__buffer__`)** - Exporting buffers for NumPy consumption requires `Py_buffer` structure access which isn't stable.

**`__base__` inheritance** - Extending Python built-in types (list, dict) requires type flags not in the limited API.

**`__dict__` and `__weakref__`** - Dynamic attribute storage and weak reference support require type flag manipulation.

**Submodules** - Creating module hierarchies requires `tp_dict` access on module objects, which is opaque in ABI3.

The **GC protocol** (`__traverse__`, `__clear__`) is available in ABI3 mode: the type flags, slots and functions it needs are part of the Limited API.

## Wheel Distribution

ABI3 wheels use tags like `cp310-abi3-manylinux_2_17_x86_64` indicating compatibility with Python 3.10 and all later versions. This means:

- One wheel per platform instead of one per Python version
- Automatic compatibility with future Python releases
- Simpler CI/CD pipelines with smaller build matrices

## When to Use ABI3

**Use ABI3** for PyPI distribution, reducing build complexity, and future-proofing. Most extensions don't need mutable buffers or type inheritance.

**Avoid ABI3** if you need `BufferViewMut` for in-place NumPy operations, need to extend built-in types, require submodules, or need maximum performance (non-ABI3 allows some optimized code paths).

## Example

See `examples/example_abi3.zig` for a complete module demonstrating all ABI3-compatible features. Build with:

```bash
zig build example_abi3 -Dabi3=true -Doptimize=ReleaseFast
```

## Next Steps

- [Classes](classes.md) - Full class documentation
- [Types](types.md) - Type conversion reference
- [GIL](gil.md) - GIL management details
