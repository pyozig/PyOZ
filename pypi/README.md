# PyOZ

Python extension modules in Zig, made easy.

Write normal Zig code and PyOZ handles all the Python integration automatically -- type conversions, class wrapping, protocol implementations, and more.

## Installation

```
pip install pyoz
```

## Quick Start

```
pyoz init mymodule
cd mymodule
pyoz build
```

Then from Python:

```python
import mymodule
```

## Commands

- `pyoz init <name>` -- Create a new PyOZ project
- `pyoz build` -- Build the extension module and create a wheel
- `pyoz develop` -- Build and install in development mode
- `pyoz publish` -- Publish wheels to PyPI

## Documentation

Full documentation is available at https://github.com/pyozig/PyOZ/tree/main/docs

## License

MIT
