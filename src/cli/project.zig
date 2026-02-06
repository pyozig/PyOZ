const std = @import("std");
const version = @import("version");
pub const toml = @import("toml.zig");

/// Create a new PyOZ project
pub fn create(allocator: std.mem.Allocator, name_opt: ?[]const u8, in_current_dir: bool, local_pyoz_path: ?[]const u8) !void {
    var project_dir: std.fs.Dir = undefined;
    var created_dir = false;
    var name: []const u8 = undefined;
    var name_owned = false;

    if (in_current_dir) {
        // Use current directory
        project_dir = std.fs.cwd();

        // Get name from argument or directory name
        if (name_opt) |n| {
            name = n;
        } else {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fs.cwd().realpath(".", &path_buf);
            name = try allocator.dupe(u8, std.fs.path.basename(path));
            name_owned = true;
        }
    } else {
        // Create new directory
        name = name_opt orelse {
            std.debug.print("Error: Project name required when not using --path\n", .{});
            return error.MissingProjectName;
        };

        std.fs.cwd().makeDir(name) catch |err| {
            if (err == error.PathAlreadyExists) {
                std.debug.print("Error: Directory '{s}' already exists\n", .{name});
                return error.DirectoryExists;
            }
            return err;
        };
        created_dir = true;

        project_dir = try std.fs.cwd().openDir(name, .{});
    }
    defer if (created_dir) project_dir.close();
    defer if (name_owned) allocator.free(name);

    std.debug.print("Creating PyOZ project: {s}\n", .{name});

    // Validate project name (must be valid Python identifier)
    if (!isValidModuleName(name)) {
        std.debug.print("Error: '{s}' is not a valid Python module name\n", .{name});
        std.debug.print("Names must start with a letter and contain only letters, numbers, and underscores\n", .{});
        return error.InvalidModuleName;
    }

    // Create directory structure
    try project_dir.makeDir("src");

    // Create pyproject.toml
    try writeTemplate(allocator, project_dir, "pyproject.toml", pyproject_template, name);

    // Create src/lib.zig
    try writeTemplate(allocator, project_dir, "src/lib.zig", lib_zig_template, name);

    // Create build.zig (for users who want to use zig build directly)
    try writeTemplate(allocator, project_dir, "build.zig", build_zig_template, name);

    // Create build.zig.zon for dependency management
    if (local_pyoz_path) |local_path| {
        try writeLocalBuildZigZon(allocator, project_dir, name, local_path);
    } else {
        try writeTemplate(allocator, project_dir, "build.zig.zon", build_zig_zon_template, name);
        // Patch fingerprint by running zig build and parsing the suggestion
        patchFingerprint(allocator, project_dir);
        // Patch dependency hash by running zig build again
        patchDependencyHash(allocator, project_dir);
    }

    // Create .gitignore
    try project_dir.writeFile(.{ .sub_path = ".gitignore", .data = gitignore_content });

    // Create README.md
    try writeTemplate(allocator, project_dir, "README.md", readme_template, name);

    std.debug.print(
        \\
        \\Project '{s}' created successfully!
        \\
        \\Project structure:
        \\  {s}/
        \\  ├── pyproject.toml    # Project configuration
        \\  ├── build.zig         # Zig build script
        \\  ├── build.zig.zon     # Zig dependencies
        \\  ├── README.md
        \\  ├── .gitignore
        \\  └── src/
        \\      └── lib.zig       # Your module code
        \\
        \\Next steps:
        \\
    , .{ name, name });

    if (!in_current_dir) {
        std.debug.print("  cd {s}\n", .{name});
    }

    std.debug.print(
        \\  pyoz build            # Build the extension
        \\  pyoz develop          # Install in development mode
        \\  python -c "import {s}; print({s}.add(2, 3))"
        \\
    , .{ name, name });
}

fn isValidModuleName(name: []const u8) bool {
    if (name.len == 0) return false;

    // Must start with letter or underscore
    const first = name[0];
    if (!std.ascii.isAlphabetic(first) and first != '_') return false;

    // Rest must be alphanumeric or underscore
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }

    // Check against Python keywords
    const keywords = [_][]const u8{
        "False",   "None",     "True",     "and",    "as",   "assert", "async",  "await",
        "break",   "class",    "continue", "def",    "del",  "elif",   "else",   "except",
        "finally", "for",      "from",     "global", "if",   "import", "in",     "is",
        "lambda",  "nonlocal", "not",      "or",     "pass", "raise",  "return", "try",
        "while",   "with",     "yield",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return false;
    }

    return true;
}

