//! What a built extension module requires from the system it runs on, read
//! from the binary itself (ELF, Mach-O or PE). The wheel's platform tag is
//! derived from this, so it is correct however the module was built (custom
//! build.zig, linked C libraries, a different Zig target), the way auditwheel
//! and delocate check wheels.

const std = @import("std");
const Io = std.Io;
const elf = std.elf;

pub const Arch = enum { x86_64, aarch64 };

pub const Version = struct {
    major: u32,
    minor: u32,

    pub fn order(a: Version, b: Version) std.math.Order {
        if (a.major != b.major) return std.math.order(a.major, b.major);
        return std.math.order(a.minor, b.minor);
    }
};

pub const Info = union(enum) {
    elf: Elf,
    macho: MachO,
    pe: Arch,

    pub const Elf = struct {
        arch: Arch,
        /// Highest GLIBC_x.y symbol version referenced (null: none).
        glibc: ?Version = null,
        /// First DT_NEEDED library outside the manylinux allowlist.
        disallowed_lib: ?[]const u8 = null,
    };

    pub const MachO = struct {
        arch: Arch,
        /// Minimum macOS version (LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX).
        min_os: ?Version = null,
    };
};

/// Libraries a manylinux wheel may link dynamically (PEP 599/600 policy, as
/// enforced by auditwheel); anything else must be bundled.
const manylinux_libs = [_][]const u8{
    "libc.so.6",             "libm.so.6",           "libdl.so.2",
    "librt.so.1",            "libpthread.so.0",     "libutil.so.1",
    "libnsl.so.1",           "libresolv.so.2",      "libcrypt.so.1",
    "libgcc_s.so.1",         "libstdc++.so.6",      "ld-linux-x86-64.so.2",
    "ld-linux-aarch64.so.1", "libX11.so.6",         "libXext.so.6",
    "libXrender.so.1",       "libICE.so.6",         "libSM.so.6",
    "libGL.so.1",            "libgobject-2.0.so.0", "libgthread-2.0.so.0",
    "libglib-2.0.so.0",
};

pub const Error = error{ UnsupportedBinary, Truncated };

/// Inspect `bytes` (a whole module file). Slices in the result point into `bytes`.
pub fn inspect(bytes: []const u8) Error!Info {
    if (bytes.len >= 4 and std.mem.eql(u8, bytes[0..4], elf.MAGIC)) return .{ .elf = try inspectElf(bytes) };
    if (bytes.len >= 4 and std.mem.readInt(u32, bytes[0..4], .little) == 0xFEEDFACF) return .{ .macho = try inspectMachO(bytes) };
    if (bytes.len >= 2 and bytes[0] == 'M' and bytes[1] == 'Z') return .{ .pe = try inspectPe(bytes) };
    return error.UnsupportedBinary;
}

fn read(comptime T: type, bytes: []const u8, off: u64) Error!T {
    const end = std.math.add(u64, off, @sizeOf(T)) catch return error.Truncated;
    if (end > bytes.len) return error.Truncated;
    return std.mem.bytesToValue(T, bytes[@intCast(off)..@intCast(end)]);
}

fn cstr(bytes: []const u8, off: u64) Error![]const u8 {
    if (off >= bytes.len) return error.Truncated;
    const s = bytes[@intCast(off)..];
    return s[0 .. std.mem.indexOfScalar(u8, s, 0) orelse return error.Truncated];
}

