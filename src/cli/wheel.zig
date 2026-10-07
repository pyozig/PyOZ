const std = @import("std");
const builtin = @import("builtin");
const project = @import("project.zig");
const builder = @import("builder.zig");
const pypi = @import("pypi.zig");
const zip = @import("zip.zig");
const symreader = @import("symreader.zig");
const sys = @import("sys.zig");
const binfo = @import("binfo.zig");
const metadata = @import("metadata.zig");
const target_mod = @import("target.zig");
const Target = target_mod.Target;
const Python = target_mod.Python;
const Ctx = sys.Ctx;
const Io = std.Io;

pub const WheelOptions = struct {
    release: bool = false,
    stubs: bool = true,
    /// Platforms to build wheels for; empty means this machine's platform.
    targets: []const Target = &.{},
    /// CPython version to build for; null means the `python3` on PATH.
    python: ?Python = null,
    /// Build for this machine only (native CPU and libc). Such wheels may use
    /// CPU instructions other machines lack; they are not for distribution.
    native: bool = false,
};

/// Build a wheel package (.whl) for this platform; returns its path (caller frees).
/// A wheel is a ZIP file with a specific structure:
///   {module}.{ext}                    - The compiled extension
///   {module}.pyi                      - Type stubs (optional)
///   {distribution}-{version}.dist-info/
///     WHEEL                           - Wheel metadata
///     METADATA                        - Package metadata
///     RECORD                          - File hashes
pub fn buildWheel(ctx: Ctx, release: bool, generate_stubs: bool) ![]const u8 {
    const paths = try buildWheels(ctx, .{ .release = release, .stubs = generate_stubs });
    defer ctx.gpa.free(paths);
    return paths[0];
}

/// Build one wheel per target; returns their paths (caller frees each and the slice).
pub fn buildWheels(ctx: Ctx, opts: WheelOptions) ![][]const u8 {
    const allocator = ctx.gpa;
    const host = Target.host() orelse return error.UnsupportedHost;
    const targets: []const Target = if (opts.targets.len > 0) opts.targets else &.{host};

    var paths: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (paths.items) |p| allocator.free(p);
        paths.deinit(allocator);
    }
    for (targets) |t| {
        const path = buildOneWheel(ctx, opts, t) catch |err| switch (err) {
            // e.g. CPython 3.10 on Windows ARM64: skip it when building several
            error.UnsupportedPython => if (targets.len > 1) {
                var buf: [32]u8 = undefined;
                std.debug.print("  Skipping {s}: no CPython build for it.\n\n", .{t.name(&buf)});
                continue;
            } else return err,
            else => return err,
        };
        try paths.append(allocator, path);
    }
    if (paths.items.len == 0) return error.NothingBuilt;

    if (paths.items.len > 1) {
        std.debug.print("\nBuilt {d} wheels:\n", .{paths.items.len});
        for (paths.items) |p| std.debug.print("  {s}\n", .{p});
    }
    return paths.toOwnedSlice(allocator);
}

