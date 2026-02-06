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

    const python_config = detectPython(b);

    if (python_config == null) {
        std.log.warn("Python not detected! Make sure python3 is in PATH.", .{});
    }

    // Get the PyOZ dependency (points to ../)
    // Enable abi3 (Python Stable ABI) so the extension is compatible with Python 3.8+
    // and can be cross-compiled without target-specific Python libraries.
    const pyoz_dep = b.dependency("PyOZ", .{
        .target = target,
        .optimize = optimize,
        .abi3 = true,
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

    // Link Python
    if (python_config) |python| {
        lib.addIncludePath(.{ .cwd_relative = python.include_dir });
        lib.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (python.lib_dir) |lib_dir| {
            lib.addLibraryPath(.{ .cwd_relative = lib_dir });
        }
        lib.linkSystemLibrary(python.lib_name);
    }
    lib.linkLibC();

    // Install as .so (Unix) or .pyd (Windows)
    const ext = if (builtin.os.tag == .windows) ".pyd" else ".so";
    const install = b.addInstallArtifact(lib, .{
        .dest_sub_path = "_pyoz" ++ ext,
    });

    b.getInstallStep().dependOn(&install.step);
}
