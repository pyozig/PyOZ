//! Python C API bindings via @cImport
//!
//! This module imports the Python C API from the system headers.
//! The correct Python version is determined at build time based on
//! which Python headers are provided to the compiler.

// ============================================================================
// Sub-modules
// ============================================================================

pub const types = @import("types.zig");
pub const slots = @import("slots.zig");
pub const refcount = @import("refcount.zig");
pub const singletons = @import("singletons.zig");
pub const typecheck = @import("typecheck.zig");
pub const numeric = @import("numeric.zig");
pub const string = @import("string.zig");
pub const tuple = @import("tuple.zig");
pub const list = @import("list.zig");
pub const dict = @import("dict.zig");
pub const set = @import("set.zig");
pub const iterator = @import("iterator.zig");
pub const object = @import("object.zig");
pub const type_ops = @import("type.zig");
pub const module_ops = @import("module.zig");
pub const error_ops = @import("error.zig");
pub const datetime = @import("datetime.zig");
pub const buffer = @import("buffer.zig");
pub const gil = @import("gil.zig");
pub const bytes = @import("bytes.zig");
pub const path = @import("path.zig");
pub const embed = @import("embed.zig");

// ============================================================================
// Re-export the raw C API
// ============================================================================

pub const c = types.c;

// ============================================================================
// Re-export essential types
// ============================================================================

pub const PyObject = types.PyObject;
pub const Py_ssize_t = types.Py_ssize_t;
pub const PyTypeObject = types.PyTypeObject;
pub const PyMethodDef = types.PyMethodDef;
pub const PyCFunction = types.PyCFunction;
pub const PyMemberDef = types.PyMemberDef;
pub const PyGetSetDef = types.PyGetSetDef;
pub const getter = types.getter;
pub const setter = types.setter;
pub const PyType_Slot = types.PyType_Slot;
pub const PyType_Spec = types.PyType_Spec;
pub const PyModuleDef = types.PyModuleDef;
pub const PyModuleDef_Base = types.PyModuleDef_Base;
pub const PyModuleDef_HEAD_INIT = types.PyModuleDef_HEAD_INIT;
pub const PySequenceMethods = types.PySequenceMethods;
pub const PyMappingMethods = types.PyMappingMethods;

// Method flags
pub const METH_VARARGS = types.METH_VARARGS;
pub const METH_KEYWORDS = types.METH_KEYWORDS;
pub const METH_NOARGS = types.METH_NOARGS;
pub const METH_O = types.METH_O;
pub const METH_STATIC = types.METH_STATIC;
pub const METH_CLASS = types.METH_CLASS;

// Type flags
pub const Py_TPFLAGS_DEFAULT = types.Py_TPFLAGS_DEFAULT;
pub const Py_TPFLAGS_HAVE_GC = types.Py_TPFLAGS_HAVE_GC;
pub const Py_TPFLAGS_BASETYPE = types.Py_TPFLAGS_BASETYPE;
pub const Py_TPFLAGS_HEAPTYPE = types.Py_TPFLAGS_HEAPTYPE;

// Type slots
pub const Py_tp_init = types.Py_tp_init;
pub const Py_tp_new = types.Py_tp_new;
pub const Py_tp_dealloc = types.Py_tp_dealloc;
pub const Py_tp_methods = types.Py_tp_methods;
pub const Py_tp_members = types.Py_tp_members;
pub const Py_tp_getset = types.Py_tp_getset;
pub const Py_tp_doc = types.Py_tp_doc;
pub const Py_tp_repr = types.Py_tp_repr;
pub const Py_tp_str = types.Py_tp_str;

// ============================================================================
// Re-export reference counting
// ============================================================================

pub const Py_IncRef = refcount.Py_IncRef;
pub const Py_DecRef = refcount.Py_DecRef;

// ============================================================================
// Re-export singletons
// ============================================================================