fn buildOneWheel(ctx: Ctx, opts: WheelOptions, target: Target) ![]const u8 {
    const allocator = ctx.gpa;
    const io = ctx.io;
    // Load project configuration
    var config = project.toml.loadPyProject(allocator, io) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
            return err;
        }
        return err;
    };
    defer config.deinit(allocator);

    // [tool.pyoz] linux-platform-tag: a manylinux tag sets the glibc floor;
    // a plain linux_* tag asks for a native (non-portable) build.
    var native = opts.native;
    var glibc: target_mod.Glibc = .{};
    const tag_setting = config.getLinuxPlatformTag();
    if (target.os == .linux and tag_setting.len > 0) {
        if (target_mod.Glibc.fromTag(tag_setting)) |g| {
            glibc = g;
        } else if (std.mem.startsWith(u8, tag_setting, "linux_")) {
            native = true;
        } else {
            std.debug.print("Error: unsupported linux-platform-tag \"{s}\" (use manylinux_2_X_<arch> or linux_<arch>)\n", .{tag_setting});
            return error.UnsupportedPlatformTag;
        }
    }
    if (native and !target.isHost()) {
        std.debug.print("Error: --native builds only for this machine; drop --target or --native.\n", .{});
        return error.NativeCrossBuild;
    }

    // Check the metadata (readme, license files, ...) before compiling, which
    // can take minutes: the same step runs again when the wheel is written.
    {
        var md = try metadata.build(allocator, io, Io.Dir.cwd());
        md.deinit(allocator);
    }

    // Build the module
    var build_result = try builder.buildModule(ctx, .{
        .release = opts.release,
        .target = if (native) null else target,
        .python = opts.python,
        .glibc = glibc,
    });
    defer build_result.deinit(allocator);
    const py = build_result.python;

    // The Stable ABI does not exist for free-threaded CPython (before 3.15's abi3t)
    var py_buf: [16]u8 = undefined;
    if (config.getAbi3() and py.freethreaded) {
        std.debug.print("Error: abi3 = true cannot target free-threaded Python {s}.\n", .{py.name(&py_buf)});
        std.debug.print("Build for a regular interpreter, or set abi3 = false for a cp3XYt wheel.\n", .{});
        return error.Abi3NotSupportedOnFreeThreaded;
    }

    if (target.os == .windows) try checkImportSlots(allocator, io, build_result.module_path);

    std.debug.print("\nCreating wheel package...\n", .{});

    // Create dist directory
    const cwd = Io.Dir.cwd();
    cwd.createDir(io, "dist", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Tags: ABI3 wheels are cp310-abi3 (the Python 3.10 minimum); otherwise
    // cpXY-cpXY[t]. The platform tag is read from the built binary.
    var pytag_buf: [16]u8 = undefined;
    var abitag_buf: [16]u8 = undefined;
    const python_tag: []const u8 = if (config.getAbi3()) "cp310" else py.pythonTag(&pytag_buf);
    const abi_tag: []const u8 = if (config.getAbi3()) "abi3" else py.abiTag(&abitag_buf);

    var tag = try binfo.platformTagOfFile(allocator, io, build_result.module_path);
    defer allocator.free(tag.text);
    defer if (tag.not_portable) |np| allocator.free(np);
    if (tag.not_portable) |why| {
        std.debug.print("  Warning: tagging {s}: {s}. PyPI does not accept linux_* wheels.\n", .{ tag.text, why });
    } else if (native and target.os == .linux) {
        // Native builds may use this CPU's instructions: not a manylinux wheel
        allocator.free(tag.text);
        tag.text = try std.fmt.allocPrint(allocator, "linux_{s}", .{@tagName(target.arch)});
    }
    if (native) std.debug.print("  Note: native build (this machine's CPU); do not publish this wheel.\n", .{});
    const platform_tag = tag.text;
    std.debug.print("  Platform tag: {s}\n", .{platform_tag});

    const dist_name = try normalizeDistName(allocator, config.name);
    defer allocator.free(dist_name);

    const wheel_filename = try std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}-{s}-{s}.whl",
        .{ dist_name, config.getVersion(), python_tag, abi_tag, platform_tag },
    );
    defer allocator.free(wheel_filename);

    const wheel_path = try std.fmt.allocPrint(allocator, "dist/{s}", .{wheel_filename});
    errdefer allocator.free(wheel_path);

    // Extract stubs from the compiled module if enabled
    var stub_content: ?[]const u8 = null;
    defer if (stub_content) |sc| allocator.free(sc);

    if (opts.stubs) {
        std.debug.print("  Extracting type stubs from module...\n", .{});
        stub_content = symreader.extractStubs(io, allocator, build_result.module_path) catch |err| blk: {
            std.debug.print("  Warning: Could not extract stubs: {}\n", .{err});
            break :blk null;
        };

        if (stub_content) |_| {
            std.debug.print("  Including type stubs: {s}.pyi\n", .{config.getModuleName()});
        } else {
            std.debug.print("  Note: No stubs found in module. Ensure your module uses pyoz.module().\n", .{});
        }
    }

    // Create the wheel (ZIP file)
    // Reproducible builds: honor SOURCE_DATE_EPOCH for ZIP entry timestamps
    const mtime: ?i64 = if (ctx.environ.get("SOURCE_DATE_EPOCH")) |v|
        std.fmt.parseInt(i64, std.mem.trim(u8, v, &std.ascii.whitespace), 10) catch null
    else
        null;

    const wheel_tag = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ python_tag, abi_tag, platform_tag });
    defer allocator.free(wheel_tag);
    try createWheelZip(allocator, io, mtime, dist_name, wheel_path, &config, wheel_tag, build_result.module_path, build_result.module_name, stub_content);

    std.debug.print("\nWheel created: {s}\n", .{wheel_path});
    if (target.isHost()) std.debug.print("\nTo install locally: pip install {s}\n", .{wheel_path});
    std.debug.print("To publish: pyoz publish\n", .{});

    // Return owned path (caller must free)
    return wheel_path;
}

