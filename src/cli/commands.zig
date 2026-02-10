const std = @import("std");
const builtin = @import("builtin");
const version = @import("version");

const project = @import("project.zig");
const builder = @import("builder.zig");
const wheel = @import("wheel.zig");
const symreader = @import("symreader.zig");

/// Initialize a new PyOZ project
pub fn init(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var project_name: ?[]const u8 = null;
    var show_help = false;
    var in_current_dir = false;
    var local_pyoz_path: ?[]const u8 = null;
    var package_layout = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--path") or std.mem.eql(u8, arg, "-p")) {
            in_current_dir = true;
        } else if (std.mem.eql(u8, arg, "--package") or std.mem.eql(u8, arg, "-k")) {
            package_layout = true;
        } else if (std.mem.eql(u8, arg, "--local") or std.mem.eql(u8, arg, "-l")) {
            // Next arg must be the path
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                i += 1;
                local_pyoz_path = args[i];
            } else {
                std.debug.print("Error: --local requires a path argument\n", .{});
                std.debug.print("  pyoz init --local /path/to/PyOZ myproject\n", .{});
                return error.MissingLocalPath;
            }
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            project_name = arg;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz init [options] [name]
            \\
            \\Create a new PyOZ project.
            \\
            \\Arguments:
            \\  name                Project name (required unless using --path)
            \\
            \\Options:
            \\  -p, --path          Initialize in current directory instead of creating new one
            \\  -k, --package       Create a Python package layout (recommended for larger projects)
            \\  -l, --local <path>  Use local PyOZ path instead of fetching from URL
            \\  -h, --help          Show this help message
            \\
            \\Examples:
            \\  pyoz init myproject                        # Create with URL dependency (flat layout)
            \\  pyoz init --package myproject              # Create with package directory layout
            \\  pyoz init --local /path/to/PyOZ myproject  # Use local PyOZ path
            \\  pyoz init --path                           # Initialize in current directory
            \\  pyoz init --path mymod                     # Initialize in current dir with name 'mymod'
            \\
        , .{});
        return;
    }

    try project.create(allocator, project_name, in_current_dir, local_pyoz_path, package_layout);
}

/// Build the extension module and create a wheel
pub fn build(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var release = false;
    var show_help = false;
    var generate_stubs = true;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--release") or std.mem.eql(u8, arg, "-r")) {
            release = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-d")) {
            release = false;
        } else if (std.mem.eql(u8, arg, "--no-stubs")) {
            generate_stubs = false;
        } else if (std.mem.eql(u8, arg, "--stubs")) {
            generate_stubs = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz build [options]
            \\
            \\Build the extension module and create a wheel package.
            \\
            \\Options:
            \\  -d, --debug    Build in debug mode (default)
            \\  -r, --release  Build in release mode (optimized)
            \\  --stubs        Generate .pyi type stub file (default)
            \\  --no-stubs     Do not generate .pyi type stub file
            \\  -h, --help     Show this help message
            \\
            \\The wheel will be placed in the dist/ directory.
            \\
        , .{});
        return;
    }

    const wheel_path = try wheel.buildWheel(allocator, release, generate_stubs);
    defer allocator.free(wheel_path);
}

/// Build and install in development mode
pub fn develop(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var show_help = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz develop
            \\
            \\Build the module and install it in development mode.
            \\Creates a symlink so changes are reflected after rebuilding.
            \\
            \\Options:
            \\  -h, --help  Show this help message
            \\
        , .{});
        return;
    }

    try builder.developMode(allocator);
}

/// Publish wheel(s) to PyPI
pub fn publish(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var show_help = false;
    var test_pypi = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--test") or std.mem.eql(u8, arg, "-t")) {
            test_pypi = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz publish [options]
            \\
            \\Publish wheel(s) from dist/ to PyPI.
            \\
            \\Options:
            \\  -t, --test  Upload to TestPyPI instead of PyPI
            \\  -h, --help  Show this help message
            \\
            \\Authentication:
            \\  Set PYPI_TOKEN environment variable with your API token.
            \\  For TestPyPI, use TEST_PYPI_TOKEN instead.
            \\
            \\  Generate tokens at:
            \\    PyPI:     https://pypi.org/manage/account/token/
            \\    TestPyPI: https://test.pypi.org/manage/account/token/
            \\
        , .{});
        return;
    }

    try wheel.publish(allocator, test_pypi);
}