fn replaceInTemplate(allocator: std.mem.Allocator, template: []const u8, name: []const u8) ![]u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        if (i + 9 <= template.len and std.mem.eql(u8, template[i .. i + 9], "{[name]s}")) {
            try result.appendSlice(allocator, name);
            i += 9;
        } else if (i + 17 <= template.len and std.mem.eql(u8, template[i .. i + 17], "{[pyoz_version]s}")) {
            try result.appendSlice(allocator, version.string);
            i += 17;
        } else {
            try result.append(allocator, template[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

fn writeTemplate(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    path: []const u8,
    template: []const u8,
    name: []const u8,
) !void {
    const content = try replaceInTemplate(allocator, template, name);
    defer allocator.free(content);
    try dir.writeFile(.{ .sub_path = path, .data = content });
}

/// Compute relative path from `from_path` to `to_path`
fn computeRelativePath(allocator: std.mem.Allocator, from_path: []const u8, to_path: []const u8) ![]const u8 {
    // Split paths into components
    var from_parts = std.ArrayListUnmanaged([]const u8){};
    defer from_parts.deinit(allocator);
    var to_parts = std.ArrayListUnmanaged([]const u8){};
    defer to_parts.deinit(allocator);

    var from_it = std.mem.splitScalar(u8, from_path, '/');
    while (from_it.next()) |part| {
        if (part.len > 0) try from_parts.append(allocator, part);
    }

    var to_it = std.mem.splitScalar(u8, to_path, '/');
    while (to_it.next()) |part| {
        if (part.len > 0) try to_parts.append(allocator, part);
    }

    // Find common prefix length
    var common: usize = 0;
    while (common < from_parts.items.len and common < to_parts.items.len) {
        if (!std.mem.eql(u8, from_parts.items[common], to_parts.items[common])) break;
        common += 1;
    }

    // Build relative path: go up from `from`, then down to `to`
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    // Add "../" for each remaining component in from_path
    const ups = from_parts.items.len - common;
    for (0..ups) |_| {
        try result.appendSlice(allocator, "../");
    }

    // Add remaining components from to_path
    for (to_parts.items[common..], 0..) |part, i| {
        if (i > 0) try result.append(allocator, '/');
        try result.appendSlice(allocator, part);
    }

    // Handle edge case where result is empty (same directory)
    if (result.items.len == 0) {
        try result.append(allocator, '.');
    }

    // Remove trailing slash if present
    if (result.items.len > 1 and result.items[result.items.len - 1] == '/') {
        _ = result.pop();
    }

    return result.toOwnedSlice(allocator);
}

/// Run `zig build` in the project directory, parse the suggested fingerprint
/// from stderr, and patch build.zig.zon to include it.
fn patchFingerprint(allocator: std.mem.Allocator, dir: std.fs.Dir) void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_path = dir.realpath(".", &path_buf) catch return;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build" },
        .cwd = cwd_path,
    }) catch return; // If zig build fails to run, skip fingerprint patching

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Parse the suggested fingerprint from stderr
    // Format: "suggested value: 0x661af9ad2d7f95bc"
    if (std.mem.indexOf(u8, result.stderr, "suggested value: 0x")) |idx| {
        const start = idx + 19; // length of "suggested value: 0x"
        if (start + 16 <= result.stderr.len) {
            const fingerprint_hex = result.stderr[start .. start + 16];
            // Read existing content and insert fingerprint
            const existing = dir.readFileAlloc(allocator, "build.zig.zon", 4096) catch return;
            defer allocator.free(existing);

            var patched = std.ArrayListUnmanaged(u8){};
            defer patched.deinit(allocator);

            // Insert fingerprint after version line
            if (std.mem.indexOf(u8, existing, ".version = \"0.1.0\",")) |ver_idx| {
                const insert_pos = ver_idx + 19; // after version line
                patched.appendSlice(allocator, existing[0..insert_pos]) catch return;
                patched.appendSlice(allocator, "\n    .fingerprint = 0x") catch return;
                patched.appendSlice(allocator, fingerprint_hex) catch return;
                patched.appendSlice(allocator, ",") catch return;
                patched.appendSlice(allocator, existing[insert_pos..]) catch return;

                dir.writeFile(.{ .sub_path = "build.zig.zon", .data = patched.items }) catch return;
            }
        }
    }
}