fn inspectElf(bytes: []const u8) Error!Info.Elf {
    // Wheels only target 64-bit little-endian (x86_64, aarch64)
    if (bytes.len < @sizeOf(elf.Elf64_Ehdr) or bytes[elf.EI.CLASS] != elf.ELFCLASS64 or bytes[elf.EI.DATA] != elf.ELFDATA2LSB)
        return error.UnsupportedBinary;
    const eh = try read(elf.Elf64_Ehdr, bytes, 0);
    var info: Info.Elf = .{ .arch = switch (eh.e_machine) {
        .X86_64 => .x86_64,
        .AARCH64 => .aarch64,
        else => return error.UnsupportedBinary,
    } };

    var i: u64 = 0;
    while (i < eh.e_shnum) : (i += 1) {
        const sh = try read(elf.Elf64_Shdr, bytes, eh.e_shoff + i * eh.e_shentsize);
        switch (sh.sh_type) {
            elf.SHT_GNU_VERNEED => {
                const strtab = try read(elf.Elf64_Shdr, bytes, eh.e_shoff + @as(u64, sh.sh_link) * eh.e_shentsize);
                var vn_off = sh.sh_offset;
                var remaining = sh.sh_info; // number of Verneed entries
                while (remaining > 0) : (remaining -= 1) {
                    const vn = try read(elf.Elf64_Verneed, bytes, vn_off);
                    var aux_off = vn_off + vn.vn_aux;
                    var n: u32 = 0;
                    while (n < vn.vn_cnt) : (n += 1) {
                        const aux = try read(elf.Vernaux, bytes, aux_off);
                        if (parseGlibc(try cstr(bytes, strtab.sh_offset + aux.name))) |v| {
                            if (info.glibc == null or v.order(info.glibc.?) == .gt) info.glibc = v;
                        }
                        aux_off += aux.next;
                    }
                    if (vn.vn_next == 0) break;
                    vn_off += vn.vn_next;
                }
            },
            elf.SHT_DYNAMIC => {
                const strtab = try read(elf.Elf64_Shdr, bytes, eh.e_shoff + @as(u64, sh.sh_link) * eh.e_shentsize);
                var off = sh.sh_offset;
                while (off + @sizeOf(elf.Elf64_Dyn) <= sh.sh_offset + sh.sh_size) : (off += @sizeOf(elf.Elf64_Dyn)) {
                    const dyn = try read(elf.Elf64_Dyn, bytes, off);
                    if (dyn.d_tag == elf.DT_NULL) break;
                    if (dyn.d_tag != elf.DT_NEEDED) continue;
                    const lib = try cstr(bytes, strtab.sh_offset + dyn.d_val);
                    if (info.disallowed_lib == null and !isManylinuxLib(lib)) info.disallowed_lib = lib;
                }
            },
            else => {},
        }
    }
    return info;
}

fn isManylinuxLib(name: []const u8) bool {
    for (manylinux_libs) |l| if (std.mem.eql(u8, l, name)) return true;
    return false;
}

/// "GLIBC_2.17" -> 2.17 (GLIBC_PRIVATE and other version names -> null)
fn parseGlibc(name: []const u8) ?Version {
    const rest = if (std.mem.startsWith(u8, name, "GLIBC_")) name["GLIBC_".len..] else return null;
    var it = std.mem.splitScalar(u8, rest, '.');
    const major = std.fmt.parseInt(u32, it.next() orelse return null, 10) catch return null;
    const minor = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch return null;
    return .{ .major = major, .minor = minor };
}

fn inspectMachO(bytes: []const u8) Error!Info.MachO {
    const Header = extern struct { magic: u32, cputype: u32, cpusubtype: u32, filetype: u32, ncmds: u32, sizeofcmds: u32, flags: u32, reserved: u32 };
    const h = try read(Header, bytes, 0);
    var info: Info.MachO = .{ .arch = switch (h.cputype) {
        0x01000007 => .x86_64,
        0x0100000C => .aarch64,
        else => return error.UnsupportedBinary,
    } };
    const LC_VERSION_MIN_MACOSX = 0x24;
    const LC_BUILD_VERSION = 0x32;
    var off: u64 = @sizeOf(Header);
    var n: u32 = 0;
    while (n < h.ncmds) : (n += 1) {
        const cmd = try read(u32, bytes, off);
        const size = try read(u32, bytes, off + 4);
        switch (cmd) {
            // build_version_command: cmd, cmdsize, platform, minos, ...
            LC_BUILD_VERSION => info.min_os = decodeMachOVersion(try read(u32, bytes, off + 12)),
            // version_min_command: cmd, cmdsize, version, sdk
            LC_VERSION_MIN_MACOSX => info.min_os = decodeMachOVersion(try read(u32, bytes, off + 8)),
            else => {},
        }
        if (size == 0) return error.Truncated;
        off += size;
    }
    return info;
}

/// Mach-O versions are xxxx.yy.zz nibble-encoded: 13.0.0 = 0x000D0000
fn decodeMachOVersion(v: u32) Version {
    return .{ .major = v >> 16, .minor = (v >> 8) & 0xff };
}

fn inspectPe(bytes: []const u8) Error!Arch {
    const pe_off = try read(u32, bytes, 0x3c);
    if (!std.mem.eql(u8, &(try read([4]u8, bytes, pe_off)), "PE\x00\x00")) return error.UnsupportedBinary;
    return switch (try read(u16, bytes, pe_off + 4)) {
        0x8664 => .x86_64,
        0xAA64 => .aarch64,
        else => error.UnsupportedBinary,
    };
}