/// Refuse a Windows module that would hand out an import slot as a Python
/// object (see binfo.importSlotConstants): it crashes when that path runs.
fn checkImportSlots(allocator: std.mem.Allocator, io: Io, module_path: []const u8) !void {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, module_path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(bytes);
    const found = try binfo.importSlotConstants(bytes);
    if (found.count == 0) return;
    std.debug.print("\nError: {s} has {d} constant(s) holding the address of an import slot instead of the object", .{ module_path, found.count });
    if (found.first) |name| std.debug.print(" (first: {s})", .{name});
    std.debug.print(".\nThe module would crash when it uses one. This happens when code takes the address of\n", .{});
    std.debug.print("Python data (e.g. &pyoz.py.c._Py_NoneStruct or a PyExc_* variable) directly: use the\n", .{});
    std.debug.print("pyoz.py accessors (pyoz.py.Py_None(), pyoz.py.PyExc_TypeError(), ...) instead.\n", .{});
    return error.ImportSlotConstants;
}

fn createWheelZip(
    allocator: std.mem.Allocator,
    io: Io,
    mtime: ?i64,
    dist_name: []const u8,
    wheel_path: []const u8,
    config: *const project.toml.PyProjectConfig,
    /// "{python}-{abi}-{platform}", e.g. "cp312-cp312-manylinux_2_17_x86_64"
    wheel_tag: []const u8,
    module_path: []const u8,
    module_name: []const u8,
    stub_content: ?[]const u8,
) !void {
    // Write next to the final path and rename on success: a failure part way
    // must not leave a broken wheel in dist/ (where `pyoz publish` would
    // upload it) nor destroy the previous good one.
    const cwd = Io.Dir.cwd();
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{wheel_path});
    defer allocator.free(tmp_path);
    writeWheelZip(allocator, io, mtime, dist_name, tmp_path, config, wheel_tag, module_path, module_name, stub_content) catch |err| {
        cwd.deleteFile(io, tmp_path) catch {};
        return err;
    };
    cwd.rename(tmp_path, cwd, wheel_path, io) catch |err| {
        cwd.deleteFile(io, tmp_path) catch {};
        return err;
    };
}