/// Run `zig build` after fingerprint patching to get the dependency hash,
/// then patch build.zig.zon to include it.
fn patchDependencyHash(allocator: std.mem.Allocator, dir: std.fs.Dir) void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_path = dir.realpath(".", &path_buf) catch return;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build" },
        .cwd = cwd_path,
    }) catch return;

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Parse the suggested hash from stderr
    // Format: note: expected .hash = "PyOZ-0.10.0-...",
    const marker = "expected .hash = \"";
    if (std.mem.indexOf(u8, result.stderr, marker)) |idx| {
        const start = idx + marker.len;
        if (std.mem.indexOfScalarPos(u8, result.stderr, start, '"')) |end| {
            const hash_value = result.stderr[start..end];

            const existing = dir.readFileAlloc(allocator, "build.zig.zon", 8192) catch return;
            defer allocator.free(existing);

            // Replace "// .hash = "..."," with actual ".hash = "VALUE","
            const comment = "// .hash = \"...\",";
            if (std.mem.indexOf(u8, existing, comment)) |comment_idx| {
                var patched = std.ArrayListUnmanaged(u8){};
                defer patched.deinit(allocator);

                patched.appendSlice(allocator, existing[0..comment_idx]) catch return;
                patched.appendSlice(allocator, ".hash = \"") catch return;
                patched.appendSlice(allocator, hash_value) catch return;
                patched.appendSlice(allocator, "\",") catch return;
                patched.appendSlice(allocator, existing[comment_idx + comment.len ..]) catch return;

                dir.writeFile(.{ .sub_path = "build.zig.zon", .data = patched.items }) catch return;
            }
        }
    }
}

fn writeLocalBuildZigZon(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    name: []const u8,
    local_path: []const u8,
) !void {
    // Get absolute path of project directory
    var proj_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const proj_abs_path = try dir.realpath(".", &proj_path_buf);

    // Make local_path absolute if it isn't already
    var pyoz_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const pyoz_abs_path = if (std.fs.path.isAbsolute(local_path))
        local_path
    else blk: {
        const cwd = std.fs.cwd();
        break :blk try cwd.realpath(local_path, &pyoz_path_buf);
    };

    // Compute relative path from project to PyOZ
    const relative_path = try computeRelativePath(allocator, proj_abs_path, pyoz_abs_path);
    defer allocator.free(relative_path);

    // Write build.zig.zon without fingerprint - zig build will generate it
    const content = try std.fmt.allocPrint(allocator,
        \\.{{
        \\    .name = .{s},
        \\    .version = "0.1.0",
        \\    .dependencies = .{{
        \\        .PyOZ = .{{
        \\            .path = "{s}",
        \\        }},
        \\    }},
        \\    .paths = .{{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "src",
        \\    }},
        \\}}
        \\
    , .{ name, relative_path });
    defer allocator.free(content);
    try dir.writeFile(.{ .sub_path = "build.zig.zon", .data = content });

    // Patch fingerprint by running zig build and parsing the suggestion
    patchFingerprint(allocator, dir);
}

// =============================================================================
// Templates
// =============================================================================

const pyproject_template =
    \\[build-system]
    \\requires = ["pyoz"]
    \\build-backend = "pyoz.build"
    \\
    \\[project]
    \\name = "{[name]s}"
    \\version = "0.1.0"
    \\description = "A Python extension module built with PyOZ"
    \\requires-python = ">=3.8"
    \\readme = "README.md"
    \\
    \\[tool.pyoz]
    \\# Path to your Zig source file
    \\module-path = "src/lib.zig"
    \\
    \\# Optimization level for release builds: "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"
    \\# optimize = "ReleaseFast"
    \\
    \\# Native module name (defaults to project name)
    \\# Use "_name" prefix to separate the .so from a Python wrapper package
    \\# module-name = "_mymodule"
    \\
    \\# Strip debug symbols in release builds
    \\# strip = true
    \\
    \\# File extensions to include from py-packages (default: .py only)
    \\# Use ["*"] to include all files
    \\# include-ext = ["py", "zig", "json"]
    \\
    \\# Linux platform tag for wheel builds (default: "linux_x86_64" or "linux_aarch64")
    \\# Use manylinux tags only if building in a manylinux container
    \\# linux-platform-tag = "manylinux_2_17_x86_64"
    \\
;

const lib_zig_template =
    \\const pyoz = @import("PyOZ");
    \\
    \\// ============================================================================
    \\// Define your functions here
    \\// ============================================================================
    \\
    \\/// Add two integers
    \\fn add(a: i64, b: i64) i64 {
    \\    return a + b;
    \\}
    \\
    \\/// Multiply two floats
    \\fn multiply(a: f64, b: f64) f64 {
    \\    return a * b;
    \\}
    \\
    \\/// Greet someone by name
    \\fn greet(name: []const u8) ![]const u8 {
    \\    _ = name;
    \\    return "Hello from {[name]s}!";
    \\}
    \\
    \\// ============================================================================
    \\// Module definition
    \\// ============================================================================
    \\
    \\pub const Module = pyoz.module(.{
    \\    .name = "{[name]s}",
    \\    .doc = "{[name]s} - A Python extension module built with PyOZ",
    \\    .funcs = &.{
    \\        pyoz.func("add", add, "Add two integers"),
    \\        pyoz.func("multiply", multiply, "Multiply two floats"),
    \\        pyoz.func("greet", greet, "Return a greeting"),
    \\    },
    \\    .classes = &.{},
    \\});
    \\
    \\// Module initialization function
    \\pub export fn PyInit_{[name]s}() ?*pyoz.PyObject {
    \\    return Module.init();
    \\}
    \\
