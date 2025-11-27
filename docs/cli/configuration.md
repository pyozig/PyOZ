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
            .url = "https://github.com/dzonerzy/PyOZ/archive/refs/tags/v0.4.0.tar.gz",
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