fn writeWheelZip(
    allocator: std.mem.Allocator,
    io: Io,
    mtime: ?i64,
    dist_name: []const u8,
    wheel_path: []const u8,
    config: *const project.toml.PyProjectConfig,
    wheel_tag: []const u8,
    module_path: []const u8,
    module_name: []const u8,
    stub_content: ?[]const u8,
) !void {
    const cwd = Io.Dir.cwd();

    // Create ZIP writer for the wheel (closed before the caller renames it)
    var z = try zip.ZipWriter.init(allocator, io, wheel_path, .{ .mtime = mtime });
    defer z.deinit();

    // Detect package mode: py-packages contains project name
    const is_package_mode = blk: {
        for (config.py_packages.items) |pkg| {
            if (std.mem.eql(u8, pkg, config.name)) break :blk true;
        }
        break :blk false;
    };

    // Add the compiled module
    // In package mode, place .so inside the package directory
    var wheel_module_name: ?[]const u8 = null;
    defer if (wheel_module_name) |wmn| allocator.free(wmn);

    if (is_package_mode) {
        wheel_module_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ config.name, module_name });
        try z.addFileFromDisk(wheel_module_name.?, module_path);
    } else {
        try z.addFileFromDisk(module_name, module_path);
    }

    // Add the .pyi stub file if provided (from memory content)
    var stub_name: ?[]const u8 = null;
    defer if (stub_name) |sn| allocator.free(sn);

    if (stub_content) |sc| {
        const mod_name = config.getModuleName();
        // In package mode, place .pyi inside the package directory
        if (is_package_mode) {
            stub_name = try std.fmt.allocPrint(allocator, "{s}/{s}.pyi", .{ config.name, mod_name });
        } else {
            stub_name = try std.fmt.allocPrint(allocator, "{s}.pyi", .{mod_name});
        }
        try z.addFile(stub_name.?, sc);
    }

    // Add pure Python packages
    var py_files: std.ArrayList([]const u8) = .empty;
    defer {
        for (py_files.items) |f| allocator.free(f);
        py_files.deinit(allocator);
    }

    for (config.py_packages.items) |pkg| {
        try addPythonPackage(allocator, io, &z, cwd, pkg, &py_files, config);
    }

    // Create dist-info directory name
    const dist_info_name = try std.fmt.allocPrint(allocator, "{s}-{s}.dist-info", .{ dist_name, config.getVersion() });
    defer allocator.free(dist_info_name);

    const wheel_content = try std.fmt.allocPrint(allocator,
        \\Wheel-Version: 1.0
        \\Generator: pyoz
        \\Root-Is-Purelib: false
        \\Tag: {s}
        \\
    , .{wheel_tag});
    defer allocator.free(wheel_content);

    const wheel_file_path = try std.fmt.allocPrint(allocator, "{s}/WHEEL", .{dist_info_name});
    defer allocator.free(wheel_file_path);
    try z.addFile(wheel_file_path, wheel_content);

    try addMetadata(allocator, io, &z, dist_info_name);

    // RECORD: every file with its sha256 and size (RECORD itself is unhashed)
    const record_file_path = try std.fmt.allocPrint(allocator, "{s}/RECORD", .{dist_info_name});
    defer allocator.free(record_file_path);

    var record_buf: std.ArrayList(u8) = .empty;
    defer record_buf.deinit(allocator);
    try z.appendRecord(&record_buf, record_file_path);

    try z.addFile(record_file_path, record_buf.items);

    // Finalize the ZIP file
    try z.finish();
}

/// METADATA, license files and entry_points.txt (see metadata.zig), shared
/// by regular and editable wheels.
fn addMetadata(allocator: std.mem.Allocator, io: Io, z: *zip.ZipWriter, dist_info: []const u8) !void {
    const cwd = Io.Dir.cwd();
    var md = try metadata.build(allocator, io, cwd);
    defer md.deinit(allocator);

    const meta_path = try std.fmt.allocPrint(allocator, "{s}/METADATA", .{dist_info});
    defer allocator.free(meta_path);
    try z.addFile(meta_path, md.text);

    for (md.license_files) |f| {
        const in_wheel = try std.fmt.allocPrint(allocator, "{s}/licenses/{s}", .{ dist_info, f });
        defer allocator.free(in_wheel);
        try z.addFileFromDisk(in_wheel, f);
    }
    if (md.entry_points) |ep| {
        const ep_path = try std.fmt.allocPrint(allocator, "{s}/entry_points.txt", .{dist_info});
        defer allocator.free(ep_path);
        try z.addFile(ep_path, ep);
    }
}