;

const build_zig_template =
    \\//! Build script for {[name]s}
    \\//!
    \\//! You can use this directly with `zig build`, or use `pyoz build` for
    \\//! automatic Python configuration detection.
    \\
    \\const std = @import("std");
    \\const builtin = @import("builtin");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    // Strip option (can be set via -Dstrip=true or from pyoz CLI)
    \\    const strip = b.option(bool, "strip", "Strip debug symbols from the binary") orelse false;
    \\
    \\    // Get PyOZ dependency
    \\    const pyoz_dep = b.dependency("PyOZ", .{
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    // Create the user's lib module (shared between library and stub generator)
    \\    const user_lib_mod = b.createModule(.{
    \\        .root_source_file = b.path("src/lib.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\        .strip = strip,
    \\        .imports = &.{
    \\            .{ .name = "PyOZ", .module = pyoz_dep.module("PyOZ") },
    \\        },
    \\    });
    \\
    \\    // Build the Python extension as a dynamic library
    \\    const lib = b.addLibrary(.{
    \\        .name = "{[name]s}",
    \\        .linkage = .dynamic,
    \\        .root_module = user_lib_mod,
    \\    });
    \\
    \\    // Link libc (required for Python C API)
    \\    lib.linkLibC();
    \\
    \\    // Determine extension based on target OS (.pyd for Windows, .so otherwise)
    \\    const ext = if (builtin.os.tag == .windows) ".pyd" else ".so";
    \\
    \\    // Install the shared library
    \\    const install = b.addInstallArtifact(lib, .{
    \\        .dest_sub_path = "{[name]s}" ++ ext,
    \\    });
    \\    b.getInstallStep().dependOn(&install.step);
    \\
    \\}
    \\
;

const build_zig_zon_template =
    \\.{
    \\    .name = .{[name]s},
    \\    .version = "0.1.0",
    \\    .dependencies = .{
    \\        .PyOZ = .{
    \\            .url = "https://github.com/dzonerzy/PyOZ/archive/refs/tags/v{[pyoz_version]s}.tar.gz",
    \\            // .hash = "...",
    \\        },
    \\    },
    \\    .paths = .{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    },
    \\}
    \\
;

const readme_template =
    \\# {[name]s}
    \\
    \\A Python extension module built with [PyOZ](https://github.com/dzonerzy/PyOZ).
    \\
    \\## Building
    \\
    \\```bash
    \\# Using PyOZ CLI (recommended)
    \\pyoz build
    \\
    \\# Or using Zig directly
    \\zig build
    \\```
    \\
    \\## Development
    \\
    \\```bash
    \\# Install in development mode
    \\pyoz develop
    \\
    \\# Now you can import and test
    \\python -c "import {[name]s}; print({[name]s}.add(2, 3))"
    \\```
    \\
    \\## Building Wheels
    \\
    \\```bash
    \\# Build a wheel for distribution
    \\pyoz build-wheel
    \\
    \\# The wheel will be in dist/
    \\```
    \\
    \\## Usage
    \\
    \\```python
    \\import {[name]s}
    \\
    \\# Add two numbers
    \\result = {[name]s}.add(2, 3)
    \\print(result)  # 5
    \\
    \\# Multiply floats
    \\result = {[name]s}.multiply(2.5, 4.0)
    \\print(result)  # 10.0
    \\
    \\# Get a greeting
    \\print({[name]s}.greet("World"))
    \\```
    \\
;

const gitignore_content =
    \\# Zig
    \\zig-cache/
    \\zig-out/
    \\.zig-cache/
    \\
    \\# Python
    \\__pycache__/
    \\*.py[cod]
    \\*$py.class
    \\*.so
    \\*.pyd
    \\.Python
    \\build/
    \\develop/
    \\dist/
    \\*.egg-info/
    \\.eggs/
    \\
    \\# Virtual environments
    \\venv/
    \\.venv/
    \\env/
    \\
    \\# IDE
    \\.idea/
    \\.vscode/
    \\*.swp
    \\*~
    \\
;
