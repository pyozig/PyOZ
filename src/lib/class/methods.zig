//! Method wrapper generation for class generation
//!
//! Generates Python method wrappers for instance methods, static methods, and class methods

const std = @import("std");
const py = @import("../python.zig");
const ft = @import("threading.zig");
const conversion = @import("../conversion.zig");
const Path = conversion.Path;

const unwrapSignature = @import("../root.zig").unwrapSignature;
const unwrapSignatureValue = @import("../root.zig").unwrapSignatureValue;
const stubs_mod = @import("../stubs.zig");
const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;
const source_parser = @import("../source_parser.zig");
const errors_mod = @import("../errors.zig");
const awaitable = @import("../awaitable.zig");
const async_mod = @import("async.zig");
const accessors = @import("accessors.zig");
const wrappers_mod = @import("../wrappers.zig");

/// Build method wrappers for a given type
pub fn MethodBuilder(comptime class_name: [*:0]const u8, comptime T: type, comptime PyWrapper: type, comptime class_infos: []const ClassInfo, comptime slot_dunders: []const []const u8) type {
    const struct_info = @typeInfo(T).@"struct";
    const decls = struct_info.decls;

    return struct {
        const Self = @This();

        // Pre-parsed source data for comptime source parsing (looked up from class_infos)
        const class_source: ?source_parser.ParsedSource = class_mod.lookupParsedSource(class_infos, T);
        const class_struct_name: []const u8 = std.mem.span(class_name);

        // ====================================================================
        // Method counting and detection
        // ====================================================================

        /// Check if a declaration is handled by a protocol slot or is a
        /// non-function dunder (constant/type). The slot_dunders list is
        /// provided by mod.zig and contains only the dunders T actually
        /// declares. The branch quota is shared by the whole evaluation that
        /// calls this (once per declaration), hence the maximum. Other dunders
        /// like __enter__, __exit__, __missing__ pass through as regular methods.
        fn isSlotDunder(comptime decl_name: []const u8) bool {
            @setEvalBranchQuota(std.math.maxInt(u32));
            // Non-function declarations (__doc__, __base__, __features__, etc.)
            if (@hasDecl(T, decl_name) and @typeInfo(@TypeOf(@field(T, decl_name))) != .@"fn")
                return true;
            inline for (slot_dunders) |d| {
                if (comptime std.mem.eql(u8, decl_name, d)) return true;
            }
            return false;
        }

        pub fn countMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isInstanceMethod(decl.name)) count += 1;
            }
            return count;
        }

        pub fn countStaticMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isStaticMethod(decl.name)) count += 1;
            }
            return count;
        }

        pub fn countClassMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isClassMethod(decl.name)) count += 1;
            }
            return count;
        }

        const has_class_getitem = @hasDecl(T, "__class_getitem__") and @TypeOf(@field(T, "__class_getitem__")) == bool and @field(T, "__class_getitem__") == true;

        pub fn totalMethodCount() usize {
            return countMethods() + countStaticMethods() + countClassMethods() + (if (has_class_getitem) @as(usize, 1) else 0);
        }

        fn isInstanceMethod(comptime decl_name: []const u8) bool {
            // Skip dunders handled by protocol slots
            if (isSlotDunder(decl_name)) return false;
            // Skip get_X/set_X used as property getters/setters
            if (accessors.isAccessor(T, decl_name)) return false;
            // Check if this is a public function that takes self
            if (!@hasDecl(T, decl_name)) return false;
            const decl = @field(T, decl_name);
            const DeclType = @TypeOf(decl);
            const decl_info = @typeInfo(DeclType);

            if (decl_info != .@"fn") return false;

            const fn_info = decl_info.@"fn";
            if (fn_info.params.len == 0) return false;

            // Check if first param is self (*T, *const T, or T)
            const FirstParam = fn_info.params[0].type orelse return false;
            const first_info = @typeInfo(FirstParam);

            if (first_info == .pointer) {
                const child = first_info.pointer.child;
                if (child == T) return true;
            }
            if (FirstParam == T) return true;

            return false;
        }

        fn isStaticMethod(comptime decl_name: []const u8) bool {
            // Skip dunders handled by protocol slots
            if (isSlotDunder(decl_name)) return false;
            // Check if this is a public function that does NOT take self or cls
            if (!@hasDecl(T, decl_name)) return false;

            // Exclude class methods
            if (isClassMethod(decl_name)) return false;

            const decl = @field(T, decl_name);
            const DeclType = @TypeOf(decl);
            const decl_info = @typeInfo(DeclType);

            if (decl_info != .@"fn") return false;

            const fn_info = decl_info.@"fn";

            // No parameters - static method
            if (fn_info.params.len == 0) return true;

            // Has parameters but first is not self - static method
            const FirstParam = fn_info.params[0].type orelse return true;
            const first_info = @typeInfo(FirstParam);

            if (first_info == .pointer) {
                const child = first_info.pointer.child;
                if (child == T) return false; // Instance method
            }
            if (FirstParam == T) return false; // Instance method

            return true; // Static method
        }

        fn isClassMethod(comptime decl_name: []const u8) bool {
            // Skip dunders handled by protocol slots
            if (isSlotDunder(decl_name)) return false;
            // Class methods have `comptime cls: type` as first parameter
            if (!@hasDecl(T, decl_name)) return false;
            const decl = @field(T, decl_name);
            const DeclType = @TypeOf(decl);
            const decl_info = @typeInfo(DeclType);

            if (decl_info != .@"fn") return false;

            const fn_info = decl_info.@"fn";
            if (fn_info.params.len == 0) return false;

            // Check if first param is `type` (comptime cls: type)
            const FirstParam = fn_info.params[0].type orelse return false;
            return FirstParam == type;
        }

        const Kind = enum { instance, static, class };

        /// Index of the first Python-visible parameter (after `self` / `cls`).
        fn firstVisible(comptime kind: Kind) usize {
            return if (kind == .static) 0 else 1;
        }

        /// Whether a method takes keyword arguments through `pyoz.Args(S)`,
        /// which must then be its only Python-visible parameter.
        fn takesArgs(comptime method_name: []const u8, comptime kind: Kind) bool {
            const params = @typeInfo(@TypeOf(@field(T, method_name))).@"fn".params;
            const first = firstVisible(kind);
            for (params[first..], first..) |p, i| {
                if (wrappers_mod.isArgs(p.type.?)) {
                    if (i != first or params.len != first + 1) @compileError(@typeName(T) ++ "." ++ method_name ++
                        ": pyoz.Args(...) must be the only parameter" ++ (if (kind == .static) "" else " after `" ++ (if (kind == .class) "cls" else "self") ++ "`") ++
                        "; put the other parameters in the Args struct");
                    return true;
                }
            }
            return false;
        }

        // ====================================================================
        // Docstring helpers
        // ====================================================================

        /// Get method docstring from method_name__doc__ declaration if it exists,
        /// falling back to source-parsed /// doc comment.
        pub fn getMethodDoc(comptime method_name: []const u8) ?[*:0]const u8 {
            const doc_name = method_name ++ "__doc__";
            if (@hasDecl(T, doc_name)) {
                const DocType = @TypeOf(@field(T, doc_name));
                if (DocType != [*:0]const u8) {
                    @compileError(doc_name ++ " must be declared as [*:0]const u8, e.g.: pub const " ++ doc_name ++ ": [*:0]const u8 = \"...\";");
                }
                return @field(T, doc_name);
            }
            // Fall back to source-parsed /// doc comment
            if (class_source) |src| {
                if (source_parser.getMethodDoc(src, class_struct_name, method_name)) |doc| {
                    return class_mod.comptimeStrZ(doc);
                }
            }
            return null;
        }

        /// Get method parameter names from method_name__params__ declaration if it exists,
        /// falling back to source-parsed function signature.
        fn getMethodParams(comptime method_name: []const u8) ?[]const u8 {
            const params_name = method_name ++ "__params__";
            if (@hasDecl(T, params_name)) {
                return stubs_mod.asSlice(@field(T, params_name));
            }
            // Fall back to source-parsed parameter names
            if (class_source) |src| {
                return source_parser.getMethodParams(src, class_struct_name, method_name);
            }
            return null;
        }

        // ====================================================================
        // Method array generation
        // ====================================================================

        const total_count = totalMethodCount();

        pub var methods: [total_count + 1]py.PyMethodDef = blk: {
            // Scales with the number of methods (signatures and docs are built here)
            @setEvalBranchQuota(std.math.maxInt(u32));
            var m: [total_count + 1]py.PyMethodDef = undefined;
            var idx: usize = 0;

            // Add instance methods
            for (decls) |decl| {
                if (isInstanceMethod(decl.name)) {
                    const kw = takesArgs(decl.name, .instance);
                    m[idx] = .{
                        .ml_name = @ptrCast(decl.name.ptr),
                        .ml_meth = if (kw)
                            @ptrCast(ft.locked(T, generateKeywordWrapper(decl.name, .instance)))
                        else
                            @ptrCast(ft.locked(T, generateMethodWrapper(decl.name))),
                        .ml_flags = py.METH_VARARGS | (if (kw) py.METH_KEYWORDS else 0),
                        .ml_doc = stubs_mod.buildMlDoc(
                            decl.name,
                            @TypeOf(@field(T, decl.name)),
                            .instance_method,
                            if (kw) .args_struct else .positional,
                            getMethodDoc(decl.name),
                            getMethodParams(decl.name),
                        ),
                    };
                    idx += 1;
                }
            }

            // Add static methods
            for (decls) |decl| {
                if (isStaticMethod(decl.name)) {
                    const kw = takesArgs(decl.name, .static);
                    m[idx] = .{
                        .ml_name = @ptrCast(decl.name.ptr),
                        .ml_meth = if (kw)
                            @ptrCast(generateKeywordWrapper(decl.name, .static))
                        else
                            @ptrCast(generateStaticMethodWrapper(decl.name)),
                        .ml_flags = py.METH_VARARGS | py.METH_STATIC | (if (kw) py.METH_KEYWORDS else 0),
                        .ml_doc = stubs_mod.buildMlDoc(
                            decl.name,
                            @TypeOf(@field(T, decl.name)),
                            .static_method,
                            if (kw) .args_struct else .positional,
                            getMethodDoc(decl.name),
                            getMethodParams(decl.name),
                        ),
                    };
                    idx += 1;
                }
            }

            // Add class methods
            for (decls) |decl| {
                if (isClassMethod(decl.name)) {
                    const kw = takesArgs(decl.name, .class);
                    m[idx] = .{
                        .ml_name = @ptrCast(decl.name.ptr),
                        .ml_meth = if (kw)
                            @ptrCast(generateKeywordWrapper(decl.name, .class))
                        else
                            @ptrCast(generateClassMethodWrapper(decl.name)),
                        .ml_flags = py.METH_VARARGS | py.METH_CLASS | (if (kw) py.METH_KEYWORDS else 0),
                        .ml_doc = stubs_mod.buildMlDoc(
                            decl.name,
                            @TypeOf(@field(T, decl.name)),
                            .class_method,
                            if (kw) .args_struct else .positional,
                            getMethodDoc(decl.name),
                            getMethodParams(decl.name),
                        ),
                    };
                    idx += 1;
                }
            }

            // __class_getitem__ - enables MyClass[T] syntax for generic types
            if (has_class_getitem) {
                m[idx] = .{
                    .ml_name = "__class_getitem__",
                    .ml_meth = @ptrCast(&classGetItemWrapper),
                    .ml_flags = py.METH_O | py.METH_CLASS,
                    .ml_doc = "See PEP 585",
                };
                idx += 1;
            }

            // Sentinel
            m[total_count] = .{
                .ml_name = null,
                .ml_meth = null,
                .ml_flags = 0,
                .ml_doc = null,
            };

            break :blk m;
        };

        /// __class_getitem__(cls, item) -> GenericAlias or cls
        /// Returns types.GenericAlias(cls, item) for proper runtime generics,
        /// or falls back to cls on older Python versions.
        fn classGetItemWrapper(cls: ?*py.PyObject, item: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const cls_obj = cls orelse return null;
            const item_obj = item orelse return null;

            // Try to create a proper GenericAlias via types.GenericAlias(cls, item)
            const types_mod = py.c.PyImport_ImportModule("types") orelse {
                // Fallback: return cls
                py.Py_IncRef(cls_obj);
                return cls_obj;
            };
            defer py.c.Py_DecRef(types_mod);

            const ga_type = py.c.PyObject_GetAttrString(types_mod, "GenericAlias") orelse {
                // Defensive: types.GenericAlias exists on every supported version (3.10+)
                py.c.PyErr_Clear();
                py.Py_IncRef(cls_obj);
                return cls_obj;
            };
            defer py.c.Py_DecRef(ga_type);

            const args = py.c.PyTuple_Pack(2, cls_obj, item_obj) orelse {
                py.Py_IncRef(cls_obj);
                return cls_obj;
            };
            defer py.c.Py_DecRef(args);

            return py.c.PyObject_Call(ga_type, args, null) orelse {
                // If GenericAlias construction fails, return cls
                py.c.PyErr_Clear();
                py.Py_IncRef(cls_obj);
                return cls_obj;
            };
        }

        // ====================================================================
        // Result conversion (shared by all method wrappers)
        // ====================================================================

        /// Convert a method's return value to a new Python reference, or null
        /// with an exception set. Errors map to exceptions unless Python already
        /// set one (e.g. KeyboardInterrupt from checkSignals); a null optional
        /// is None unless an exception is pending.
        fn plainResult(comptime R: type, result: R) ?*py.PyObject {
            const Conv = conversion.Converter(class_infos);
            switch (@typeInfo(R)) {
                .error_union => {
                    const value = result catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            py.PyErr_SetString(errors_mod.mapWellKnownError(msg), msg.ptr);
                        }
                        return null;
                    };
                    return Conv.toPy(@TypeOf(value), value);
                },
                .optional => {
                    if (result) |value| return Conv.toPy(@TypeOf(value), value);
                    if (py.PyErr_Occurred() != null) return null;
                    return py.Py_RETURN_NONE();
                },
                .void => return py.Py_RETURN_NONE(),
                else => return Conv.toPy(R, result),
            }
        }

        /// `plainResult` for instance methods, plus the `return self` pattern
        /// (a `*T` equal to self returns the same Python object) and the
        /// awaitables `__aenter__` / `__aexit__` must return.
        fn instanceResult(comptime method_name: []const u8, comptime R: type, result: R, self_obj: *py.PyObject, self_data: *T) ?*py.PyObject {
            if (comptime async_mod.isAsyncMethodDunder(method_name)) {
                return awaitable.toAwaitable(conversion.Converter(class_infos), T, R, result, .value, self_obj, self_data);
            }
            const info = @typeInfo(R);
            if (info == .error_union) {
                const value = result catch |err| return plainResult(R, err);
                return instanceResult(method_name, info.error_union.payload, value, self_obj, self_data);
            }
            // Only single-item pointers (*T / *const T), not slices ([]T)
            if (info == .pointer and info.pointer.size == .one and info.pointer.child == T) {
                const ptr: *const T = result;
                if (ptr == self_data) {
                    py.Py_IncRef(self_obj);
                    return self_obj;
                }
            }
            return plainResult(R, result);
        }

        // ====================================================================
        // Keyword-argument wrapper generation (methods taking pyoz.Args(S))
        // ====================================================================

        fn generateKeywordWrapper(comptime method_name: []const u8, comptime kind: Kind) wrappers_mod.PyCFunctionWithKeywords {
            const method = @field(T, method_name);
            const fn_info = @typeInfo(@TypeOf(method)).@"fn";
            const ArgsWrapper = fn_info.params[firstVisible(kind)].type.?;
            const ArgsStruct = ArgsWrapper.ArgsStruct;
            const RawReturnType = fn_info.return_type orelse void;
            const ReturnType = unwrapSignature(RawReturnType);

            return struct {
                fn wrapper(self_obj: ?*py.PyObject, args: ?*py.PyObject, kwargs: ?*py.PyObject) callconv(.c) ?*py.PyObject {
                    var parsed = wrappers_mod.parseNamedArgs(ArgsStruct, class_infos, method_name, args, kwargs) orelse return null;
                    defer wrappers_mod.releaseNamedArgs(ArgsStruct, &parsed);
                    const named: ArgsWrapper = .{ .value = parsed };

                    switch (kind) {
                        .instance => {
                            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                            const data = self.getData();
                            // `self` may be taken by value (T) or by pointer (*T / *const T)
                            const raw = if (fn_info.params[0].type.? == T) method(data.*, named) else method(data, named);
                            return instanceResult(method_name, ReturnType, unwrapSignatureValue(RawReturnType, raw), self_obj.?, data);
                        },
                        .static => return plainResult(ReturnType, unwrapSignatureValue(RawReturnType, method(named))),
                        .class => return plainResult(ReturnType, unwrapSignatureValue(RawReturnType, method(T, named))),
                    }
                }
            }.wrapper;
        }

        // ====================================================================
        // Instance method wrapper generation
        // ====================================================================

        fn generateMethodWrapper(comptime method_name: []const u8) *const fn (?*py.PyObject, ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const method = @field(T, method_name);
            const MethodType = @TypeOf(method);
            const fn_info = @typeInfo(MethodType).@"fn";
            const params = fn_info.params;
            const RawReturnType = fn_info.return_type orelse void;
            const ReturnType = unwrapSignature(RawReturnType);

            return struct {
                fn wrapper(self_obj: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));

                    // Build argument tuple for the method call
                    var extra_args = parseMethodArgs(args) catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                        }
                        return null;
                    };
                    // Ensure Path arguments are cleaned up after function call
                    defer releasePathArgs(&extra_args);

                    // Call method with self pointer and extra args
                    const raw_result = callMethod(self.getData(), extra_args);
                    const result = unwrapSignatureValue(RawReturnType, raw_result);

                    return instanceResult(method_name, ReturnType, result, self_obj.?, self.getData());
                }

                fn releasePathArgs(extra_args: *ExtraArgsTuple()) void {
                    inline for (1..params.len) |param_idx| {
                        const ParamType = params[param_idx].type.?;
                        if (ParamType == Path) {
                            extra_args[param_idx - 1].deinit();
                        }
                    }
                }

                fn parseMethodArgs(py_args: ?*py.PyObject) !ExtraArgsTuple() {
                    var result: ExtraArgsTuple() = undefined;
                    const extra_param_count = params.len - 1;

                    if (extra_param_count == 0) {
                        return result;
                    }

                    const args_tuple = py_args orelse return error.MissingArguments;
                    const arg_count = py.PyTuple_Size(args_tuple);

                    if (arg_count != extra_param_count) {
                        return error.WrongArgumentCount;
                    }

                    comptime var i: usize = 0;
                    inline for (1..params.len) |param_idx| {
                        const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                        // Use class-aware converter so methods can take cross-class parameters
                        const Conv = conversion.Converter(class_infos);
                        result[i] = try Conv.fromPy(params[param_idx].type.?, item);
                        i += 1;
                    }

                    return result;
                }

                fn ExtraArgsTuple() type {
                    if (params.len <= 1) return std.meta.Tuple(&[_]type{});
                    var types: [params.len - 1]type = undefined;
                    for (1..params.len) |i| {
                        types[i - 1] = params[i].type.?;
                    }
                    return std.meta.Tuple(&types);
                }

                fn callMethod(self_ptr: anytype, extra: ExtraArgsTuple()) RawReturnType {
                    // Build the full args with self as first parameter
                    if (params.len == 1) {
                        return @call(.auto, method, .{self_ptr});
                    } else {
                        return @call(.auto, method, .{self_ptr} ++ extra);
                    }
                }
            }.wrapper;
        }

        // ====================================================================
        // Static method wrapper generation
        // ====================================================================

        fn generateStaticMethodWrapper(comptime method_name: []const u8) *const fn (?*py.PyObject, ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const method = @field(T, method_name);
            const MethodType = @TypeOf(method);
            const fn_info = @typeInfo(MethodType).@"fn";
            const params = fn_info.params;
            const RawReturnType = fn_info.return_type orelse void;
            const ReturnType = unwrapSignature(RawReturnType);
            // Use a converter that knows about type T so we can return T instances
            const Conv = conversion.Converter(class_infos);

            return struct {
                fn wrapper(self_obj: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
                    // Static methods ignore self (it's NULL or the type object)
                    _ = self_obj;

                    // Parse all arguments (no self to skip)
                    var zig_args = parseArgs(args) catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                        }
                        return null;
                    };
                    // Ensure Path arguments are cleaned up after function call
                    defer releasePathArgs(&zig_args);

                    // Call static method
                    const raw_result = @call(.auto, method, zig_args);
                    const result = unwrapSignatureValue(@TypeOf(raw_result), raw_result);

                    // Handle return
                    return plainResult(ReturnType, result);
                }

                fn releasePathArgs(zig_args: *ArgsTuple()) void {
                    inline for (params, 0..) |param, i| {
                        if (param.type.? == Path) {
                            zig_args[i].deinit();
                        }
                    }
                }

                fn parseArgs(py_args: ?*py.PyObject) !ArgsTuple() {
                    var result: ArgsTuple() = undefined;

                    if (params.len == 0) {
                        return result;
                    }

                    const args_tuple = py_args orelse return error.MissingArguments;
                    const arg_count = py.PyTuple_Size(args_tuple);

                    if (arg_count != params.len) {
                        return error.WrongArgumentCount;
                    }

                    comptime var i: usize = 0;
                    inline for (params) |param| {
                        const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                        result[i] = try Conv.fromPy(param.type.?, item);
                        i += 1;
                    }

                    return result;
                }

                fn ArgsTuple() type {
                    if (params.len == 0) return std.meta.Tuple(&[_]type{});
                    var types: [params.len]type = undefined;
                    for (params, 0..) |param, i| {
                        types[i] = param.type.?;
                    }
                    return std.meta.Tuple(&types);
                }
            }.wrapper;
        }

        // ====================================================================
        // Class method wrapper generation
        // ====================================================================

        fn generateClassMethodWrapper(comptime method_name: []const u8) *const fn (?*py.PyObject, ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const method = @field(T, method_name);
            const MethodType = @TypeOf(method);
            const fn_info = @typeInfo(MethodType).@"fn";
            const params = fn_info.params;
            const RawReturnType = fn_info.return_type orelse void;
            const ReturnType = unwrapSignature(RawReturnType);
            // Use a converter that knows about type T so we can return T instances
            const Conv = conversion.Converter(class_infos);

            return struct {
                fn wrapper(cls_obj: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
                    // For class methods, cls_obj is the type object
                    // We pass the Zig type T to the method
                    _ = cls_obj;

                    // Parse arguments (skip the first `type` parameter)
                    var zig_args = parseArgs(args) catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                        }
                        return null;
                    };
                    // Ensure Path arguments are cleaned up after function call
                    defer releasePathArgs(&zig_args);

                    // Call class method with T as first argument, then the rest
                    const raw_result = @call(.auto, method, .{T} ++ zig_args);
                    const result = unwrapSignatureValue(@TypeOf(raw_result), raw_result);

                    // Handle return
                    return plainResult(ReturnType, result);
                }

                fn releasePathArgs(zig_args: *ArgsTuple()) void {
                    inline for (1..params.len) |param_idx| {
                        const ParamType = params[param_idx].type.?;
                        if (ParamType == Path) {
                            zig_args[param_idx - 1].deinit();
                        }
                    }
                }

                fn parseArgs(py_args: ?*py.PyObject) !ArgsTuple() {
                    var result: ArgsTuple() = undefined;
                    const extra_param_count = params.len - 1; // Skip the `type` param

                    if (extra_param_count == 0) {
                        return result;
                    }

                    const args_tuple = py_args orelse return error.MissingArguments;
                    const arg_count = py.PyTuple_Size(args_tuple);

                    if (arg_count != extra_param_count) {
                        return error.WrongArgumentCount;
                    }

                    comptime var i: usize = 0;
                    inline for (1..params.len) |param_idx| {
                        const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                        result[i] = try Conv.fromPy(params[param_idx].type.?, item);
                        i += 1;
                    }

                    return result;
                }

                fn ArgsTuple() type {
                    if (params.len <= 1) return std.meta.Tuple(&[_]type{});
                    var types: [params.len - 1]type = undefined;
                    for (1..params.len) |i| {
                        types[i - 1] = params[i].type.?;
                    }
                    return std.meta.Tuple(&types);
                }
            }.wrapper;
        }
    };
}