pub const Py_None = singletons.Py_None;
pub const Py_True = singletons.Py_True;
pub const Py_False = singletons.Py_False;
pub const Py_RETURN_NONE = singletons.Py_RETURN_NONE;
pub const Py_RETURN_TRUE = singletons.Py_RETURN_TRUE;
pub const Py_RETURN_FALSE = singletons.Py_RETURN_FALSE;
pub const Py_RETURN_BOOL = singletons.Py_RETURN_BOOL;
pub const Py_NotImplemented = singletons.Py_NotImplemented;

// ============================================================================
// Re-export type checking
// ============================================================================

pub const Py_TYPE = typecheck.Py_TYPE;
pub const PyLong_Check = typecheck.PyLong_Check;
pub const PyFloat_Check = typecheck.PyFloat_Check;
pub const PyUnicode_Check = typecheck.PyUnicode_Check;
pub const PyBool_Check = typecheck.PyBool_Check;
pub const PyNone_Check = typecheck.PyNone_Check;
pub const PyTuple_Check = typecheck.PyTuple_Check;
pub const PyList_Check = typecheck.PyList_Check;
pub const PyDict_Check = typecheck.PyDict_Check;
pub const PySet_Check = typecheck.PySet_Check;
pub const PyFrozenSet_Check = typecheck.PyFrozenSet_Check;
pub const PyAnySet_Check = typecheck.PyAnySet_Check;
pub const PyBytes_Check = typecheck.PyBytes_Check;
pub const PyByteArray_Check = typecheck.PyByteArray_Check;
pub const PyObject_TypeCheck = typecheck.PyObject_TypeCheck;
pub const PyCallable_Check = typecheck.PyCallable_Check;

// ============================================================================
// Re-export numeric operations
// ============================================================================

pub const PyLong_FromLongLong = numeric.PyLong_FromLongLong;
pub const PyLong_FromString = numeric.PyLong_FromString;
pub const PyLong_FromUnsignedLongLong = numeric.PyLong_FromUnsignedLongLong;
pub const PyFloat_FromDouble = numeric.PyFloat_FromDouble;
pub const PyComplex_FromDoubles = numeric.PyComplex_FromDoubles;
pub const PyComplex_RealAsDouble = numeric.PyComplex_RealAsDouble;
pub const PyComplex_ImagAsDouble = numeric.PyComplex_ImagAsDouble;
pub const PyComplex_Check = numeric.PyComplex_Check;
pub const PyBool_FromLong = numeric.PyBool_FromLong;
pub const PyLong_AsLongLong = numeric.PyLong_AsLongLong;
pub const PyLong_AsUnsignedLongLong = numeric.PyLong_AsUnsignedLongLong;
pub const PyLong_AsDouble = numeric.PyLong_AsDouble;
pub const PyFloat_AsDouble = numeric.PyFloat_AsDouble;

// ============================================================================
// Re-export string operations
// ============================================================================

pub const PyUnicode_FromString = string.PyUnicode_FromString;
pub const PyUnicode_FromStringAndSize = string.PyUnicode_FromStringAndSize;
pub const PyUnicode_AsUTF8 = string.PyUnicode_AsUTF8;
pub const PyUnicode_AsUTF8AndSize = string.PyUnicode_AsUTF8AndSize;
pub const PyUnicode_Concat = string.PyUnicode_Concat;
pub const PyUnicode_FromFormat = string.PyUnicode_FromFormat;

// ============================================================================
// Re-export tuple operations
// ============================================================================

pub const PyTuple_Size = tuple.PyTuple_Size;
pub const PyTuple_GetItem = tuple.PyTuple_GetItem;
pub const PyTuple_New = tuple.PyTuple_New;
pub const PyTuple_SetItem = tuple.PyTuple_SetItem;
pub const PyTuple_Pack = tuple.PyTuple_Pack;

// ============================================================================
// Re-export list operations
// ============================================================================

pub const PyList_New = list.PyList_New;
pub const PyList_Size = list.PyList_Size;
pub const PyList_GetItem = list.PyList_GetItem;
pub const PyList_SetItem = list.PyList_SetItem;
pub const PyList_Append = list.PyList_Append;
pub const PyList_SetSlice = list.PyList_SetSlice;
pub const PyList_Insert = list.PyList_Insert;

// ============================================================================
// Re-export dict operations
// ============================================================================

