# NumPy Integration

PyOZ provides zero-copy access to NumPy arrays and other buffer-protocol objects through `BufferView` and `BufferViewMut`.

## BufferView Types

| Type | Description |
|------|-------------|
| `pyoz.BufferView(T)` | Read-only access to array data |
| `pyoz.BufferViewMut(T)` | Mutable access (can modify in-place) |

## Basic Usage

**Read-only access:**
```zig
fn array_sum(arr: pyoz.BufferView(f64)) f64 {
    var total: f64 = 0;
    for (arr.data) |v| total += v;
    return total;
}
```

**Mutable access:**
```zig
fn scale_array(arr: pyoz.BufferViewMut(f64), factor: f64) void {
    for (arr.data) |*v| v.* *= factor;
}
```

```python
import numpy as np
arr = np.array([1.0, 2.0, 3.0])
print(array_sum(arr))   # 6.0
scale_array(arr, 2.0)
print(arr)              # [2. 4. 6.]
```

## Supported Element Types

| Zig Type | NumPy dtype |
|----------|-------------|
| `f32`, `f64` | `float32`, `float64` |
| `i8`, `i16`, `i32`, `i64` | `int8`, `int16`, `int32`, `int64` |
| `u8`, `u16`, `u32`, `u64` | `uint8`, `uint16`, `uint32`, `uint64` |
| `pyoz.Complex` | `complex128` |
| `pyoz.Complex32` | `complex64` |

## BufferView Methods

| Method | Description |
|--------|-------------|
| `.data` | Slice of elements (iterate with `for`) |
| `.len()` | Total number of elements |
| `.rows()` | Number of rows (first dimension) |
| `.cols()` | Number of columns (second dimension) |
| `.isEmpty()` | Check if array is empty |
| `.fill(value)` | Fill with value (BufferViewMut only) |

## Complex Numbers

```zig
fn complex_sum(arr: pyoz.BufferView(pyoz.Complex)) pyoz.Complex {
    var result = pyoz.Complex.init(0, 0);
    for (arr.data) |v| result = result.add(v);
    return result;
}
```

Complex type methods: `.add()`, `.sub()`, `.mul()`, `.div()`, `.conjugate()`, `.magnitude()`

## Error Handling

Return `?bool` to raise exceptions:

```zig
fn element_multiply(a: pyoz.BufferViewMut(f64), b: pyoz.BufferView(f64)) ?bool {
    if (a.len() != b.len()) {
        _ = pyoz.raiseValueError("Arrays must have same length");
        return null;
    }
    for (a.data, b.data) |*x, y| x.* *= y;
    return true;
}
```

## Exposing Buffer Protocol

Make your class compatible with NumPy by implementing `__buffer__`:

```zig
const IntArray = struct {
    data: [8]i64,
    len: usize,

    var buffer_shape: [1]pyoz.Py_ssize_t = .{0};
    var buffer_format: [2:0]u8 = .{ 'q', 0 };  // 'q' = int64

    pub fn __buffer__(self: *IntArray) pyoz.BufferInfo {
        buffer_shape[0] = @intCast(self.len);
        return .{
            .ptr = @ptrCast(&self.data),
            .len = self.len * @sizeOf(i64),
            .readonly = false,
            .format = &buffer_format,
            .itemsize = @sizeOf(i64),
            .ndim = 1,
            .shape = &buffer_shape,
            .strides = null,
        };
    }
};
```

```python
arr = IntArray.from_values(1, 2, 3)
np_view = np.asarray(arr)  # Zero-copy view
```

## Performance Tips

1. **Zero-copy**: BufferView provides direct memory access - no copying
2. **Release GIL**: For long computations, release the GIL (see [GIL Management](gil.md))
3. **Contiguous arrays**: Works best with C-contiguous arrays

## Next Steps

- [GIL](gil.md) - Threading and GIL management
- [Types](types.md) - Type conversion reference