/// Build a PEP 660 editable wheel in `out_dir` and return its path (caller frees).
///
/// The extension is built in debug mode (or the pyproject `optimize` setting)
/// and stays in zig-out/; the wheel only contains a `__editable__.*.pth` file
/// that puts the build output directory (and, for Python packages, their
/// parent directory) on sys.path, plus standard dist-info. Rebuilding with
/// `zig build` / `pyoz develop` is picked up without reinstalling, and the
/// install is visible to `pip list` / removable with `pip uninstall`.
pub fn buildEditableWheel(ctx: Ctx, out_dir: []const u8) ![]const u8 {
    const allocator = ctx.gpa;
    const io = ctx.io;
    const cwd = Io.Dir.cwd();

    var config = try project.toml.loadPyProject(allocator, io);
    defer config.deinit(allocator);

    var build_result = try builder.buildModule(ctx, .{});
    defer build_result.deinit(allocator);

    const is_package_mode = for (config.py_packages.items) |pkg| {
        if (std.mem.eql(u8, pkg, config.name)) break true;
    } else false;

    // Package layout: the extension lives inside the package directory
    // (`from ._mod import *`), so link it there; rebuilds update the link.
    if (is_package_mode) {
        const src_candidate = try std.fmt.allocPrint(allocator, "src/{s}", .{config.name});
        defer allocator.free(src_candidate);
        const pkg_root = if (sys.exists(io, src_candidate)) "src/" else "";
        const in_pkg = try std.fmt.allocPrint(allocator, "{s}{s}/{s}", .{ pkg_root, config.name, build_result.module_name });
        defer allocator.free(in_pkg);
        var abs_buf: [Io.Dir.max_path_bytes]u8 = undefined;
        const abs_built = abs_buf[0..try cwd.realPathFile(io, build_result.module_path, &abs_buf)];
        cwd.deleteFile(io, in_pkg) catch {};
        if (builtin.os.tag == .windows) {
            try cwd.copyFile(build_result.module_path, cwd, in_pkg, io, .{});
        } else {
            try cwd.symLink(io, abs_built, in_pkg, .{});
        }
    }

    // Stubs next to the built module, for IDEs using the editable install.
    if (symreader.extractStubs(io, allocator, build_result.module_path) catch null) |stubs| {
        defer allocator.free(stubs);
        const out_dir_rel = Io.Dir.path.dirname(build_result.module_path) orelse ".";
        const pyi = try std.fmt.allocPrint(allocator, "{s}/{s}.pyi", .{ out_dir_rel, config.getModuleName() });
        defer allocator.free(pyi);
        cwd.writeFile(io, .{ .sub_path = pyi, .data = stubs }) catch {};
    }

    // .pth lines: absolute directories to add to sys.path.
    var pth: std.ArrayList(u8) = .empty;
    defer pth.deinit(allocator);
    var abs_buf: [Io.Dir.max_path_bytes]u8 = undefined;
    if (!is_package_mode) {
        const mod_dir = Io.Dir.path.dirname(build_result.module_path) orelse ".";
        try pth.print(allocator, "{s}\n", .{abs_buf[0..try cwd.realPathFile(io, mod_dir, &abs_buf)]});
    }
    for (config.py_packages.items) |pkg| {
        const src_pkg = try std.fmt.allocPrint(allocator, "src/{s}", .{pkg});
        defer allocator.free(src_pkg);
        const root = if (sys.exists(io, src_pkg)) "src" else ".";
        const line = abs_buf[0..try cwd.realPathFile(io, root, &abs_buf)];
        if (std.mem.indexOf(u8, pth.items, line) == null) try pth.print(allocator, "{s}\n", .{line});
    }

    const dist_name = try normalizeDistName(allocator, config.name);
    defer allocator.free(dist_name);
    const version = config.getVersion();

    cwd.createDirPath(io, out_dir) catch {};
    const wheel_path = try std.fmt.allocPrint(allocator, "{s}/{s}-{s}-py3-none-any.whl", .{ out_dir, dist_name, version });
    errdefer allocator.free(wheel_path);
    cwd.deleteFile(io, wheel_path) catch {};

    var z = try zip.ZipWriter.init(allocator, io, wheel_path, .{});
    defer z.deinit();

    const pth_name = try std.fmt.allocPrint(allocator, "__editable__.{s}-{s}.pth", .{ dist_name, version });
    defer allocator.free(pth_name);
    try z.addFile(pth_name, pth.items);

    const dist_info = try std.fmt.allocPrint(allocator, "{s}-{s}.dist-info", .{ dist_name, version });
    defer allocator.free(dist_info);
    try addMetadata(allocator, io, &z, dist_info);
    const wheel_meta_path = try std.fmt.allocPrint(allocator, "{s}/WHEEL", .{dist_info});
    defer allocator.free(wheel_meta_path);
    try z.addFile(wheel_meta_path,
        \\Wheel-Version: 1.0
        \\Generator: pyoz
        \\Root-Is-Purelib: true
        \\Tag: py3-none-any
        \\
    );
    const record_path = try std.fmt.allocPrint(allocator, "{s}/RECORD", .{dist_info});
    defer allocator.free(record_path);
    var record: std.ArrayList(u8) = .empty;
    defer record.deinit(allocator);
    try z.appendRecord(&record, record_path);
    try z.addFile(record_path, record.items);
    try z.finish();

    return wheel_path;
}

