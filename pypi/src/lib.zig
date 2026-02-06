const std = @import("std");
const pyoz = @import("PyOZ");
const version = @import("version");

const project = @import("project.zig");
const builder = @import("builder.zig");
const wheel = @import("wheel.zig");

fn init_project(name: ?[]const u8, in_current_dir: ?bool, local_pyoz_path: ?[]const u8) !void {
    try project.create(std.heap.page_allocator, name, in_current_dir orelse false, local_pyoz_path);
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
        pyoz.func("version", get_version, "Get PyOZ version string"),
    },
    .consts = &.{
        pyoz.constant("__version__", version.string),
    },
});

pub export fn PyInit__pyoz() ?*pyoz.PyObject {
    return PyOZCli.init();
}
