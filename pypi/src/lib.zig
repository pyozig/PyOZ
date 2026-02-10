const std = @import("std");
const pyoz = @import("PyOZ");
const version = @import("version");

const project = @import("project.zig");
const builder = @import("builder.zig");
const commands = @import("commands.zig");
const wheel = @import("wheel.zig");

fn init_project(name: ?[]const u8, in_current_dir: ?bool, local_pyoz_path: ?[]const u8, package_layout: ?bool) !void {
    try project.create(std.heap.page_allocator, name, in_current_dir orelse false, local_pyoz_path, package_layout orelse false);
}

fn build_wheel(release: ?bool, stubs: ?bool) ![]const u8 {
    // Use page_allocator: the wheel path string must outlive this function
    // because PyOZ's wrapper calls toPy() on the returned slice after we return.
    // Internal allocations from buildWheel are leaked but they're small and one-shot.
    const alloc = std.heap.page_allocator;
    return try wheel.buildWheel(alloc, release orelse false, stubs orelse true);
}

fn develop_mode() !void {
    try builder.developMode(std.heap.page_allocator);
}

fn publish_wheels(test_pypi: ?bool) !void {
    try wheel.publish(std.heap.page_allocator, test_pypi orelse false);
}

fn run_tests(release: ?bool, verbose: ?bool) !void {
    var args_buf: [2][]const u8 = undefined;
    var args_len: usize = 0;
    if (release orelse false) {
        args_buf[args_len] = "--release";
        args_len += 1;
    }
    if (verbose orelse false) {
        args_buf[args_len] = "--verbose";
        args_len += 1;
    }
    try commands.runTests(std.heap.page_allocator, args_buf[0..args_len]);
}

fn run_bench() !void {
    const args = [_][]const u8{};
    try commands.runBench(std.heap.page_allocator, &args);
}

fn get_version() []const u8 {
    return version.string;
}

const PyOZCli = pyoz.module(.{
    .name = "_pyoz",
    .doc = "PyOZ native CLI library - build Python extensions in Zig",
    .classes = &.{},
    .funcs = &.{
        pyoz.kwfunc("init", init_project, "Create a new PyOZ project"),
        pyoz.kwfunc("build", build_wheel, "Build extension module and create wheel"),
        pyoz.func("develop", develop_mode, "Build and install in development mode"),
        pyoz.kwfunc("publish", publish_wheels, "Publish wheel(s) to PyPI"),
        pyoz.kwfunc("run_tests", run_tests, "Run embedded tests"),
        pyoz.func("run_bench", run_bench, "Run embedded benchmarks"),
        pyoz.func("version", get_version, "Get PyOZ version string"),
    },
    .consts = &.{
        pyoz.constant("__version__", version.string),
    },
});

pub export fn PyInit__pyoz() ?*pyoz.PyObject {
    return PyOZCli.init();
}
