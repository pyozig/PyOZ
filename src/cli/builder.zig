const std = @import("std");
const builtin = @import("builtin");
const project = @import("project.zig");

/// Python configuration detected from the system
pub const PythonConfig = struct {
    version_major: u8,
    version_minor: u8,
    version_str: []const u8,
    include_dir: []const u8,
    lib_dir: ?[]const u8,
    lib_name: []const u8,

    pub fn deinit(self: *PythonConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.version_str);
        allocator.free(self.include_dir);
        if (self.lib_dir) |ld| allocator.free(ld);
        allocator.free(self.lib_name);
    }

    /// Get Python tag for wheel (e.g., "cp310")
    pub fn pythonTag(self: PythonConfig) [8]u8 {
        var buf: [8]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "cp{d}{d}", .{ self.version_major, self.version_minor }) catch unreachable;
        return buf;
    }
};

/// Get the Python executable name for the current platform
pub fn getPythonCommand() []const u8 {
    return if (builtin.os.tag == .windows) "python" else "python3";
}

/// Detect Python configuration using sysconfig (cross-platform)
pub fn detectPython(allocator: std.mem.Allocator) !PythonConfig {
    const python_cmd = getPythonCommand();

    // Get Python version
    const version_result = try runCommand(allocator, &.{
        python_cmd, "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')",
    });
    defer allocator.free(version_result);
    const version_trimmed = std.mem.trim(u8, version_result, &std.ascii.whitespace);

    // Parse version
    var version_major: u8 = 3;
    var version_minor: u8 = 0;
    if (std.mem.indexOf(u8, version_trimmed, ".")) |dot| {
        version_major = std.fmt.parseInt(u8, version_trimmed[0..dot], 10) catch 3;
        version_minor = std.fmt.parseInt(u8, version_trimmed[dot + 1 ..], 10) catch 0;
    }

    const version_str = try allocator.dupe(u8, version_trimmed);
    errdefer allocator.free(version_str);

    // Get include directory using sysconfig (cross-platform)
    const include_result = try runCommand(allocator, &.{
        python_cmd, "-c", "import sysconfig; print(sysconfig.get_path('include'))",
    });
    defer allocator.free(include_result);
    const include_trimmed = std.mem.trim(u8, include_result, &std.ascii.whitespace);

    if (include_trimmed.len == 0) {
        allocator.free(version_str);
        return error.PythonNotFound;
    }

    const include_dir = try allocator.dupe(u8, include_trimmed);
    errdefer allocator.free(include_dir);

    // Get library directory using sysconfig (cross-platform)
    var lib_dir: ?[]const u8 = null;
    if (runCommand(allocator, &.{
        python_cmd,
        "-c",
        "import sysconfig,sys,os;d=sysconfig.get_config_var('LIBDIR');print(d if d else os.path.join(sys.prefix,'libs' if sys.platform=='win32' else 'lib'))",
    })) |libdir_result| {
        defer allocator.free(libdir_result);
        const libdir_trimmed = std.mem.trim(u8, libdir_result, &std.ascii.whitespace);
        if (libdir_trimmed.len > 0) {
            lib_dir = try allocator.dupe(u8, libdir_trimmed);
        }
    } else |_| {}

    // Construct library name based on platform
    const lib_name = if (builtin.os.tag == .windows)
        // Windows uses python<major><minor> (no dot), e.g., python313
        try std.fmt.allocPrint(allocator, "python{d}{d}", .{ version_major, version_minor })
    else
        // Unix uses python<major>.<minor>, e.g., python3.13
        try std.fmt.allocPrint(allocator, "python{s}", .{version_str});

    return PythonConfig{
        .version_major = version_major,
        .version_minor = version_minor,
        .version_str = version_str,
        .include_dir = include_dir,
        .lib_dir = lib_dir,
        .lib_name = lib_name,
    };
}

/// Build result with path to the compiled module
pub const BuildResult = struct {
    module_path: []const u8,
    module_name: []const u8,

    pub fn deinit(self: *BuildResult, allocator: std.mem.Allocator) void {
        allocator.free(self.module_path);
        allocator.free(self.module_name);
    }
};