pub const ImportSlotConstants = struct {
    count: usize = 0,
    /// Imported symbol of the first one found (points into the module bytes)
    first: ?[]const u8 = null,
};

/// Windows modules: constants in the data sections that hold the address of
/// an import slot. Data of the Python DLL (None, the PyExc_* objects, the
/// type objects) must be read through its slot at run time; if the compiler
/// treats the address as known at link time it can place it in a constant
/// (a switch's table of results), and the linker fills that with the slot's
/// address: the module then hands out the slot as if it were the object.
pub fn importSlotConstants(bytes: []const u8) Error!ImportSlotConstants {
    const pe = try read(u32, bytes, 0x3c);
    if (!std.mem.eql(u8, &(try read([4]u8, bytes, pe)), "PE\x00\x00")) return error.UnsupportedBinary;
    const nsec = try read(u16, bytes, pe + 6);
    const opt = pe + 24;
    const opt_size = try read(u16, bytes, pe + 20);
    if (try read(u16, bytes, opt) != 0x20b) return error.UnsupportedBinary; // PE32+ only
    const image_base = try read(u64, bytes, opt + 24);
    // Data directories: 1 = import table, 12 = import address table
    const imports_rva = try read(u32, bytes, opt + 112 + 1 * 8);
    const iat_rva = try read(u32, bytes, opt + 112 + 12 * 8);
    const iat_size = try read(u32, bytes, opt + 112 + 12 * 8 + 4);
    if (iat_size == 0) return .{};

    const Section = struct { name: [8]u8, vsize: u32, va: u32, rsize: u32, raw: u32 };
    const sectionAt = struct {
        fn get(b: []const u8, at: u64) Error!Section {
            return .{
                .name = try read([8]u8, b, at),
                .vsize = try read(u32, b, at + 8),
                .va = try read(u32, b, at + 12),
                .rsize = try read(u32, b, at + 16),
                .raw = try read(u32, b, at + 20),
            };
        }
    }.get;
    const sections = opt + opt_size;

    var result: ImportSlotConstants = .{};
    var first_slot: ?u64 = null;
    var i: u64 = 0;
    while (i < nsec) : (i += 1) {
        const s = try sectionAt(bytes, sections + 40 * i);
        const name = std.mem.sliceTo(&s.name, 0);
        // Code, unwind data and base relocations legitimately refer to slots
        if (std.mem.eql(u8, name, ".text") or std.mem.eql(u8, name, ".pdata") or std.mem.eql(u8, name, ".reloc")) continue;
        const len = @min(s.vsize, s.rsize);
        var off: u64 = 0;
        while (off + 8 <= len) : (off += 8) {
            const rva = s.va + off;
            if (rva >= iat_rva and rva < iat_rva + iat_size) continue; // the table itself
            const value = try read(u64, bytes, s.raw + off);
            if (value < image_base) continue;
            const target = value - image_base;
            if (target >= iat_rva and target < iat_rva + iat_size) {
                result.count += 1;
                if (first_slot == null) first_slot = target;
            }
        }
    }

    // Name the first one: find its slot among the import descriptors
    if (first_slot) |slot| {
        const rvaToOffset = struct {
            fn get(b: []const u8, secs: u64, n: u16, rva: u64) Error!u64 {
                var k: u64 = 0;
                while (k < n) : (k += 1) {
                    const s = try sectionAt(b, secs + 40 * k);
                    if (rva >= s.va and rva < s.va + @max(s.vsize, s.rsize)) return s.raw + (rva - s.va);
                }
                return error.Truncated;
            }
        }.get;
        var desc = try rvaToOffset(bytes, sections, nsec, imports_rva);
        while (true) : (desc += 20) {
            const lookup = try read(u32, bytes, desc);
            const dll_name = try read(u32, bytes, desc + 12);
            const first_thunk = try read(u32, bytes, desc + 16);
            if (dll_name == 0) break;
            if (slot < first_thunk) continue;
            const index = (slot - first_thunk) / 8;
            const entries = try rvaToOffset(bytes, sections, nsec, if (lookup != 0) lookup else first_thunk);
            // The slot must belong to this DLL's table (null-terminated)
            var j: u64 = 0;
            while (j <= index) : (j += 1) {
                if (try read(u64, bytes, entries + 8 * j) == 0) break;
            } else {
                const entry = try read(u64, bytes, entries + 8 * index);
                if (entry >> 63 == 0) result.first = try cstr(bytes, try rvaToOffset(bytes, sections, nsec, (entry & 0x7fffffff) + 2));
                break;
            }
        }
    }
    return result;
}