/// Run embedded tests
pub fn runTests(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var release = false;
    var show_help = false;
    var verbose = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--release") or std.mem.eql(u8, arg, "-r")) {
            release = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz test [options]
            \\
            \\Run tests embedded in the module via pyoz.test() definitions.
            \\
            \\Options:
            \\  -r, --release  Build in release mode before testing
            \\  -v, --verbose  Verbose test output
            \\  -h, --help     Show this help message
            \\
        , .{});
        return;
    }

    // Load project config to detect package mode
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
        }
        return err;
    };
    defer config.deinit(allocator);

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

    // Build the module
    var build_result = try builder.buildModule(allocator, release);
    defer build_result.deinit(allocator);

    // In package mode, copy .pyd/.so into the package directory so `import ravn` works
    if (is_package_mode) {
        const pkg_module_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ config.name, build_result.module_name });
        defer allocator.free(pkg_module_path);
        std.fs.cwd().copyFile(build_result.module_path, std.fs.cwd(), pkg_module_path, .{}) catch |err| {
            std.debug.print("Warning: Could not copy module into package directory: {s}\n", .{@errorName(err)});
        };
    }

    // Extract tests from the compiled module
    const test_content = symreader.extractTests(allocator, build_result.module_path) catch |err| {
        std.debug.print("Error: Could not extract tests: {}\n", .{err});
        return err;
    };

    if (test_content == null or test_content.?.len == 0) {
        std.debug.print("\nNo tests found in module.\n", .{});
        std.debug.print("Add .tests to your pyoz.module() config:\n\n", .{});
        std.debug.print("  .tests = &.{{\n", .{});
        std.debug.print("      pyoz.@\"test\"(\"my test\",\n", .{});
        std.debug.print("          \\\\assert mymod.add(2, 3) == 5\n", .{});
        std.debug.print("      ),\n", .{});
        std.debug.print("  }},\n", .{});
        return;
    }
    defer allocator.free(test_content.?);

    // Write test file next to the built module
    const test_file = if (builtin.os.tag == .windows) "zig-out/bin/__pyoz_test.py" else "zig-out/lib/__pyoz_test.py";
    {
        const cwd = std.fs.cwd();
        const f = cwd.createFile(test_file, .{}) catch |err| {
            std.debug.print("Error: Could not write test file: {s}\n", .{@errorName(err)});
            return err;
        };
        defer f.close();
        f.writeAll(test_content.?) catch |err| {
            std.debug.print("Error: Could not write test file: {s}\n", .{@errorName(err)});
            return err;
        };
    }

    // Syntax-check the generated test file before running
    const python_cmd = builder.getPythonCommand();
    {
        const syntax_argv = [_][]const u8{ python_cmd, "-m", "py_compile", test_file };
        var syntax_check = std.process.Child.init(&syntax_argv, allocator);
        syntax_check.stderr_behavior = .Inherit;
        syntax_check.stdout_behavior = .Ignore;
        const syntax_term = try syntax_check.spawnAndWait();
        if (syntax_term.Exited != 0) {
            std.debug.print("\nSyntax error in generated test file.\n", .{});
            std.debug.print("Check the Python code in your pyoz.@\"test\"() definitions.\n", .{});
            std.process.exit(1);
        }
    }

    std.debug.print("\nRunning tests...\n\n", .{});
    const path_sep = if (builtin.os.tag == .windows) ";" else ":";

    // Build PYTHONPATH
    const existing_pp = std.process.getEnvVarOwned(allocator, "PYTHONPATH") catch "";
    defer if (existing_pp.len > 0) allocator.free(existing_pp);

    // On Windows, Zig places DLLs (.pyd) in zig-out/bin/, so use the correct directory
    const out_dir = if (builtin.os.tag == .windows) "zig-out/bin" else "zig-out/lib";
    // In package mode, also add project root so `import ravn` finds ravn/__init__.py
    const new_pp = if (is_package_mode)
        if (existing_pp.len > 0)
            try std.fmt.allocPrint(allocator, ".{s}{s}{s}{s}", .{ path_sep, out_dir, path_sep, existing_pp })
        else
            try std.fmt.allocPrint(allocator, ".{s}{s}", .{ path_sep, out_dir })
    else if (existing_pp.len > 0)
        try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ out_dir, path_sep, existing_pp })
    else
        try allocator.dupe(u8, out_dir);
    defer allocator.free(new_pp);

    // Build argv
    var argv_buf: [6][]const u8 = undefined;
    var argc: usize = 0;
    argv_buf[argc] = python_cmd;
    argc += 1;
    argv_buf[argc] = "-m";
    argc += 1;
    argv_buf[argc] = "unittest";
    argc += 1;
    argv_buf[argc] = test_file;
    argc += 1;
    if (verbose) {
        argv_buf[argc] = "-v";
        argc += 1;
    }

    var env_map = std.process.getEnvMap(allocator) catch |err| {
        std.debug.print("Error: Could not get environment: {s}\n", .{@errorName(err)});
        return err;
    };
    defer env_map.deinit();
    try env_map.put("PYTHONPATH", new_pp);

    var child = std.process.Child.init(argv_buf[0..argc], allocator);
    child.env_map = &env_map;
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term.Exited != 0) {
        std.process.exit(1);
    }
}

