const std = @import("std");
const builtin = @import("builtin");

/// Python configuration detected from the system
const PythonConfig = struct {
    version: []const u8,
    version_major: u8,
    version_minor: u8,
    include_dir: []const u8,
    lib_dir: ?[]const u8,
    lib_name: []const u8,
};

fn getPythonCommand() []const u8 {
    return if (builtin.os.tag == .windows) "python" else "python3";
}

fn detectPython(b: *std.Build) ?PythonConfig {
    var out_code: u8 = 0;
    const python_cmd = getPythonCommand();

    const version_result = b.runAllowFail(
        &.{ python_cmd, "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" },
        &out_code,
        .Inherit,
    ) catch return null;
    if (out_code != 0) return null;
    const version = std.mem.trim(u8, version_result, &std.ascii.whitespace);

    var version_major: u8 = 3;
    var version_minor: u8 = 0;
    if (std.mem.indexOf(u8, version, ".")) |dot| {
        version_major = std.fmt.parseInt(u8, version[0..dot], 10) catch 3;
        version_minor = std.fmt.parseInt(u8, version[dot + 1 ..], 10) catch 0;
    }

    const include_result = b.runAllowFail(
        &.{ python_cmd, "-c", "import sysconfig; print(sysconfig.get_path('include'))" },
        &out_code,
        .Inherit,
    ) catch return null;
    if (out_code != 0) return null;
    const include_dir = std.mem.trim(u8, include_result, &std.ascii.whitespace);
    if (include_dir.len == 0) return null;

    var lib_dir: ?[]const u8 = null;
    if (b.runAllowFail(&.{
        python_cmd,
        "-c",
        "import sysconfig,sys,os;d=sysconfig.get_config_var('LIBDIR');print(d if d else os.path.join(sys.prefix,'libs' if sys.platform=='win32' else 'lib'))",
    }, &out_code, .Inherit)) |libdir_result| {
        if (out_code == 0) {
            const libdir_trimmed = std.mem.trim(u8, libdir_result, &std.ascii.whitespace);
            if (libdir_trimmed.len > 0) {
                lib_dir = libdir_trimmed;
            }
        }
    } else |_| {}

    const lib_name = if (builtin.os.tag == .windows)
        std.fmt.allocPrint(b.allocator, "python{d}{d}", .{ version_major, version_minor }) catch return null
    else
        std.fmt.allocPrint(b.allocator, "python{s}", .{version}) catch return null;

    return PythonConfig{
        .version = version,
        .version_major = version_major,
        .version_minor = version_minor,
        .include_dir = include_dir,
        .lib_dir = lib_dir,
        .lib_name = lib_name,
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional: path to downloaded CPython headers for cross-compilation.
    // When set, these headers are used instead of the host Python's headers.
    // Expected layout:
    //   <dir>/*.h, <dir>/cpython/*.h  — platform-independent CPython headers
    //   <dir>/unix/pyconfig.h         — pyconfig.h for Linux/macOS targets
    //   <dir>/windows/pyconfig.h      — pyconfig.h for Windows targets (from PC/pyconfig.h)
    const python_headers_dir = b.option([]const u8, "python-headers-dir", "Path to downloaded CPython headers for cross-compilation");

    const python_config = detectPython(b);

    if (python_config == null and python_headers_dir == null) {
        std.log.warn("Python not detected! Make sure python3 is in PATH or pass -Dpython-headers-dir.", .{});
    }

    // Build the list of Python include dirs for cross-compilation.
    // These are passed to the PyOZ dependency so its @cImport("Python.h") finds
    // the correct headers instead of the host Python's.
    // Note: build_wheels.py stages the correct pyconfig.h (unix or windows)
    // directly into the headers directory before each build.
    const target_os = target.result.os.tag;
    const cross_include_dirs: ?[]const []const u8 = if (python_headers_dir) |headers_dir|
        b.allocator.dupe([]const u8, &.{headers_dir}) catch @panic("OOM")
    else
        null;

    // Get the PyOZ dependency (points to ../)
    // Enable abi3 (Python Stable ABI) so the extension is compatible with Python 3.8+
    // and can be cross-compiled without target-specific Python libraries.
    const pyoz_dep = b.dependency("PyOZ", .{
        .target = target,
        .optimize = optimize,
        .abi3 = true,
        .@"python-include-dirs" = cross_include_dirs,
    });

    const pyoz_mod = pyoz_dep.module("PyOZ");

    // Reuse the version module exposed by the PyOZ dependency
    const version_mod = pyoz_dep.module("version");

    // Create a virtual source directory containing lib.zig alongside all CLI files.
    // This lets lib.zig do @import("project.zig") etc., and CLI files can cross-import
    // each other since they're all in the same module tree.
    const cli_path: std.Build.LazyPath = b.path("../src/cli");
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(b.path("src/lib.zig"), "lib.zig");
    const cli_files = [_][]const u8{
        "builder.zig",
        "commands.zig",
        "project.zig",
        "pypi.zig",
        "symreader.zig",
        "toml.zig",
        "wheel.zig",
        "zip.zig",
    };
    for (cli_files) |name| {
        _ = wf.addCopyFile(cli_path.path(b, name), name);
    }

    // Build the shared library
    const lib = b.addLibrary(.{
        .name = "_pyoz",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = wf.getDirectory().path(b, "lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "PyOZ", .module = pyoz_mod },
                .{ .name = "version", .module = version_mod },
            },
        }),
    });

    // Add miniz C source (needed by zip.zig which is imported by wheel.zig)
    lib.addCSourceFile(.{
        .file = b.path("../src/miniz/miniz.c"),
        .flags = &.{"-DMINIZ_NO_STDIO"},
    });
    lib.addIncludePath(b.path("../src/miniz"));

    // Link Python headers (needed for compilation).
    // On Linux/macOS, do NOT link against libpython — the symbols are provided
    // by the Python interpreter at runtime. Linking against a specific version
    // would hardcode it into the .so, breaking abi3 cross-version compatibility.
    // On Windows, link against python3.dll (the version-agnostic stable ABI DLL)
    // instead of python3XX.dll, so the extension works across all Python 3.x.
    if (python_headers_dir) |headers_dir| {
        // Cross-compilation: use downloaded CPython headers.
        // build_wheels.py stages the correct pyconfig.h into this directory.
        lib.addIncludePath(.{ .cwd_relative = headers_dir });
        lib.root_module.addIncludePath(.{ .cwd_relative = headers_dir });

        if (target_os == .windows) {
            // Generate python3.lib import library from python3.def using zig dlltool.
            // The .def file is generated by build_wheels.py from CPython's stable_abi.toml.
            const def_path = std.fmt.allocPrint(b.allocator, "{s}/windows/python3.def", .{headers_dir}) catch @panic("OOM");
            const dlltool = b.addSystemCommand(&.{ "zig", "dlltool" });
            dlltool.addArgs(&.{ "-d", def_path });
            dlltool.addArgs(&.{"-l"});
            const python3_lib = dlltool.addOutputFileArg("python3.lib");
            dlltool.addArgs(&.{
                "-m",
                switch (target.result.cpu.arch) {
                    .x86 => "i386",
                    .x86_64 => "i386:x86-64",
                    .aarch64 => "arm64",
                    .arm => "arm",
                    else => "i386:x86-64",
                },
            });
            lib.addObjectFile(python3_lib);
        }
    } else if (python_config) |python| {
        // Native build: use host Python's headers
        lib.addIncludePath(.{ .cwd_relative = python.include_dir });
        lib.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (target_os == .windows) {
            if (python.lib_dir) |lib_dir| {
                lib.addLibraryPath(.{ .cwd_relative = lib_dir });
            }
            // Link against python3.dll (stable ABI), not python3XX.dll
            lib.linkSystemLibrary("python3");
        }
    }

    // On macOS, allow undefined symbols so Python C API symbols are resolved
    // at load time by the interpreter (same behavior as Linux). Without this,
    // the macOS linker errors out on unresolved _Py* symbols during cross-compilation.
    if (target_os == .macos) {
        lib.linker_allow_shlib_undefined = true;
    }

    lib.linkLibC();

    // Install as .so (Unix) or .pyd (Windows)
    const dest_name = if (target_os == .windows) "_pyoz.pyd" else "_pyoz.so";
    const install = b.addInstallArtifact(lib, .{
        .dest_sub_path = dest_name,
    });

    b.getInstallStep().dependOn(&install.step);
}
