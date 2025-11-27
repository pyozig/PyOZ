# pyoz build

Build your PyOZ module into a Python wheel package.

## Usage

```bash
pyoz build [options]
```

## Options

| Option | Description |
|--------|-------------|
| `-d, --debug` | Build in debug mode (default) |
| `-r, --release` | Build in release mode (optimized) |
| `--stubs` | Generate `.pyi` type stub file (default) |
| `--no-stubs` | Skip type stub generation |
| `-h, --help` | Show help message |

## Build Modes

| Mode | Use Case |
|------|----------|
| Debug (default) | Fast compilation, debug symbols, safety checks - best for development |
| Release | Optimized, smaller binary - best for distribution |

## Output

```
dist/
└── mymodule-0.1.0-cp311-cp311-linux_x86_64.whl
```

---

# pyoz develop

Build and install the module in development mode for iterative development.

## Usage

```bash
pyoz develop
```

Builds the module and installs it in your Python environment. After making changes to `src/lib.zig`, run `pyoz develop` again to rebuild.

---

# pyoz publish

Publish wheel packages to PyPI.

## Usage

```bash
pyoz publish [options]
```

## Options

| Option | Description |
|--------|-------------|
| `-t, --test` | Upload to TestPyPI instead of PyPI |
| `-h, --help` | Show help message |

## Authentication

Set your API token as an environment variable:

| Variable | Description |
|----------|-------------|
| `PYPI_TOKEN` | API token for PyPI |
| `TEST_PYPI_TOKEN` | API token for TestPyPI |

Generate tokens at [pypi.org](https://pypi.org/manage/account/token/) or [test.pypi.org](https://test.pypi.org/manage/account/token/).

## Typical Workflow

```bash
# 1. Build release wheel
pyoz build --release

# 2. Test on TestPyPI first (optional)
export TEST_PYPI_TOKEN="pypi-..."
pyoz publish --test

# 3. Publish to PyPI
export PYPI_TOKEN="pypi-..."
pyoz publish
```