/// Run embedded benchmarks
pub fn runBench(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var show_help = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz bench [options]
            \\
            \\Run benchmarks embedded in the module via pyoz.bench() definitions.
            \\Always builds in release mode.
            \\
            \\Options:
            \\  -h, --help  Show this help message
            \\
        , .{});
        return;
    }

    // Load project config to detect package mode
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
        }
        return err;
    };
    defer config.deinit(allocator);

    // Detect package mode
    const is_package_mode = blk: {
        const mod_name = config.getModuleName();
        if (mod_name.len > 0 and mod_name[0] == '_') {
            for (config.py_packages.items) |pkg| {
                if (std.mem.eql(u8, pkg, config.name)) break :blk true;
            }
        }
        break :blk false;
    };

    // Always build in release mode for benchmarks
    var build_result = try builder.buildModule(allocator, true);
    defer build_result.deinit(allocator);

    // In package mode, copy .pyd/.so into the package directory so `import ravn` works
    if (is_package_mode) {
        const pkg_module_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ config.name, build_result.module_name });
        defer allocator.free(pkg_module_path);
        std.fs.cwd().copyFile(build_result.module_path, std.fs.cwd(), pkg_module_path, .{}) catch |err| {
            std.debug.print("Warning: Could not copy module into package directory: {s}\n", .{@errorName(err)});
        };
    }

    // Extract benchmarks from the compiled module
    const bench_content = symreader.extractBenchmarks(allocator, build_result.module_path) catch |err| {
        std.debug.print("Error: Could not extract benchmarks: {}\n", .{err});
        return err;
    };

    if (bench_content == null or bench_content.?.len == 0) {
        std.debug.print("\nNo benchmarks found in module.\n", .{});
        std.debug.print("Add .benchmarks to your pyoz.module() config:\n\n", .{});
        std.debug.print("  .benchmarks = &.{{\n", .{});
        std.debug.print("      pyoz.bench(\"my benchmark\",\n", .{});
        std.debug.print("          \\\\mymod.add(100, 200)\n", .{});
        std.debug.print("      ),\n", .{});
        std.debug.print("  }},\n", .{});
        return;
    }
    defer allocator.free(bench_content.?);

    // Write benchmark file next to the built module
    const bench_file = if (builtin.os.tag == .windows) "zig-out/bin/__pyoz_bench.py" else "zig-out/lib/__pyoz_bench.py";
    {
        const cwd = std.fs.cwd();
        const f = cwd.createFile(bench_file, .{}) catch |err| {
            std.debug.print("Error: Could not write benchmark file: {s}\n", .{@errorName(err)});
            return err;
        };
        defer f.close();
        f.writeAll(bench_content.?) catch |err| {
            std.debug.print("Error: Could not write benchmark file: {s}\n", .{@errorName(err)});
            return err;
        };
    }

    // Syntax-check the generated benchmark file before running
    const python_cmd = builder.getPythonCommand();
    {
        const syntax_argv = [_][]const u8{ python_cmd, "-m", "py_compile", bench_file };
        var syntax_check = std.process.Child.init(&syntax_argv, allocator);
        syntax_check.stderr_behavior = .Inherit;
        syntax_check.stdout_behavior = .Ignore;
        const syntax_term = try syntax_check.spawnAndWait();
        if (syntax_term.Exited != 0) {
            std.debug.print("\nSyntax error in generated benchmark file.\n", .{});
            std.debug.print("Check the Python code in your pyoz.bench() definitions.\n", .{});
            std.process.exit(1);
        }
    }

    std.debug.print("\nRunning benchmarks...\n", .{});
    const path_sep = if (builtin.os.tag == .windows) ";" else ":";

    const existing_pp = std.process.getEnvVarOwned(allocator, "PYTHONPATH") catch "";
    defer if (existing_pp.len > 0) allocator.free(existing_pp);

    // On Windows, Zig places DLLs (.pyd) in zig-out/bin/, so use the correct directory
    const bench_out_dir = if (builtin.os.tag == .windows) "zig-out/bin" else "zig-out/lib";
    // In package mode, also add project root so `import ravn` finds ravn/__init__.py
    const new_pp = if (is_package_mode)
        if (existing_pp.len > 0)
            try std.fmt.allocPrint(allocator, ".{s}{s}{s}{s}", .{ path_sep, bench_out_dir, path_sep, existing_pp })
        else
            try std.fmt.allocPrint(allocator, ".{s}{s}", .{ path_sep, bench_out_dir })
    else if (existing_pp.len > 0)
        try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ bench_out_dir, path_sep, existing_pp })
    else
        try allocator.dupe(u8, bench_out_dir);
    defer allocator.free(new_pp);

    var env_map = std.process.getEnvMap(allocator) catch |err| {
        std.debug.print("Error: Could not get environment: {s}\n", .{@errorName(err)});
        return err;
    };
    defer env_map.deinit();
    try env_map.put("PYTHONPATH", new_pp);

    const argv = [_][]const u8{ python_cmd, bench_file };
    var child = std.process.Child.init(&argv, allocator);
    child.env_map = &env_map;
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term.Exited != 0) {
        std.process.exit(1);
    }
}
