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

/// Get the Python executable name for the current platform
fn getPythonCommand() []const u8 {
    return if (builtin.os.tag == .windows) "python" else "python3";
}

/// Detect Python configuration using sysconfig (cross-platform)
fn detectPython(b: *std.Build) ?PythonConfig {
    var out_code: u8 = 0;
    const python_cmd = getPythonCommand();

    // Try to get Python version
    const version_result = b.runAllowFail(
        &.{ python_cmd, "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" },
        &out_code,
        .Inherit,
    ) catch return null;
    if (out_code != 0) return null;
    const version = std.mem.trim(u8, version_result, &std.ascii.whitespace);

    // Parse version numbers
    var version_major: u8 = 3;
    var version_minor: u8 = 0;
    if (std.mem.indexOf(u8, version, ".")) |dot| {
        version_major = std.fmt.parseInt(u8, version[0..dot], 10) catch 3;
        version_minor = std.fmt.parseInt(u8, version[dot + 1 ..], 10) catch 0;
    }

    // Get include directory using sysconfig (cross-platform)
    const include_result = b.runAllowFail(
        &.{ python_cmd, "-c", "import sysconfig; print(sysconfig.get_path('include'))" },
        &out_code,
        .Inherit,
    ) catch return null;
    if (out_code != 0) return null;

    const include_dir = std.mem.trim(u8, include_result, &std.ascii.whitespace);
    if (include_dir.len == 0) return null;

    // Get library directory using sysconfig (cross-platform)
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

    // Construct library name based on platform
    const lib_name = if (builtin.os.tag == .windows)
        // Windows uses python<major><minor> (no dot), e.g., python313
        std.fmt.allocPrint(b.allocator, "python{d}{d}", .{ version_major, version_minor }) catch return null
    else
        // Unix uses python<major>.<minor>, e.g., python3.13
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

    // Sanitizer option
    const sanitize = b.option(bool, "sanitize", "Enable address sanitizer") orelse false;

    // ABI3 option - hardcoded to Python 3.8 minimum (see src/lib/python/types.zig)
    const abi3 = b.option(bool, "abi3", "Enable Python Stable ABI (Limited API) mode") orelse false;

    // Optional: override Python include paths (used by pypi/build.zig for cross-compilation)
    const python_include_dirs: ?[]const []const u8 = b.option([]const []const u8, "python-include-dirs", "Override Python include paths for cross-compilation");

    // Detect Python on the system
    const python_config = detectPython(b);

    if (python_config == null and python_include_dirs == null) {
        if (builtin.os.tag == .windows) {
            std.log.warn("Python not detected! Make sure python is in PATH.", .{});
        } else {
            std.log.warn("Python not detected! Make sure python3 is in PATH.", .{});
        }
    }

    // Create the version module - single source of truth for lib and CLI
    const version_mod = b.addModule("version", .{
        .root_source_file = b.path("src/version.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create ABI3 options - passed to PyOZ for compile-time ABI3 detection
    const abi3_options = b.addOptions();
    abi3_options.addOption(bool, "abi3", abi3);

    // Create the PyOZ module (library)
    const pyoz_mod = b.addModule("PyOZ", .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "version", .module = version_mod },
        },
    });

    // Add build options to PyOZ module (importable as "build_options")
    pyoz_mod.addOptions("build_options", abi3_options);

    // Add Python include path to the module
    if (python_include_dirs) |dirs| {
        // Cross-compilation: use explicitly provided include paths
        for (dirs) |dir| {
            pyoz_mod.addIncludePath(.{ .cwd_relative = dir });
        }
    } else if (python_config) |python| {
        pyoz_mod.addIncludePath(.{ .cwd_relative = python.include_dir });
    }

    // ========================================================================
    // Example Python Extension Module
    // ========================================================================

    const example_lib = b.addLibrary(.{
        .name = "example",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/example_module.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "PyOZ", .module = pyoz_mod },
            },
        }),
    });

    // Enable sanitizers if requested
    if (sanitize) {
        example_lib.root_module.sanitize_c = .full;
    }

    // Link against Python
    if (python_config) |python| {
        example_lib.addIncludePath(.{ .cwd_relative = python.include_dir });
        example_lib.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (python.lib_dir) |lib_dir| {
            example_lib.addLibraryPath(.{ .cwd_relative = lib_dir });
        }
        example_lib.linkSystemLibrary(python.lib_name);
    }
    example_lib.linkLibC();

    // Install as .so file (Unix) or .pyd file (Windows)
    const ext = if (builtin.os.tag == .windows) ".pyd" else ".so";
    const install_example = b.addInstallArtifact(example_lib, .{
        .dest_sub_path = "example" ++ ext,
    });

    const example_step = b.step("example", "Build the example Python module");
    example_step.dependOn(&install_example.step);

    // ========================================================================
    // ABI3 Example Python Extension Module
    // ========================================================================

    const example_abi3_lib = b.addLibrary(.{
        .name = "example_abi3",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/example_abi3.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "PyOZ", .module = pyoz_mod },
            },
        }),
    });

    // Enable sanitizers if requested
    if (sanitize) {
        example_abi3_lib.root_module.sanitize_c = .full;
    }

    // Link against Python
    if (python_config) |python| {
        example_abi3_lib.addIncludePath(.{ .cwd_relative = python.include_dir });
        example_abi3_lib.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (python.lib_dir) |lib_dir| {
            example_abi3_lib.addLibraryPath(.{ .cwd_relative = lib_dir });
        }
        example_abi3_lib.linkSystemLibrary(python.lib_name);
    }
    example_abi3_lib.linkLibC();

    // Install as .so file (Unix) or .pyd file (Windows)
    const install_example_abi3 = b.addInstallArtifact(example_abi3_lib, .{
        .dest_sub_path = "example_abi3" ++ ext,
    });

    const example_abi3_step = b.step("example_abi3", "Build the ABI3-compatible example Python module");
    example_abi3_step.dependOn(&install_example_abi3.step);

    // ========================================================================
    // Test Suite
    // ========================================================================

    // Generate test stub library source code for symreader tests
    // Includes both symbol-based and section-based stub embedding
    const test_stub_source =
        \\//! Test stub library for symreader tests
        \\const test_stubs_content = "# Test stub content\ndef hello(): ...\n";
        \\
        \\// Symbol-based exports (for non-stripped binaries)
        \\pub const __pyoz_stubs_ptr__: [*]const u8 = test_stubs_content.ptr;
        \\pub const __pyoz_stubs_len__: usize = test_stubs_content.len;
        \\comptime {
        \\    @export(&__pyoz_stubs_ptr__, .{ .name = "__pyoz_stubs_data__" });
        \\    @export(&__pyoz_stubs_len__, .{ .name = "__pyoz_stubs_len__" });
        \\}
        \\
        \\// Section-based embedding (survives stripping)
        \\// Format: "PYOZSTUB" magic (8 bytes) + length (8 bytes LE) + content
        \\const builtin = @import("builtin");
        \\const section_name = if (builtin.os.tag == .macos) "__DATA,__pyozstub" else ".pyozstub";
        \\pub const __pyoz_stubs_section__: [16 + test_stubs_content.len]u8 linksection(section_name) = blk: {
        \\    var data: [16 + test_stubs_content.len]u8 = undefined;
        \\    // 8-byte magic header
        \\    @memcpy(data[0..8], "PYOZSTUB");
        \\    // 8-byte little-endian length
        \\    const len = test_stubs_content.len;
        \\    data[8] = @truncate(len);
        \\    data[9] = @truncate(len >> 8);
        \\    data[10] = @truncate(len >> 16);
        \\    data[11] = @truncate(len >> 24);
        \\    data[12] = @truncate(len >> 32);
        \\    data[13] = @truncate(len >> 40);
        \\    data[14] = @truncate(len >> 48);
        \\    data[15] = @truncate(len >> 56);
        \\    // Copy stub content
        \\    @memcpy(data[16..], test_stubs_content);
        \\    break :blk data;
        \\};
        \\
        \\// Force the section data to be retained by exporting it
        \\comptime {
        \\    @export(&__pyoz_stubs_section__, .{ .name = "__pyoz_stubs_section__" });
        \\}
        \\
        \\pub export fn PyInit_test_stub() ?*anyopaque { return null; }
    ;

    const wf = b.addWriteFiles();
    const test_stub_file = wf.add("test_stub_lib.zig", test_stub_source);

    // Build test stub libraries for each target format (ELF, PE, Mach-O)
    const symreader_test_targets = [_]struct {
        query: std.Target.Query,
        name: []const u8,
        ext: []const u8,
    }{
        .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu }, .name = "test_stub_elf", .ext = ".so" },
        .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .windows }, .name = "test_stub_pe", .ext = ".dll" },
        .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .macos }, .name = "test_stub_macho", .ext = ".dylib" },
    };

    var test_stub_paths: [3]std.Build.LazyPath = undefined;
    var test_stub_installs: [3]*std.Build.Step = undefined;

    for (symreader_test_targets, 0..) |t, i| {
        const stub_target = b.resolveTargetQuery(t.query);
        const stub_lib = b.addLibrary(.{
            .name = t.name,
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = test_stub_file,
                .target = stub_target,
                .optimize = .Debug,
            }),
        });

        const install_stub = b.addInstallArtifact(stub_lib, .{
            .dest_dir = .{ .override = .{ .custom = "test_bins" } },
            .dest_sub_path = b.fmt("{s}{s}", .{ t.name, t.ext }),
        });

        // Get the output path from the artifact itself
        test_stub_paths[i] = stub_lib.getEmittedBin();
        test_stub_installs[i] = &install_stub.step;
    }

    // Create symreader module for tests
    const symreader_mod = b.addModule("symreader", .{
        .root_source_file = b.path("src/cli/symreader.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "symreader", .module = symreader_mod },
            },
        }),
    });

    // Pass test binary paths to tests via build options
    const test_options = b.addOptions();
    test_options.addOptionPath("elf_test_lib", test_stub_paths[0]);
    test_options.addOptionPath("pe_test_lib", test_stub_paths[1]);
    test_options.addOptionPath("macho_test_lib", test_stub_paths[2]);
    tests.root_module.addOptions("test_config", test_options);

    // Add build_options for ABI3 (always false for tests)
    const test_abi3_options = b.addOptions();
    test_abi3_options.addOption(bool, "abi3", false);
    tests.root_module.addOptions("build_options", test_abi3_options);

    // Enable sanitizers if requested
    if (sanitize) {
        tests.root_module.sanitize_c = .full;
    }

    // Link against Python for embedding
    if (python_config) |python| {
        tests.addIncludePath(.{ .cwd_relative = python.include_dir });
        tests.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (python.lib_dir) |lib_dir| {
            tests.addLibraryPath(.{ .cwd_relative = lib_dir });
        }
        tests.linkSystemLibrary(python.lib_name);
    }
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);
    // Tests depend on the example module and test stub libs being built first
    run_tests.step.dependOn(&install_example.step);
    for (test_stub_installs) |install_step| {
        run_tests.step.dependOn(install_step);
    }

    const test_step = b.step("test", "Run the PyOZ test suite");
    test_step.dependOn(&run_tests.step);

    // ========================================================================
    // ABI3 Test Suite
    // ========================================================================

    const tests_abi3 = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests_abi3.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add build_options for ABI3 (always false for tests - we use embedding)
    const test_abi3_options_for_abi3_tests = b.addOptions();
    test_abi3_options_for_abi3_tests.addOption(bool, "abi3", false);
    tests_abi3.root_module.addOptions("build_options", test_abi3_options_for_abi3_tests);

    // Enable sanitizers if requested
    if (sanitize) {
        tests_abi3.root_module.sanitize_c = .full;
    }

    // Link against Python for embedding
    if (python_config) |python| {
        tests_abi3.addIncludePath(.{ .cwd_relative = python.include_dir });
        tests_abi3.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (python.lib_dir) |lib_dir| {
            tests_abi3.addLibraryPath(.{ .cwd_relative = lib_dir });
        }
        tests_abi3.linkSystemLibrary(python.lib_name);
    }
    tests_abi3.linkLibC();

    const run_tests_abi3 = b.addRunArtifact(tests_abi3);
    // ABI3 tests depend on the ABI3 example module being built first
    run_tests_abi3.step.dependOn(&install_example_abi3.step);

    const test_abi3_step = b.step("test_abi3", "Run the PyOZ ABI3 test suite");
    test_abi3_step.dependOn(&run_tests_abi3.step);

    // ========================================================================
    // CLI Executable (pyoz command)
    // ========================================================================

    const cli_exe = b.addExecutable(.{
        .name = "pyoz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "version", .module = version_mod },
            },
        }),
    });

    // Add miniz C source (amalgamated single-file version)
    cli_exe.addCSourceFile(.{
        .file = b.path("src/miniz/miniz.c"),
        .flags = &.{"-DMINIZ_NO_STDIO"},
    });
    cli_exe.addIncludePath(b.path("src/miniz"));
    cli_exe.linkLibC();

    const install_cli = b.addInstallArtifact(cli_exe, .{});

    const cli_step = b.step("cli", "Build the PyOZ CLI tool");
    cli_step.dependOn(&install_cli.step);

    // Run CLI step for quick testing
    const run_cli = b.addRunArtifact(cli_exe);
    run_cli.step.dependOn(&install_cli.step);
    if (b.args) |args| {
        run_cli.addArgs(args);
    }

    const run_cli_step = b.step("run", "Run the PyOZ CLI tool");
    run_cli_step.dependOn(&run_cli.step);

    // ========================================================================
    // Cross-compile CLI for all major OS/arch pairs
    // ========================================================================

    const release_targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
    };

    const release_step = b.step("release", "Build CLI for all platforms (x86_64/aarch64 for Linux/macOS/Windows)");

    for (release_targets) |t| {
        const release_target = b.resolveTargetQuery(t);

        const release_version_mod = b.addModule(b.fmt("version-{s}-{s}", .{
            @tagName(t.cpu_arch.?),
            @tagName(t.os_tag.?),
        }), .{
            .root_source_file = b.path("src/version.zig"),
            .target = release_target,
            .optimize = .ReleaseSmall,
        });

        const release_exe = b.addExecutable(.{
            .name = "pyoz",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/cli/main.zig"),
                .target = release_target,
                .optimize = .ReleaseSmall,
                .strip = true,
                .imports = &.{
                    .{ .name = "version", .module = release_version_mod },
                },
            }),
        });

        // Add miniz C source for compression support
        release_exe.addCSourceFile(.{
            .file = b.path("src/miniz/miniz.c"),
            .flags = &.{"-DMINIZ_NO_STDIO"},
        });
        release_exe.addIncludePath(b.path("src/miniz"));

        // Statically link libc for fully static binaries
        release_exe.linkLibC();

        const target_name = b.fmt("pyoz-{s}-{s}{s}", .{
            @tagName(t.cpu_arch.?),
            @tagName(t.os_tag.?),
            if (t.os_tag.? == .windows) ".exe" else "",
        });

        const install_release = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{ .override = .{ .custom = "release" } },
            .dest_sub_path = target_name,
        });

        release_step.dependOn(&install_release.step);
    }

    // ========================================================================
    // Default step just shows info
    // ========================================================================

    const default_step = b.step("info", "Show build information");
    if (python_config) |python| {
        const info_cmd = b.addSystemCommand(&.{
            "echo",
            std.fmt.allocPrint(b.allocator,
                \\
                \\PyOZ - Python bindings for Zig
                \\==============================
                \\Python version: {s}
                \\Include dir:   {s}
                \\Library:       {s}
                \\
                \\To build the example module:
                \\  zig build example
                \\
                \\To build the CLI tool:
                \\  zig build cli
                \\
                \\Then test the example:
                \\  cd zig-out/lib
                \\  python3 -c "import example; print(example.add(2, 3))"
                \\
            , .{ python.version, python.include_dir, python.lib_name }) catch "Error",
        });
        default_step.dependOn(&info_cmd.step);
    }
}