/// Build the extension module (shared library)
/// Returns the path to the built .so/.pyd file
pub fn buildModule(allocator: std.mem.Allocator, release: bool) !BuildResult {
    // Load project configuration
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
            return err;
        }
        std.debug.print("Error: Failed to parse pyproject.toml\n", .{});
        return err;
    };
    defer config.deinit(allocator);

    // Determine build type display string
    const optimize_setting = config.getOptimize();
    const build_type = if (release) "Release" else if (optimize_setting.len > 0) optimize_setting else "Debug";
    std.debug.print("Building {s} v{s} ({s})...\n", .{ config.name, config.getVersion(), build_type });

    // Detect Python configuration
    var python = detectPython(allocator) catch |err| {
        if (builtin.os.tag == .windows) {
            std.debug.print("Error: Could not detect Python. Make sure python is in PATH.\n", .{});
        } else {
            std.debug.print("Error: Could not detect Python. Make sure python3 is in PATH.\n", .{});
        }
        return err;
    };
    defer python.deinit(allocator);

    std.debug.print("  Python {s} detected\n", .{python.version_str});
    std.debug.print("  Module: {s}\n", .{config.getModulePath()});

    // Determine output filename based on platform
    const ext = switch (builtin.os.tag) {
        .windows => ".pyd",
        else => ".so",
    };

    // Check if build.zig exists
    const cwd = std.fs.cwd();
    const has_build_zig = blk: {
        cwd.access("build.zig", .{}) catch break :blk false;
        break :blk true;
    };

    if (has_build_zig) {
        std.debug.print("  Using build.zig\n", .{});

        // Determine optimization level:
        // - If --release flag is passed, always use ReleaseFast
        // - Otherwise, use the optimize setting from pyproject.toml (empty = debug)
        var argv_buf: [6][]const u8 = undefined;
        var argv_len: usize = 2;
        argv_buf[0] = "zig";
        argv_buf[1] = "build";

        var optimize_arg_buf: [64]u8 = undefined;
        const optimize_value = if (release) "ReleaseFast" else config.getOptimize();
        if (optimize_value.len > 0) {
            const optimize_arg = std.fmt.bufPrint(&optimize_arg_buf, "-Doptimize={s}", .{optimize_value}) catch "-Doptimize=ReleaseFast";
            argv_buf[argv_len] = optimize_arg;
            argv_len += 1;
        }

        // Pass strip option if enabled in pyproject.toml
        if (config.strip) {
            std.debug.print("  Strip: enabled\n", .{});
            argv_buf[argv_len] = "-Dstrip=true";
            argv_len += 1;
        }

        // On Windows, pass Python library info so zig build can link against python3.lib
        // (Windows linker requires all symbols resolved at link time, unlike Unix)
        var lib_dir_arg: ?[]const u8 = null;
        defer if (lib_dir_arg) |a| allocator.free(a);
        if (builtin.os.tag == .windows) {
            if (python.lib_dir) |lib_dir| {
                lib_dir_arg = std.fmt.allocPrint(allocator, "-Dpython-lib-dir={s}", .{lib_dir}) catch null;
                if (lib_dir_arg) |arg| {
                    argv_buf[argv_len] = arg;
                    argv_len += 1;
                }
            }
            argv_buf[argv_len] = "-Dpython-lib-name=python3";
            argv_len += 1;
        }

        const argv: []const []const u8 = argv_buf[0..argv_len];

        var child = std.process.Child.init(argv, allocator);
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        const term = try child.spawnAndWait();
        if (term.Exited != 0) {
            std.debug.print("\nBuild failed!\n", .{});
            return error.BuildFailed;
        }

        const module_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.getModuleName(), ext });
        // On Windows, Zig places DLLs (.pyd) in zig-out/bin/, import libs in zig-out/lib/
        const out_dir = if (builtin.os.tag == .windows) "zig-out/bin" else "zig-out/lib";
        const module_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ out_dir, module_name });

        return BuildResult{
            .module_path = module_path,
            .module_name = module_name,
        };
    } else {
        std.debug.print("Error: build.zig not found. Please create a build.zig file.\n", .{});
        std.debug.print("Run 'pyoz init --path' to generate one in the current directory.\n", .{});
        return error.NoBuildZig;
    }
}