/// Wheel/dist-info names must be normalized: runs of '-', '_' and '.' become a
/// single '_' and the result is lowercased (PEP 427 / binary distribution format).
fn normalizeDistName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, name.len);
    errdefer out.deinit(allocator);
    var prev_sep = false;
    for (name) |c| {
        if (c == '-' or c == '_' or c == '.') {
            if (!prev_sep) out.appendAssumeCapacity('_');
            prev_sep = true;
        } else {
            out.appendAssumeCapacity(std.ascii.toLower(c));
            prev_sep = false;
        }
    }
    return out.toOwnedSlice(allocator);
}

/// True if `filename` is a wheel for exactly this project name and version.
/// The "-" after the version keeps "1.0" from matching "1.0.1" wheels.
fn isWheelFor(allocator: std.mem.Allocator, filename: []const u8, name: []const u8, version: []const u8) !bool {
    const dist_name = try normalizeDistName(allocator, name);
    defer allocator.free(dist_name);
    const prefix = try std.fmt.allocPrint(allocator, "{s}-{s}-", .{ dist_name, version });
    defer allocator.free(prefix);
    return std.mem.startsWith(u8, filename, prefix) and std.mem.endsWith(u8, filename, ".whl");
}

test isWheelFor {
    const a = std.testing.allocator;
    try std.testing.expect(try isWheelFor(a, "my_pkg-1.0-cp312-cp312-linux_x86_64.whl", "My-Pkg", "1.0"));
    try std.testing.expect(try isWheelFor(a, "my_pkg-1.0-cp314-cp314t-linux_x86_64.whl", "my.pkg", "1.0"));
    try std.testing.expect(!try isWheelFor(a, "my_pkg-1.0.1-cp312-cp312-linux_x86_64.whl", "my-pkg", "1.0"));
    try std.testing.expect(!try isWheelFor(a, "my_pkg-0.9-cp312-cp312-linux_x86_64.whl", "my-pkg", "1.0"));
    try std.testing.expect(!try isWheelFor(a, "my_pkg_extra-1.0-cp312-cp312-linux_x86_64.whl", "my-pkg", "1.0"));
    try std.testing.expect(!try isWheelFor(a, "my_pkg-1.0.tar.gz", "my-pkg", "1.0"));
}

test normalizeDistName {
    const n = try normalizeDistName(std.testing.allocator, "My-Cool..Pkg");
    defer std.testing.allocator.free(n);
    try std.testing.expectEqualStrings("my_cool_pkg", n);
}

/// Recursively add files from a package directory to the wheel.
/// File extensions are filtered by the include-ext config (defaults to .py only).
fn addPythonPackage(
    allocator: std.mem.Allocator,
    io: Io,
    z: *zip.ZipWriter,
    cwd: Io.Dir,
    pkg_name: []const u8,
    py_files: *std.ArrayList([]const u8),
    config: *const project.toml.PyProjectConfig,
) !void {
    // Try src-layout first (src/<pkg_name>/), then flat layout (<pkg_name>/)
    const src_path = try std.fmt.allocPrint(allocator, "src/{s}", .{pkg_name});
    defer allocator.free(src_path);

    const is_src_layout = sys.exists(io, src_path);
    const disk_prefix = if (is_src_layout) src_path else pkg_name;

    var pkg_dir = cwd.openDir(io, disk_prefix, .{ .iterate = true }) catch |err| {
        std.debug.print("  Warning: Python package directory '{s}' not found (tried 'src/{s}' and '{s}'): {}\n", .{ pkg_name, pkg_name, pkg_name, err });
        return;
    };
    defer pkg_dir.close(io);

    var walker = try pkg_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!config.shouldIncludeFile(entry.basename)) continue;

        // Build the in-wheel path: pkg_name/subdir/file.py (always flat in wheel).
        // ZIP entries must use '/', but the walker yields native separators ('\\' on Windows).
        const wheel_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ pkg_name, entry.path });
        if (builtin.os.tag == .windows) std.mem.replaceScalar(u8, wheel_path, '\\', '/');

        // Build the disk path relative to cwd (may be src/<pkg>/ or <pkg>/)
        const disk_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ disk_prefix, entry.path });
        defer allocator.free(disk_path);

        std.debug.print("  Adding Python file: {s}\n", .{wheel_path});
        try z.addFileFromDisk(wheel_path, disk_path);
        try py_files.append(allocator, wheel_path);
    }
}

