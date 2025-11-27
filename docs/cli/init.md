# pyoz init

Initialize a new PyOZ project with the recommended directory structure and configuration.

## Usage

```bash
pyoz init [options] [name]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `name` | Project name (required unless using `--path`) |

## Options

| Option | Description |
|--------|-------------|
| `-p, --path` | Initialize in current directory instead of creating new one |
| `-l, --local <path>` | Use local PyOZ path instead of fetching from URL |
| `-h, --help` | Show help message |

## Examples

```bash
# Create new project directory
pyoz init myproject

# Initialize in current directory
pyoz init --path

# Use local PyOZ for development
pyoz init --local /path/to/PyOZ myproject
```

## Generated Structure

```
myproject/
├── src/
│   └── lib.zig          # Main module source
├── build.zig            # Zig build configuration
├── build.zig.zon        # Zig package manifest
└── pyproject.toml       # Python package configuration
```

The generated `src/lib.zig` contains a minimal working module with an example `add` function. Edit this file to add your functions and classes.

## Next Steps

After initialization:

```bash
cd myproject
pyoz develop                                        # Build and install
python -c "import myproject; print(myproject.add(1, 2))"  # Test
```

See [pyoz build](build.md) for build options and [Configuration](configuration.md) for project settings.