/// Build and install in development mode (symlink to site-packages or local)
pub fn developMode(allocator: std.mem.Allocator) !void {
    // Load project configuration for display
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
            return err;
        }
        return err;
    };
    defer config.deinit(allocator);

    std.debug.print("Installing {s} in development mode...\n", .{config.name});

    // Build the module (debug mode for develop)
    var result = try buildModule(allocator, false);
    defer result.deinit(allocator);

    // Get absolute path for the built module
    var abs_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_built_path = std.fs.cwd().realpath(result.module_path, &abs_path_buf) catch |err| {
        std.debug.print("Error: Built module not found at {s}\n", .{result.module_path});
        return err;
    };

    // Detect package mode: module name starts with '_' and a py-package matches project name
    const is_package_mode = blk: {
        const mod_name = config.getModuleName();
        if (mod_name.len > 0 and mod_name[0] == '_') {
            for (config.py_packages.items) |pkg| {
                if (std.mem.eql(u8, pkg, config.name)) break :blk true;
            }
        }
        break :blk false;
    };

    // In package mode, symlink .so into the local package directory on disk
    // so that when the package dir is symlinked to site-packages, it includes the .so
    if (is_package_mode) {
        const so_in_pkg = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ config.name, result.module_name });
        defer allocator.free(so_in_pkg);
        std.fs.cwd().deleteFile(so_in_pkg) catch {};
        std.fs.cwd().symLink(abs_built_path, so_in_pkg, .{}) catch |err| {
            std.debug.print("Warning: Could not symlink .so into package directory: {s}\n", .{@errorName(err)});
        };
        std.debug.print("  Symlinked extension into package: {s}\n", .{so_in_pkg});
    }

    // First, check if we're in a virtual environment
    // This checks VIRTUAL_ENV env var OR if sys.prefix != sys.base_prefix
    const python_cmd = getPythonCommand();
    const venv_check = runCommand(allocator, &.{
        python_cmd, "-c",
        \\import sys, os
        \\venv = os.environ.get('VIRTUAL_ENV')
        \\if venv or sys.prefix != sys.base_prefix:
        \\    # In a venv - get site-packages from sys.path
        \\    import site
        \\    for p in site.getsitepackages():
        \\        if 'site-packages' in p:
        \\            print(p)
        \\            break
        \\    else:
        \\        print(site.getsitepackages()[0])
        \\else:
        \\    print('NO_VENV')
        ,
    }) catch {
        // Fall back to local symlink
        if (!is_package_mode)
            try createLocalSymlink(allocator, abs_built_path, result.module_name, config.name);
        return;
    };
    defer allocator.free(venv_check);
    const venv_result = std.mem.trim(u8, venv_check, &std.ascii.whitespace);

    // If not in venv, try system site-packages but expect it might fail
    var site_result_owned: ?[]const u8 = null;
    defer if (site_result_owned) |sr| allocator.free(sr);

    const site_dir = if (std.mem.eql(u8, venv_result, "NO_VENV")) blk: {
        site_result_owned = runCommand(allocator, &.{
            python_cmd, "-c", "import site; print(site.getsitepackages()[0])",
        }) catch {
            if (!is_package_mode)
                try createLocalSymlink(allocator, abs_built_path, result.module_name, config.name);
            return;
        };
        break :blk std.mem.trim(u8, site_result_owned.?, &std.ascii.whitespace);
    } else blk: {
        std.debug.print("  Virtual environment detected\n", .{});
        break :blk venv_result;
    };

    // In flat mode, symlink .so directly to site-packages
    // In package mode, skip this — the .so is inside the package directory
    if (!is_package_mode) {
        const target_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ site_dir, result.module_name });
        defer allocator.free(target_path);

        // Try to create symlink in site-packages
        if (builtin.os.tag == .windows) {
            std.fs.copyFileAbsolute(abs_built_path, target_path, .{}) catch |err| {
                std.debug.print("Warning: Could not copy to site-packages ({s})\n", .{@errorName(err)});
                try createLocalSymlink(allocator, abs_built_path, result.module_name, config.name);
                return;
            };
            std.debug.print("\nCopied to: {s}\n", .{target_path});
        } else {
            std.fs.deleteFileAbsolute(target_path) catch {};
            std.posix.symlink(abs_built_path, target_path) catch |err| {
                if (err == error.AccessDenied) {
                    std.debug.print("Warning: Permission denied for site-packages. Creating local symlink.\n", .{});
                }
                try createLocalSymlink(allocator, abs_built_path, result.module_name, config.name);
                return;
            };
            std.debug.print("\nSymlinked to: {s}\n", .{target_path});
        }
    }

    // Also symlink/copy Python packages
    for (config.py_packages.items) |pkg| {
        var pkg_abs_buf: [std.fs.max_path_bytes]u8 = undefined;
        const pkg_abs = std.fs.cwd().realpath(pkg, &pkg_abs_buf) catch {
            std.debug.print("  Warning: Python package '{s}' not found, skipping\n", .{pkg});
            continue;
        };
        const pkg_target = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ site_dir, pkg });
        defer allocator.free(pkg_target);

        if (builtin.os.tag != .windows) {
            // Remove existing symlink/dir
            std.fs.deleteFileAbsolute(pkg_target) catch {};
            std.posix.symlink(pkg_abs, pkg_target) catch |err| {
                std.debug.print("  Warning: Could not symlink Python package '{s}': {s}\n", .{ pkg, @errorName(err) });
                continue;
            };
            std.debug.print("  Symlinked Python package: {s}\n", .{pkg});
        }
    }

    std.debug.print("\nDevelopment install complete!\n", .{});
    std.debug.print("Test with: {s} -c \"import {s}; print({s}.add(2, 3))\"\n", .{ python_cmd, config.name, config.name });
}

fn createLocalSymlink(allocator: std.mem.Allocator, abs_built_path: []const u8, module_name: []const u8, project_name: []const u8) !void {
    _ = allocator;
    const python_cmd = getPythonCommand();
    const cwd = std.fs.cwd();
    cwd.deleteFile(module_name) catch {};
    cwd.symLink(abs_built_path, module_name, .{}) catch |err| {
        std.debug.print("Error: Could not create symlink: {s}\n", .{@errorName(err)});
        std.debug.print("\nManual installation:\n", .{});
        if (builtin.os.tag == .windows) {
            std.debug.print("  copy {s} .\\{s}\n", .{ abs_built_path, module_name });
        } else {
            std.debug.print("  ln -sf {s} ./{s}\n", .{ abs_built_path, module_name });
        }
        return err;
    };

    std.debug.print("\nCreated local symlink: ./{s}\n", .{module_name});
    std.debug.print("You can import the module from this directory.\n", .{});
    std.debug.print("Test with: {s} -c \"import {s}; print({s}.add(2, 3))\"\n", .{ python_cmd, project_name, project_name });
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    }) catch return error.CommandFailed;

    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }

    return result.stdout;
}