pub const PyDict_New = dict.PyDict_New;
pub const PyDict_SetItemString = dict.PyDict_SetItemString;
pub const PyDict_GetItemString = dict.PyDict_GetItemString;
pub const PyDict_Size = dict.PyDict_Size;
pub const PyDict_Keys = dict.PyDict_Keys;
pub const PyDict_Values = dict.PyDict_Values;
pub const PyDict_Items = dict.PyDict_Items;
pub const PyDict_SetItem = dict.PyDict_SetItem;
pub const PyDict_GetItem = dict.PyDict_GetItem;
pub const PyDict_Next = dict.PyDict_Next;

// ============================================================================
// Re-export set operations
// ============================================================================

pub const PySet_New = set.PySet_New;
pub const PyFrozenSet_New = set.PyFrozenSet_New;
pub const PySet_Size = set.PySet_Size;
pub const PySet_Contains = set.PySet_Contains;
pub const PySet_Add = set.PySet_Add;
pub const PySet_Discard = set.PySet_Discard;
pub const PySet_Pop = set.PySet_Pop;
pub const PySet_Clear = set.PySet_Clear;

// ============================================================================
// Re-export iterator operations
// ============================================================================

pub const PyObject_GetIter = iterator.PyObject_GetIter;
pub const PyIter_Next = iterator.PyIter_Next;
pub const PySequence_List = iterator.PySequence_List;

// ============================================================================
// Re-export object operations
// ============================================================================

pub const PyObject_Init = object.PyObject_Init;
pub const PyObject_New = object.PyObject_New;
pub const PyObject_Del = object.PyObject_Del;
pub const PyObject_ClearWeakRefs = object.PyObject_ClearWeakRefs;
pub const PyObject_Repr = object.PyObject_Repr;
pub const PyObject_Str = object.PyObject_Str;
pub const PyObject_CallObject = object.PyObject_CallObject;
pub const PyObject_Call = object.PyObject_Call;
pub const PyObject_SetAttrString = object.PyObject_SetAttrString;
pub const PyObject_GenericGetAttr = object.PyObject_GenericGetAttr;
pub const PyObject_GenericSetAttr = object.PyObject_GenericSetAttr;
pub const PyObject_IsTrue = object.PyObject_IsTrue;
pub const PyObject_GetAttr = object.PyObject_GetAttr;
pub const PyObject_GetAttrString = object.PyObject_GetAttrString;
pub const PyObject_SetAttr = object.PyObject_SetAttr;
pub const PyObject_IsInstance = object.PyObject_IsInstance;
pub const PyObject_CallFunction = object.PyObject_CallFunction;

// ============================================================================
// Re-export type operations
// ============================================================================

pub const PyType_FromSpec = type_ops.PyType_FromSpec;
pub const PyType_Ready = type_ops.PyType_Ready;
pub const PyType_GenericAlloc = type_ops.PyType_GenericAlloc;
pub const PyType_GenericNew = type_ops.PyType_GenericNew;

// ============================================================================
// Re-export module operations
// ============================================================================

pub const PyModule_Create = module_ops.PyModule_Create;
pub const PyModuleDef_Init = module_ops.PyModuleDef_Init;
pub const PyModule_AddObject = module_ops.PyModule_AddObject;
pub const PyModule_AddIntConstant = module_ops.PyModule_AddIntConstant;
pub const PyModule_AddStringConstant = module_ops.PyModule_AddStringConstant;
pub const PyModule_AddType = module_ops.PyModule_AddType;
pub const PyModule_GetDict = module_ops.PyModule_GetDict;

// ============================================================================
// Re-export error operations
// ============================================================================