/// Oldest glibc a manylinux tag is produced for: manylinux2014, the oldest
/// policy current pip and PyPI treat as mainstream (modules that need less
/// still get this tag, which remains accurate).
pub const min_glibc: Version = .{ .major = 2, .minor = 17 };

pub const Tag = struct {
    /// e.g. "manylinux_2_17_x86_64", "macosx_13_0_arm64", "win_amd64"
    text: []u8,
    /// Why the module cannot get a portable (PyPI-accepted) tag, if it can't.
    not_portable: ?[]const u8 = null,
};

/// The wheel platform tag the module described by `info` qualifies for.
pub fn platformTag(gpa: std.mem.Allocator, info: Info) !Tag {
    switch (info) {
        .elf => |e| {
            const arch = @tagName(e.arch);
            if (e.disallowed_lib) |lib| return .{
                .text = try std.fmt.allocPrint(gpa, "linux_{s}", .{arch}),
                .not_portable = try std.fmt.allocPrint(gpa, "it links {s}, which manylinux wheels may not depend on", .{lib}),
            };
            const g = if (e.glibc) |v| (if (v.order(min_glibc) == .lt) min_glibc else v) else min_glibc;
            return .{ .text = try std.fmt.allocPrint(gpa, "manylinux_{d}_{d}_{s}", .{ g.major, g.minor, arch }) };
        },
        .macho => |m| {
            const arch = switch (m.arch) {
                .x86_64 => "x86_64",
                .aarch64 => "arm64",
            };
            const v = m.min_os orelse Version{ .major = 11, .minor = 0 };
            // pip only generates macosx_N_0 tags for macOS 11 and later, so a
            // minor version there would make the wheel uninstallable.
            const minor = if (v.major >= 11) 0 else v.minor;
            return .{ .text = try std.fmt.allocPrint(gpa, "macosx_{d}_{d}_{s}", .{ v.major, minor, arch }) };
        },
        .pe => |arch| return .{ .text = try gpa.dupe(u8, switch (arch) {
            .x86_64 => "win_amd64",
            .aarch64 => "win_arm64",
        }) },
    }
}

/// Read the module at `path` and compute its platform tag.
pub fn platformTagOfFile(gpa: std.mem.Allocator, io: Io, path: []const u8) !Tag {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(512 * 1024 * 1024));
    defer gpa.free(bytes);
    const info = try inspect(bytes);
    // Copy the one slice that points into `bytes` before freeing it
    var tag = try platformTag(gpa, info);
    errdefer gpa.free(tag.text);
    if (tag.not_portable) |np| {
        const owned = try gpa.dupe(u8, np);
        gpa.free(np);
        tag.not_portable = owned;
    }
    return tag;
}

test parseGlibc {
    try std.testing.expectEqual(Version{ .major = 2, .minor = 17 }, parseGlibc("GLIBC_2.17").?);
    try std.testing.expectEqual(Version{ .major = 2, .minor = 2 }, parseGlibc("GLIBC_2.2.5").?);
    try std.testing.expect(parseGlibc("GLIBC_PRIVATE") == null);
    try std.testing.expect(parseGlibc("GCC_3.0") == null);
}

test platformTag {
    const gpa = std.testing.allocator;
    const cases = .{
        .{ Info{ .elf = .{ .arch = .x86_64, .glibc = .{ .major = 2, .minor = 3 } } }, "manylinux_2_17_x86_64" },
        .{ Info{ .elf = .{ .arch = .aarch64, .glibc = .{ .major = 2, .minor = 34 } } }, "manylinux_2_34_aarch64" },
        .{ Info{ .macho = .{ .arch = .aarch64, .min_os = .{ .major = 14, .minor = 5 } } }, "macosx_14_0_arm64" },
        .{ Info{ .macho = .{ .arch = .x86_64, .min_os = .{ .major = 10, .minor = 13 } } }, "macosx_10_13_x86_64" },
        .{ Info{ .pe = .aarch64 }, "win_arm64" },
    };
    inline for (cases) |c| {
        const t = try platformTag(gpa, c[0]);
        defer gpa.free(t.text);
        try std.testing.expectEqualStrings(c[1], t.text);
        try std.testing.expect(t.not_portable == null);
    }
    const bad = try platformTag(gpa, .{ .elf = .{ .arch = .x86_64, .disallowed_lib = "libpython3.12.so.1.0" } });
    defer gpa.free(bad.text);
    defer gpa.free(bad.not_portable.?);
    try std.testing.expectEqualStrings("linux_x86_64", bad.text);
}