/// Publish wheel(s) to PyPI or TestPyPI
pub fn publish(ctx: Ctx, test_pypi: bool) !void {
    const allocator = ctx.gpa;
    const io = ctx.io;
    const repo = if (test_pypi) pypi.Repository.testpypi else pypi.Repository.pypi;

    std.debug.print("Publishing to {s}...\n\n", .{repo.name});

    // Load project config
    var config = project.toml.loadPyProject(allocator, io) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found.\n", .{});
            return err;
        }
        return err;
    };
    defer config.deinit(allocator);

    // Get credentials
    const creds = pypi.getCredentials(allocator, ctx.environ, repo) catch |err| {
        if (err == error.NoCredentials) return err;
        return err;
    };
    defer allocator.free(creds.username);
    defer allocator.free(creds.password);

    // Find wheel files in dist/
    var dist_dir = Io.Dir.cwd().openDir(io, "dist", .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: No dist/ directory. Run 'pyoz build' first.\n", .{});
            return error.NoDistDir;
        }
        return err;
    };
    defer dist_dir.close(io);

    // Collect wheel files
    var wheels: std.ArrayList([]const u8) = .empty;
    defer {
        for (wheels.items) |w| allocator.free(w);
        wheels.deinit(allocator);
    }

    // Only upload wheels for *this* name and version: dist/ often still holds
    // wheels from earlier versions, which PyPI rejects with HTTP 400.
    var skipped: usize = 0;
    var iter = dist_dir.iterate();
    while (try iter.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".whl")) continue;
        if (!try isWheelFor(allocator, entry.name, config.name, config.getVersion())) {
            skipped += 1;
            continue;
        }
        const wheel_path = try std.fmt.allocPrint(allocator, "dist/{s}", .{entry.name});
        try wheels.append(allocator, wheel_path);
    }

    if (wheels.items.len == 0) {
        std.debug.print("Error: No wheels for {s} {s} in dist/", .{ config.name, config.getVersion() });
        if (skipped > 0) std.debug.print(" ({d} wheel(s) for other versions were ignored)", .{skipped});
        std.debug.print(". Run 'pyoz build' first.\n", .{});
        return error.NoWheels;
    }
    if (skipped > 0) {
        std.debug.print("Ignoring {d} wheel(s) in dist/ that are not {s} {s}\n", .{ skipped, config.name, config.getVersion() });
    }

    std.debug.print("Found {d} wheel(s) to upload:\n", .{wheels.items.len});
    for (wheels.items) |w| {
        std.debug.print("  {s}\n", .{w});
    }
    std.debug.print("\n", .{});

    // Upload each wheel
    for (wheels.items) |wheel_path| {
        try pypi.uploadWheel(allocator, io, wheel_path, repo, creds.username, creds.password);
    }

    std.debug.print("\nSuccessfully published to {s}!\n", .{repo.name});

    if (test_pypi) {
        std.debug.print("View at: https://test.pypi.org/project/{s}/\n", .{config.name});
        std.debug.print("Install with: pip install -i https://test.pypi.org/simple/ {s}\n", .{config.name});
    } else {
        std.debug.print("View at: https://pypi.org/project/{s}/\n", .{config.name});
        std.debug.print("Install with: pip install {s}\n", .{config.name});
    }
}