pub const PyErr_SetString = error_ops.PyErr_SetString;
pub const PyErr_Occurred = error_ops.PyErr_Occurred;
pub const PyErr_Clear = error_ops.PyErr_Clear;
pub const PyErr_ExceptionMatches = error_ops.PyErr_ExceptionMatches;
pub const PyErr_Fetch = error_ops.PyErr_Fetch;
pub const PyErr_Restore = error_ops.PyErr_Restore;
pub const PyErr_NormalizeException = error_ops.PyErr_NormalizeException;
pub const PyErr_GivenExceptionMatches = error_ops.PyErr_GivenExceptionMatches;
pub const PyErr_SetObject = error_ops.PyErr_SetObject;
pub const PyErr_GetExcInfo = error_ops.PyErr_GetExcInfo;
pub const PyErr_NewException = error_ops.PyErr_NewException;
pub const PyErr_Print = error_ops.PyErr_Print;
pub const PyErr_CheckSignals = error_ops.PyErr_CheckSignals;
pub const PyExc_RuntimeError = error_ops.PyExc_RuntimeError;
pub const PyExc_TypeError = error_ops.PyExc_TypeError;
pub const PyExc_ValueError = error_ops.PyExc_ValueError;
pub const PyExc_AttributeError = error_ops.PyExc_AttributeError;
pub const PyExc_IndexError = error_ops.PyExc_IndexError;
pub const PyExc_KeyError = error_ops.PyExc_KeyError;
pub const PyExc_ZeroDivisionError = error_ops.PyExc_ZeroDivisionError;
pub const PyExc_StopIteration = error_ops.PyExc_StopIteration;
pub const PyExc_Exception = error_ops.PyExc_Exception;
pub const PyExc_ArithmeticError = error_ops.PyExc_ArithmeticError;
pub const PyExc_LookupError = error_ops.PyExc_LookupError;
pub const PyExc_AssertionError = error_ops.PyExc_AssertionError;
pub const PyExc_BufferError = error_ops.PyExc_BufferError;
pub const PyExc_EOFError = error_ops.PyExc_EOFError;
pub const PyExc_FileExistsError = error_ops.PyExc_FileExistsError;
pub const PyExc_FileNotFoundError = error_ops.PyExc_FileNotFoundError;
pub const PyExc_FloatingPointError = error_ops.PyExc_FloatingPointError;
pub const PyExc_ImportError = error_ops.PyExc_ImportError;
pub const PyExc_ModuleNotFoundError = error_ops.PyExc_ModuleNotFoundError;
pub const PyExc_IsADirectoryError = error_ops.PyExc_IsADirectoryError;
pub const PyExc_MemoryError = error_ops.PyExc_MemoryError;
pub const PyExc_NotADirectoryError = error_ops.PyExc_NotADirectoryError;
pub const PyExc_NotImplementedError = error_ops.PyExc_NotImplementedError;
pub const PyExc_OSError = error_ops.PyExc_OSError;
pub const PyExc_OverflowError = error_ops.PyExc_OverflowError;
pub const PyExc_PermissionError = error_ops.PyExc_PermissionError;
pub const PyExc_ProcessLookupError = error_ops.PyExc_ProcessLookupError;
pub const PyExc_RecursionError = error_ops.PyExc_RecursionError;
pub const PyExc_SystemError = error_ops.PyExc_SystemError;
pub const PyExc_TimeoutError = error_ops.PyExc_TimeoutError;
pub const PyExc_UnicodeDecodeError = error_ops.PyExc_UnicodeDecodeError;
pub const PyExc_UnicodeEncodeError = error_ops.PyExc_UnicodeEncodeError;
pub const PyExc_UnicodeError = error_ops.PyExc_UnicodeError;
pub const PyExc_ConnectionError = error_ops.PyExc_ConnectionError;
pub const PyExc_ConnectionAbortedError = error_ops.PyExc_ConnectionAbortedError;
pub const PyExc_ConnectionRefusedError = error_ops.PyExc_ConnectionRefusedError;
pub const PyExc_ConnectionResetError = error_ops.PyExc_ConnectionResetError;
pub const PyExc_BlockingIOError = error_ops.PyExc_BlockingIOError;
pub const PyExc_BrokenPipeError = error_ops.PyExc_BrokenPipeError;
pub const PyExc_ChildProcessError = error_ops.PyExc_ChildProcessError;
pub const PyExc_InterruptedError = error_ops.PyExc_InterruptedError;
pub const PyExc_SystemExit = error_ops.PyExc_SystemExit;
pub const PyExc_KeyboardInterrupt = error_ops.PyExc_KeyboardInterrupt;
pub const PyExc_BaseException = error_ops.PyExc_BaseException;
pub const PyExc_GeneratorExit = error_ops.PyExc_GeneratorExit;
pub const PyExc_NameError = error_ops.PyExc_NameError;
pub const PyExc_UnboundLocalError = error_ops.PyExc_UnboundLocalError;
pub const PyExc_ReferenceError = error_ops.PyExc_ReferenceError;
pub const PyExc_StopAsyncIteration = error_ops.PyExc_StopAsyncIteration;
pub const PyExc_SyntaxError = error_ops.PyExc_SyntaxError;
pub const PyExc_IndentationError = error_ops.PyExc_IndentationError;
pub const PyExc_TabError = error_ops.PyExc_TabError;
pub const PyExc_UnicodeTranslateError = error_ops.PyExc_UnicodeTranslateError;
pub const PyExc_Warning = error_ops.PyExc_Warning;
pub const PyExc_BytesWarning = error_ops.PyExc_BytesWarning;
pub const PyExc_DeprecationWarning = error_ops.PyExc_DeprecationWarning;
pub const PyExc_FutureWarning = error_ops.PyExc_FutureWarning;
pub const PyExc_ImportWarning = error_ops.PyExc_ImportWarning;
pub const PyExc_PendingDeprecationWarning = error_ops.PyExc_PendingDeprecationWarning;
pub const PyExc_ResourceWarning = error_ops.PyExc_ResourceWarning;
pub const PyExc_RuntimeWarning = error_ops.PyExc_RuntimeWarning;
pub const PyExc_SyntaxWarning = error_ops.PyExc_SyntaxWarning;
pub const PyExc_UnicodeWarning = error_ops.PyExc_UnicodeWarning;
pub const PyExc_UserWarning = error_ops.PyExc_UserWarning;

