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
            .url = "https://github.com/pyozig/PyOZ/archive/refs/tags/v0.10.0.tar.gz",
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
requires-python = ">=3.8"

[build-system]
requires = ["setuptools", "wheel"]
build-backend = "setuptools.build_meta"
```

### PyOZ Settings

The `[tool.pyoz]` section configures the build:

```toml
[tool.pyoz]
# Path to your Zig source file (required)
module-path = "src/lib.zig"

# Optimization level for release builds
# optimize = "ReleaseFast"

# Strip debug symbols in release builds
# strip = true

# Linux platform tag for wheel builds
# linux-platform-tag = "manylinux_2_17_x86_64"

# Pure Python packages to include in the wheel
# py-packages = ["mypackage", "mypackage_utils"]
```

### Mixed Zig/Python Packages

To include pure Python packages alongside your Zig extension, use `py-packages`:

```toml
[tool.pyoz]
module-path = "src/lib.zig"
py-packages = ["myutils"]
```

With this project structure:

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
| `src/lib.zig` | `.name = "myproject"` and `PyInit_myproject` |
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

PyOZ supports Python 3.8 through 3.13. Specify minimum version in pyproject.toml:

```toml
requires-python = ">=3.8"
```

## Next Steps

- [pyoz init](init.md) - Create a new project
- [pyoz build](build.md) - Build your module
