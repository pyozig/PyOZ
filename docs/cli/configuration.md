# Configuration

PyOZ projects use standard Zig and Python configuration files.

## Project Structure

```
myproject/
├── src/
│   └── lib.zig          # Main module source
├── build.zig            # Zig build configuration
├── build.zig.zon        # Zig package manifest
└── pyproject.toml       # Python package configuration
```

## build.zig.zon

Zig package manifest defining project metadata and dependencies:

```zig
.{
    .name = "myproject",
    .version = "0.1.0",
    .dependencies = .{
        .PyOZ = .{
            .url = "https://github.com/pyozig/PyOZ/archive/refs/tags/v0.13.10.tar.gz",
            .hash = "1220abc123...",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

For local development, use a path dependency:

```zig
.PyOZ = .{ .path = "../PyOZ" },
```

## pyproject.toml

Python package metadata:

```toml
[project]
name = "myproject"
version = "0.1.0"
description = "My PyOZ module"
requires-python = ">=3.10"

[build-system]
requires = ["pyoz"]
build-backend = "pyoz.backend"
```

### PyOZ Settings

The `[tool.pyoz]` section configures the build:

```toml
[tool.pyoz]
# Path to your Zig source file (required)
module-path = "src/lib.zig"

# Native module name (defaults to project name from [project].name)
# Use underscore prefix for package layouts to avoid name collision
# module-name = "_myproject"

# Pure Python packages to include in the wheel
# py-packages = ["mypackage"]

# File extensions to include from py-packages (default: .py only)
# include-ext = ["py", "zig"]

# Optimization level for release builds
# optimize = "ReleaseFast"

# Strip debug symbols in release builds
# strip = true

# Enable ABI3 (Stable ABI) for cross-version compatibility (cp310-abi3 wheels;
# not available with free-threaded interpreters)
# abi3 = true

# Oldest glibc Linux wheels may require, as a manylinux tag (default:
# manylinux_2_17, i.e. glibc 2.17). "linux_x86_64" builds a native,
# non-portable wheel instead (PyPI rejects those).
# linux-platform-tag = "manylinux_2_28_x86_64"
```

### Package Layout with `module-name`

For projects that combine a native extension with a Python package (created with `pyoz init --package`), use `module-name` to give the `.so`/`.pyd` a different name from the project:

```toml
[tool.pyoz]
module-path = "src/lib.zig"
module-name = "_myproject"
py-packages = ["myproject"]
```

The `.so` is placed **inside** the package directory in the wheel, so `__init__.py` can use a relative import:

```python
# myproject/__init__.py
from ._myproject import *
```

### Python src-layout

`py-packages` supports both flat layout and [src-layout](https://packaging.python.org/en/latest/discussions/src-layout-vs-flat-layout/) (PEP 517). PyOZ automatically detects which layout is used by checking `src/<pkg>/` first, then falling back to `<pkg>/`.

**Flat layout:**

```
myproject/
├── src/
│   └── lib.zig
├── myproject/
│   └── __init__.py
├── build.zig
├── build.zig.zon
└── pyproject.toml
```

**Src-layout:**

```
myproject/
├── src/
│   └── myproject/
│       ├── __init__.py
│       └── root.zig
├── build.zig
├── build.zig.zon
└── pyproject.toml
```

Both layouts use the same `pyproject.toml` configuration:

```toml
[tool.pyoz]
module-path = "src/myproject/root.zig"
module-name = "_myproject"
py-packages = ["myproject"]
```

### Including Non-Python Files

By default, only `.py` files from `py-packages` are included in the wheel. Use `include-ext` to include additional file types:

```toml
[tool.pyoz]
py-packages = ["myproject"]

# Include .py and .zig files
include-ext = ["py", "zig"]

# Include all files
# include-ext = ["*"]
```

### Mixed Zig/Python Packages

To include pure Python utility packages alongside your Zig extension:

```toml
[tool.pyoz]
module-path = "src/lib.zig"
py-packages = ["myutils"]
```

```
myproject/
├── src/
│   └── lib.zig          # Zig extension module
├── myutils/
│   ├── __init__.py      # Python package
│   ├── helpers.py
│   └── config.py
├── build.zig
├── build.zig.zon
└── pyproject.toml
```

All `.py` files under listed packages are included in the wheel and symlinked during `pyoz develop`.

## Module Name Consistency

The module name must match in three places:

| File | Setting |
|------|---------|
| `build.zig` | `.name = "myproject"` |
| `src/lib.zig` | `.name = "myproject"` |
| `pyproject.toml` | `name = "myproject"` |

## Version Management

Update version in both:
- `build.zig.zon` - `.version = "x.y.z"`
- `pyproject.toml` - `version = "x.y.z"`

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PYPI_TOKEN` | PyPI API token for publishing |
| `TEST_PYPI_TOKEN` | TestPyPI API token |

## Python Version Support

PyOZ supports Python 3.10 through 3.14. Specify minimum version in pyproject.toml:

```toml
requires-python = ">=3.10"
```

## Next Steps

- [pyoz init](init.md) - Create a new project
- [pyoz build](build.md) - Build your module
