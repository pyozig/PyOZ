# Upgrading to 0.13

PyOZ 0.13 moves to **Zig 0.16** and **Python 3.10+**, and changes
`pyoz.fmt`. Most projects need three small edits: the version pins, a few lines
in `build.zig`, and any `pyoz.fmt` return types. Everything else is additive.

!!! summary "Checklist"
    1. Install **Zig 0.16.0** and use **Python 3.10 or newer**.
    2. Update the PyOZ dependency in `build.zig.zon` and add `minimum_zig_version`.
    3. Apply the [`build.zig` changes](#buildzig): `linkLibC`, `addLibraryPath`,
       `linkSystemLibrary`, the `.pyd`/`.so` extension check, and one line for
       macOS.
    4. Set `requires-python = ">=3.10"` in `pyproject.toml`.
    5. If a function returns `pyoz.fmt(...)`, change its return type to
       [`pyoz.Formatted`](#pyozfmt-returns-a-lazy-value).
    6. Rebuild: `pyoz build`, then `pyoz test`.

## Requirements

| | 0.12 | 0.13 |
|---|---|---|
| Zig | 0.15.x | **0.16.0** |
| Python | 3.8 – 3.13 | **3.10 – 3.14**, including free-threaded 3.14t |
| ABI3 wheels | `cp38-abi3` | **`cp310-abi3`** |

## build.zig.zon

Point the dependency at the latest 0.13 release and refresh its hash with `zig fetch`,
which rewrites `build.zig.zon` for you:

```bash
zig fetch --save=PyOZ https://github.com/pyozig/PyOZ/archive/refs/tags/v0.13.6.tar.gz
```

Then declare the minimum Zig version, so older compilers fail with a clear
message instead of confusing errors:

```zig
.{
    .name = .myproject,
    .version = "0.1.0",
    .fingerprint = 0x...,
    .minimum_zig_version = "0.16.0", // add this
    .dependencies = .{ .PyOZ = .{ ... } },
    ...
}
```

If you use a local checkout (`.path = "..."`), just update that checkout.

## build.zig

Zig 0.16 moved libc and library linking from the compile step to the module.
These are the lines `pyoz init` generated in 0.12 that need to change.

**Link libc on the module, not the library:**

```zig
// Before (0.12)
const user_lib_mod = b.createModule(.{
    .root_source_file = b.path("src/lib.zig"),
    .target = target,
    .optimize = optimize,
    .strip = strip,
    .imports = &.{ .{ .name = "PyOZ", .module = pyoz_dep.module("PyOZ") } },
});
// ...
lib.linkLibC();
```

```zig
// After (0.13)
const user_lib_mod = b.createModule(.{
    .root_source_file = b.path("src/lib.zig"),
    .target = target,
    .optimize = optimize,
    .strip = strip,
    .link_libc = true, // replaces lib.linkLibC()
    .imports = &.{ .{ .name = "PyOZ", .module = pyoz_dep.module("PyOZ") } },
});
```

**Library path and system library also go on the module; `linkSystemLibrary`
takes an options argument:**

```zig
// Before (0.12)
lib.addLibraryPath(.{ .cwd_relative = lib_dir });
lib.linkSystemLibrary(lib_name);
```

```zig
// After (0.13)
user_lib_mod.addLibraryPath(.{ .cwd_relative = lib_dir });
user_lib_mod.linkSystemLibrary(lib_name, .{ .use_pkg_config = .no }); // skip host pkg-config
```

The same applies to anything else you added on `lib`: `addIncludePath`,
`addObjectFile`, `addCSourceFile` and friends are now called on the module
(`user_lib_mod`) instead.

**Pick the extension from the target, not the host.** The 0.12 template used
`builtin.os.tag`, which is the OS running the build, so cross-compiling to
Windows produced `name.so`. With the target's OS, the result is runtime-known,
so `++` becomes `b.fmt`:

```zig
// Before (0.12)
const builtin = @import("builtin");
// ...
const ext = if (builtin.os.tag == .windows) ".pyd" else ".so";
const install = b.addInstallArtifact(lib, .{
    .dest_sub_path = "myproject" ++ ext,
});
```

```zig
// After (0.13)
const ext = if (target.result.os.tag == .windows) ".pyd" else ".so";
const install = b.addInstallArtifact(lib, .{
    .dest_sub_path = b.fmt("myproject{s}", .{ext}),
});
```

(`const builtin = @import("builtin");` can be removed if nothing else uses it.)

**Allow undefined symbols on macOS.** An extension gets the Python C API from
the interpreter that loads it, so the macOS linker must accept those symbols as
undefined (`-undefined dynamic_lookup`). The 0.12 template lacked this line;
without it macOS builds, native or cross-compiled, fail with
`undefined symbol: _PyErr_Occurred` and similar. Add it after `b.addLibrary`:

```zig
// After (0.13)
if (target.result.os.tag == .macos) lib.linker_allow_shlib_undefined = true;
```

!!! tip "Starting fresh"
    For heavily customized projects it can be quicker to run
    `pyoz init --path` in a scratch directory and copy your additions into the
    newly generated `build.zig`.

## pyproject.toml

```toml
[project]
requires-python = ">=3.10"
```

If you set `abi3 = true`, wheels are now tagged `cp310-abi3` and work on
Python 3.10 and every later version. ABI3 cannot target free-threaded Python;
`pyoz build` reports this if you try.

## pyoz.fmt returns a lazy value

`pyoz.fmt` no longer returns a `[*:0]const u8`. It returns a
`pyoz.Formatted` value that is rendered by whoever consumes it. The old version
returned a pointer into a stack buffer, which was invalid once the function
that called `pyoz.fmt` returned (for example from `__repr__`), and it truncated
messages over 4 KB.

**Passing it to a raise function needs no change:**

```zig
return pyoz.raiseValueError(pyoz.fmt("value {d} too large", .{v})); // still works
```

**Returning it needs a new return type.** The compiler will point at each place:

```zig
// Before (0.12)
pub fn __repr__(self: *const Vec2) [*:0]const u8 {
    return pyoz.fmt("Vec2({d:.2}, {d:.2})", .{ self.x, self.y });
}
```

```zig
// After (0.13): the format string lives in the return type
pub fn __repr__(self: *const Vec2) pyoz.Formatted("Vec2({d:.2}, {d:.2})", struct { f64, f64 }) {
    return .{ .args = .{ self.x, self.y } };
}
```

The tuple type lists the argument types in order. If you need a
`[*:0]const u8` for your own C calls, format into your own buffer with
`std.fmt.bufPrintZ`.

## Behavior changes (no code changes needed)

- **`pyoz develop`** now installs a standard PEP 660 editable wheel with pip
  instead of symlinking into site-packages. Run `pip uninstall <name>` once
  to remove an old symlink-based install if `pip list` doesn't show it, then
  delete any leftover `<module>.so` symlink in site-packages. `pip install -e .`
  now works too.
- **`pip install .`** works with `build-backend = "pyoz.backend"` (it failed with
  `ModuleNotFoundError: No module named '_pyoz'` in 0.12).
- **`pyoz publish`** only uploads wheels for the current project version.
- **Wheel names are normalized** (`My-Pkg` → `my_pkg-...whl`) and RECORD files
  carry SHA-256 hashes, as the wheel spec requires.
- **`__freelist__` is ignored on free-threaded Python.** Regular builds are
  unchanged.
- **`pyoz build` makes portable wheels.** They are built for a baseline CPU,
  glibc 2.17 on Linux and macOS 13.0, and tagged from the built binary:
  `manylinux_2_17_x86_64` instead of `linux_x86_64`, which PyPI rejected, and
  `macosx_13_0_arm64` instead of the build machine's version (0.12 produced
  tags like `macosx_14_5_arm64`, which pip never installs). `--native` builds
  for the exact machine as before. `linux-platform-tag` now selects the glibc
  version (`manylinux_2_28_x86_64` builds against glibc 2.28); a `linux_*`
  value means a native build. See [pyoz build](cli/build.md#portable-wheels).
- **Wheel metadata is complete.** Classifiers, license (SPDX expressions and
  license files), readme, URLs, authors, keywords, dependencies, extras and
  entry points from `[project]` now reach the wheel and PyPI; 0.12 dropped
  everything but the name, version, summary and `README.md`. Dependencies
  declared in `pyproject.toml` are now installed with the wheel.
- **`abi3 = true` now builds a real Stable ABI module.** Before 0.13.3 it only
  set the wheel tag: the module was built for the Python that ran `pyoz build`,
  so an `abi3` wheel could crash on other versions. `pyoz build` fixes this for
  existing projects without edits; rebuild and republish any `abi3` wheels made
  with an earlier PyOZ. To use `zig build -Dabi3=true` directly, add the option
  to `build.zig` and pass it to the dependency:

    ```zig
    const abi3 = b.option(bool, "abi3", "Build for the Python Stable ABI (abi3)") orelse false;
    const pyoz_dep = b.dependency("PyOZ", .{ .target = target, .optimize = optimize, .abi3 = abi3 });
    ```

- **Windows non-ABI3 builds link `python3XY.lib`** instead of `python3.lib`,
  which only exports the Stable ABI.
- **Fixed-size array parameters** (`[3]i64`) accept a tuple as well as a list.
  A wrong length now raises `ValueError: expected 3 items, got 2` (it was a
  `TypeError` whose message was just the error name).
- **`pip install .` from source needs no Zig installed:** without a Zig 0.16
  on `PATH`, `pyoz.backend` gets one from the `ziglang` package.

## New in 0.13 (optional)

- [Async](guide/async.md): `pyoz.asyncFn` and `pyoz.asyncMethod`, built on
  `std.Io`, with cancellation.
- [Free-threading](guide/free-threading.md): `.gil_used = false` to run without
  the GIL on 3.14t; class instances are locked automatically.
- `pyoz.func(...).withParams("a, b")`: real parameter names in stubs and
  `help()`.
- [Cross-building wheels](cli/build.md#other-platforms-and-python-versions):
  `pyoz build --target all --python 3.13` builds every platform from one
  machine.
- Async protocols on classes: `__aiter__`, `__anext__`, `__await__`,
  `__aenter__`, `__aexit__` (see [Async](guide/async.md#async-protocols)).

See the [CHANGELOG](https://github.com/pyozig/PyOZ/blob/main/CHANGELOG.md) for
the complete list.
