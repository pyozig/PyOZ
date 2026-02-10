//! Module operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const PyModuleDef = types.PyModuleDef;

// ============================================================================
// Module creation
// ============================================================================

pub inline fn PyModule_Create(def: *PyModuleDef) ?*PyObject {
    return c.PyModule_Create2(def, c.PYTHON_API_VERSION);
}

pub inline fn PyModule_AddObject(module: *PyObject, name: [*:0]const u8, value: *PyObject) c_int {
    return c.PyModule_AddObject(module, name, value);
}

pub inline fn PyModule_AddIntConstant(module: *PyObject, name: [*:0]const u8, value: c_long) c_int {
    return c.PyModule_AddIntConstant(module, name, value);
}

pub inline fn PyModule_AddStringConstant(module: *PyObject, name: [*:0]const u8, value: [*:0]const u8) c_int {
    return c.PyModule_AddStringConstant(module, name, value);
}

pub inline fn PyModule_AddType(module: *PyObject, type_obj: *PyTypeObject) c_int {
    // PyModule_AddType was added in Python 3.9 but may not be in Limited API
    // Use PyModule_AddObject as fallback
    if (@hasDecl(c, "PyModule_AddType")) {
        return c.PyModule_AddType(module, type_obj);
    } else {
        // Fallback: use PyModule_AddObject with type name
        // First get the type name
        const name = type_obj.tp_name orelse return -1;
        // PyModule_AddObject steals a reference on success, so incref first
        c.Py_IncRef(@ptrCast(type_obj));
        const result = c.PyModule_AddObject(module, name, @ptrCast(type_obj));
        if (result < 0) {
            // Failed, so decref to undo our incref
            c.Py_DecRef(@ptrCast(type_obj));
        }
        return result;
    }
}

/// Initialize a module definition for multi-phase initialization (PEP 489)
pub inline fn PyModuleDef_Init(def: *PyModuleDef) ?*PyObject {
    return c.PyModuleDef_Init(def);
}

/// Get the dictionary of a module
pub inline fn PyModule_GetDict(module: *PyObject) ?*PyObject {
    return c.PyModule_GetDict(module);
}