// ============================================================================
// Re-export datetime operations
// ============================================================================

pub const PyDateTime_Import = datetime.PyDateTime_Import;
pub const PyDateTime_IsInitialized = datetime.PyDateTime_IsInitialized;
pub const PyDate_FromDate = datetime.PyDate_FromDate;
pub const PyDateTime_FromDateAndTime = datetime.PyDateTime_FromDateAndTime;
pub const PyTime_FromTime = datetime.PyTime_FromTime;
pub const PyDelta_FromDSU = datetime.PyDelta_FromDSU;
pub const PyDate_Check = datetime.PyDate_Check;
pub const PyDateTime_Check = datetime.PyDateTime_Check;
pub const PyTime_Check = datetime.PyTime_Check;
pub const PyDelta_Check = datetime.PyDelta_Check;
pub const PyDateTime_GET_YEAR = datetime.PyDateTime_GET_YEAR;
pub const PyDateTime_GET_MONTH = datetime.PyDateTime_GET_MONTH;
pub const PyDateTime_GET_DAY = datetime.PyDateTime_GET_DAY;
pub const PyDateTime_DATE_GET_HOUR = datetime.PyDateTime_DATE_GET_HOUR;
pub const PyDateTime_DATE_GET_MINUTE = datetime.PyDateTime_DATE_GET_MINUTE;
pub const PyDateTime_DATE_GET_SECOND = datetime.PyDateTime_DATE_GET_SECOND;
pub const PyDateTime_DATE_GET_MICROSECOND = datetime.PyDateTime_DATE_GET_MICROSECOND;
pub const PyDateTime_TIME_GET_HOUR = datetime.PyDateTime_TIME_GET_HOUR;
pub const PyDateTime_TIME_GET_MINUTE = datetime.PyDateTime_TIME_GET_MINUTE;
pub const PyDateTime_TIME_GET_SECOND = datetime.PyDateTime_TIME_GET_SECOND;
pub const PyDateTime_TIME_GET_MICROSECOND = datetime.PyDateTime_TIME_GET_MICROSECOND;
pub const PyDateTime_DELTA_GET_DAYS = datetime.PyDateTime_DELTA_GET_DAYS;
pub const PyDateTime_DELTA_GET_SECONDS = datetime.PyDateTime_DELTA_GET_SECONDS;
pub const PyDateTime_DELTA_GET_MICROSECONDS = datetime.PyDateTime_DELTA_GET_MICROSECONDS;

// ============================================================================
// Re-export buffer protocol
// ============================================================================

pub const Py_buffer = buffer.Py_buffer;
pub const PyBufferProcs = buffer.PyBufferProcs;
pub const PyBUF_SIMPLE = buffer.PyBUF_SIMPLE;
pub const PyBUF_WRITABLE = buffer.PyBUF_WRITABLE;
pub const PyBUF_FORMAT = buffer.PyBUF_FORMAT;
pub const PyBUF_ND = buffer.PyBUF_ND;
pub const PyBUF_STRIDES = buffer.PyBUF_STRIDES;
pub const PyBUF_C_CONTIGUOUS = buffer.PyBUF_C_CONTIGUOUS;
pub const PyBUF_F_CONTIGUOUS = buffer.PyBUF_F_CONTIGUOUS;
pub const PyBUF_ANY_CONTIGUOUS = buffer.PyBUF_ANY_CONTIGUOUS;
pub const PyBUF_FULL = buffer.PyBUF_FULL;
pub const PyBUF_FULL_RO = buffer.PyBUF_FULL_RO;
pub const PyBuffer_FillInfo = buffer.PyBuffer_FillInfo;
pub const PyObject_GetBuffer = buffer.PyObject_GetBuffer;
pub const PyBuffer_Release = buffer.PyBuffer_Release;
pub const PyObject_CheckBuffer = buffer.PyObject_CheckBuffer;

// ============================================================================
// Re-export GIL operations
// ============================================================================

pub const PyThreadState = gil.PyThreadState;
pub const PyGILState_STATE = gil.PyGILState_STATE;
pub const PyEval_SaveThread = gil.PyEval_SaveThread;
pub const PyEval_RestoreThread = gil.PyEval_RestoreThread;
pub const PyGILState_Ensure = gil.PyGILState_Ensure;
pub const PyGILState_Release = gil.PyGILState_Release;

// ============================================================================
// Re-export bytes operations
// ============================================================================

pub const PyBytes_FromStringAndSize = bytes.PyBytes_FromStringAndSize;
pub const PyBytes_AsStringAndSize = bytes.PyBytes_AsStringAndSize;
pub const PyBytes_Size = bytes.PyBytes_Size;
pub const PyBytes_AsString = bytes.PyBytes_AsString;
pub const PyByteArray_FromStringAndSize = bytes.PyByteArray_FromStringAndSize;
pub const PyByteArray_AsString = bytes.PyByteArray_AsString;
pub const PyByteArray_Size = bytes.PyByteArray_Size;

// ============================================================================
// Re-export path operations
// ============================================================================

pub const PyPath_FromString = path.PyPath_FromString;
pub const PyPath_Check = path.PyPath_Check;
pub const PyPath_AsString = path.PyPath_AsString;
pub const PyPath_AsStringWithRef = path.PyPath_AsStringWithRef;
pub const PathStringResult = path.PathStringResult;

// ============================================================================
// Re-export embedding API
// ============================================================================

pub const Py_single_input = embed.Py_single_input;
pub const Py_file_input = embed.Py_file_input;
pub const Py_eval_input = embed.Py_eval_input;
pub const Py_Initialize = embed.Py_Initialize;
pub const Py_InitializeEx = embed.Py_InitializeEx;
pub const Py_IsInitialized = embed.Py_IsInitialized;
pub const Py_Finalize = embed.Py_Finalize;
pub const Py_FinalizeEx = embed.Py_FinalizeEx;
pub const PyRun_SimpleString = embed.PyRun_SimpleString;
pub const PyRun_String = embed.PyRun_String;
pub const PyImport_AddModule = embed.PyImport_AddModule;
pub const PyImport_ImportModule = embed.PyImport_ImportModule;
pub const PyMain_GetGlobal = embed.PyMain_GetGlobal;
pub const PyMain_SetGlobal = embed.PyMain_SetGlobal;
pub const PyEval_Expression = embed.PyEval_Expression;
pub const PyExec_Statements = embed.PyExec_Statements;
