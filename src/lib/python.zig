//! Python C API bindings via @cImport
//!
//! This module imports the Python C API from the system headers.
//! The correct Python version is determined at build time based on
//! which Python headers are provided to the compiler.
//!
//! This file re-exports from the modular python/ directory structure.

const mod = @import("python/mod.zig");

// Re-export sub-modules for direct access
pub const types = mod.types;
pub const slots = mod.slots;
pub const refcount = mod.refcount;
pub const singletons = mod.singletons;
pub const typecheck = mod.typecheck;
pub const numeric = mod.numeric;
pub const string = mod.string;
pub const tuple = mod.tuple;
pub const list = mod.list;
pub const dict = mod.dict;
pub const set = mod.set;
pub const iterator = mod.iterator;
pub const object = mod.object;
pub const type_ops = mod.type_ops;
pub const module_ops = mod.module_ops;
pub const error_ops = mod.error_ops;
pub const datetime = mod.datetime;
pub const buffer = mod.buffer;
pub const gil = mod.gil;
pub const bytes = mod.bytes;
pub const path = mod.path;
pub const embed = mod.embed;

// Re-export the raw C API
pub const c = mod.c;

// Re-export essential types
pub const PyObject = mod.PyObject;
pub const Py_ssize_t = mod.Py_ssize_t;
pub const PyTypeObject = mod.PyTypeObject;
pub const PyMethodDef = mod.PyMethodDef;
pub const PyCFunction = mod.PyCFunction;
pub const PyMemberDef = mod.PyMemberDef;
pub const PyGetSetDef = mod.PyGetSetDef;
pub const getter = mod.getter;
pub const setter = mod.setter;
pub const PyType_Slot = mod.PyType_Slot;
pub const PyType_Spec = mod.PyType_Spec;
pub const PyModuleDef = mod.PyModuleDef;
pub const PyModuleDef_Base = mod.PyModuleDef_Base;
pub const PyModuleDef_HEAD_INIT = mod.PyModuleDef_HEAD_INIT;
pub const PySequenceMethods = mod.PySequenceMethods;
pub const PyMappingMethods = mod.PyMappingMethods;

// Method flags
pub const METH_VARARGS = mod.METH_VARARGS;
pub const METH_KEYWORDS = mod.METH_KEYWORDS;
pub const METH_NOARGS = mod.METH_NOARGS;
pub const METH_O = mod.METH_O;
pub const METH_STATIC = mod.METH_STATIC;
pub const METH_CLASS = mod.METH_CLASS;

// Type flags
pub const Py_TPFLAGS_DEFAULT = mod.Py_TPFLAGS_DEFAULT;
pub const Py_TPFLAGS_HAVE_GC = mod.Py_TPFLAGS_HAVE_GC;
pub const Py_TPFLAGS_BASETYPE = mod.Py_TPFLAGS_BASETYPE;
pub const Py_TPFLAGS_HEAPTYPE = mod.Py_TPFLAGS_HEAPTYPE;

// Type slots
pub const Py_tp_init = mod.Py_tp_init;
pub const Py_tp_new = mod.Py_tp_new;
pub const Py_tp_dealloc = mod.Py_tp_dealloc;
pub const Py_tp_methods = mod.Py_tp_methods;
pub const Py_tp_members = mod.Py_tp_members;
pub const Py_tp_getset = mod.Py_tp_getset;
pub const Py_tp_doc = mod.Py_tp_doc;
pub const Py_tp_repr = mod.Py_tp_repr;
pub const Py_tp_str = mod.Py_tp_str;

// Reference counting
pub const Py_IncRef = mod.Py_IncRef;
pub const Py_DecRef = mod.Py_DecRef;

// Singletons
pub const Py_None = mod.Py_None;
pub const Py_True = mod.Py_True;
pub const Py_False = mod.Py_False;
pub const Py_RETURN_NONE = mod.Py_RETURN_NONE;
pub const Py_RETURN_TRUE = mod.Py_RETURN_TRUE;
pub const Py_RETURN_FALSE = mod.Py_RETURN_FALSE;
pub const Py_RETURN_BOOL = mod.Py_RETURN_BOOL;
pub const Py_NotImplemented = mod.Py_NotImplemented;

// Type checking
pub const Py_TYPE = mod.Py_TYPE;
pub const PyLong_Check = mod.PyLong_Check;
pub const PyFloat_Check = mod.PyFloat_Check;
pub const PyUnicode_Check = mod.PyUnicode_Check;
pub const PyBool_Check = mod.PyBool_Check;
pub const PyNone_Check = mod.PyNone_Check;
pub const PyTuple_Check = mod.PyTuple_Check;
pub const PyList_Check = mod.PyList_Check;
pub const PyDict_Check = mod.PyDict_Check;
pub const PySet_Check = mod.PySet_Check;
pub const PyFrozenSet_Check = mod.PyFrozenSet_Check;
pub const PyAnySet_Check = mod.PyAnySet_Check;
pub const PyBytes_Check = mod.PyBytes_Check;
pub const PyByteArray_Check = mod.PyByteArray_Check;
pub const PyObject_TypeCheck = mod.PyObject_TypeCheck;
pub const PyCallable_Check = mod.PyCallable_Check;

// Numeric operations
pub const PyLong_FromLongLong = mod.PyLong_FromLongLong;
pub const PyLong_FromString = mod.PyLong_FromString;
pub const PyLong_FromUnsignedLongLong = mod.PyLong_FromUnsignedLongLong;
pub const PyFloat_FromDouble = mod.PyFloat_FromDouble;
pub const PyComplex_FromDoubles = mod.PyComplex_FromDoubles;
pub const PyComplex_RealAsDouble = mod.PyComplex_RealAsDouble;
pub const PyComplex_ImagAsDouble = mod.PyComplex_ImagAsDouble;
pub const PyComplex_Check = mod.PyComplex_Check;
pub const PyBool_FromLong = mod.PyBool_FromLong;
pub const PyLong_AsLongLong = mod.PyLong_AsLongLong;
pub const PyLong_AsUnsignedLongLong = mod.PyLong_AsUnsignedLongLong;
pub const PyLong_AsDouble = mod.PyLong_AsDouble;
pub const PyFloat_AsDouble = mod.PyFloat_AsDouble;

// String operations
pub const PyUnicode_FromString = mod.PyUnicode_FromString;
pub const PyUnicode_FromStringAndSize = mod.PyUnicode_FromStringAndSize;
pub const PyUnicode_AsUTF8 = mod.PyUnicode_AsUTF8;
pub const PyUnicode_AsUTF8AndSize = mod.PyUnicode_AsUTF8AndSize;
pub const PyUnicode_Concat = mod.PyUnicode_Concat;
pub const PyUnicode_FromFormat = mod.PyUnicode_FromFormat;

// Tuple operations
pub const PyTuple_Size = mod.PyTuple_Size;
pub const PyTuple_GetItem = mod.PyTuple_GetItem;
pub const PyTuple_New = mod.PyTuple_New;
pub const PyTuple_SetItem = mod.PyTuple_SetItem;
pub const PyTuple_Pack = mod.PyTuple_Pack;

// List operations
pub const PyList_New = mod.PyList_New;
pub const PyList_Size = mod.PyList_Size;
pub const PyList_GetItem = mod.PyList_GetItem;
pub const PyList_SetItem = mod.PyList_SetItem;
pub const PyList_Append = mod.PyList_Append;
pub const PyList_SetSlice = mod.PyList_SetSlice;
pub const PyList_Insert = mod.PyList_Insert;

// Dict operations
pub const PyDict_New = mod.PyDict_New;
pub const PyDict_SetItemString = mod.PyDict_SetItemString;
pub const PyDict_GetItemString = mod.PyDict_GetItemString;
pub const PyDict_Size = mod.PyDict_Size;
pub const PyDict_Keys = mod.PyDict_Keys;
pub const PyDict_Values = mod.PyDict_Values;
pub const PyDict_Items = mod.PyDict_Items;
pub const PyDict_SetItem = mod.PyDict_SetItem;
pub const PyDict_GetItem = mod.PyDict_GetItem;
pub const PyDict_Next = mod.PyDict_Next;

// Set operations
pub const PySet_New = mod.PySet_New;
pub const PyFrozenSet_New = mod.PyFrozenSet_New;
pub const PySet_Size = mod.PySet_Size;
pub const PySet_Contains = mod.PySet_Contains;
pub const PySet_Add = mod.PySet_Add;
pub const PySet_Discard = mod.PySet_Discard;
pub const PySet_Pop = mod.PySet_Pop;
pub const PySet_Clear = mod.PySet_Clear;

// Iterator operations
pub const PyObject_GetIter = mod.PyObject_GetIter;
pub const PyIter_Next = mod.PyIter_Next;
pub const PySequence_List = mod.PySequence_List;

// Object operations
pub const PyObject_Init = mod.PyObject_Init;
pub const PyObject_New = mod.PyObject_New;
pub const PyObject_Del = mod.PyObject_Del;
pub const PyObject_ClearWeakRefs = mod.PyObject_ClearWeakRefs;
pub const PyObject_Repr = mod.PyObject_Repr;
pub const PyObject_Str = mod.PyObject_Str;
pub const PyObject_CallObject = mod.PyObject_CallObject;
pub const PyObject_Call = mod.PyObject_Call;
pub const PyObject_SetAttrString = mod.PyObject_SetAttrString;
pub const PyObject_GenericGetAttr = mod.PyObject_GenericGetAttr;
pub const PyObject_GenericSetAttr = mod.PyObject_GenericSetAttr;
pub const PyObject_IsTrue = mod.PyObject_IsTrue;
pub const PyObject_GetAttr = mod.PyObject_GetAttr;
pub const PyObject_GetAttrString = mod.PyObject_GetAttrString;
pub const PyObject_SetAttr = mod.PyObject_SetAttr;
pub const PyObject_IsInstance = mod.PyObject_IsInstance;
pub const PyObject_CallFunction = mod.PyObject_CallFunction;

// Type operations
pub const PyType_FromSpec = mod.PyType_FromSpec;
pub const PyType_Ready = mod.PyType_Ready;
pub const PyType_GenericAlloc = mod.PyType_GenericAlloc;
pub const PyType_GenericNew = mod.PyType_GenericNew;

// Module operations
pub const PyModule_Create = mod.PyModule_Create;
pub const PyModuleDef_Init = mod.PyModuleDef_Init;
pub const PyModule_AddObject = mod.PyModule_AddObject;
pub const PyModule_AddIntConstant = mod.PyModule_AddIntConstant;
pub const PyModule_AddStringConstant = mod.PyModule_AddStringConstant;
pub const PyModule_AddType = mod.PyModule_AddType;
pub const PyModule_GetDict = mod.PyModule_GetDict;

// Error operations
pub const PyErr_SetString = mod.PyErr_SetString;
pub const PyErr_Occurred = mod.PyErr_Occurred;
pub const PyErr_Clear = mod.PyErr_Clear;
pub const PyErr_ExceptionMatches = mod.PyErr_ExceptionMatches;
pub const PyErr_Fetch = mod.PyErr_Fetch;
pub const PyErr_Restore = mod.PyErr_Restore;
pub const PyErr_NormalizeException = mod.PyErr_NormalizeException;
pub const PyErr_GivenExceptionMatches = mod.PyErr_GivenExceptionMatches;
pub const PyErr_SetObject = mod.PyErr_SetObject;
pub const PyErr_GetExcInfo = mod.PyErr_GetExcInfo;
pub const PyErr_NewException = mod.PyErr_NewException;
pub const PyErr_Print = mod.PyErr_Print;
pub const PyErr_CheckSignals = mod.PyErr_CheckSignals;
pub const PyExc_RuntimeError = mod.PyExc_RuntimeError;
pub const PyExc_TypeError = mod.PyExc_TypeError;
pub const PyExc_ValueError = mod.PyExc_ValueError;
pub const PyExc_AttributeError = mod.PyExc_AttributeError;
pub const PyExc_IndexError = mod.PyExc_IndexError;
pub const PyExc_KeyError = mod.PyExc_KeyError;
pub const PyExc_ZeroDivisionError = mod.PyExc_ZeroDivisionError;
pub const PyExc_StopIteration = mod.PyExc_StopIteration;
pub const PyExc_Exception = mod.PyExc_Exception;
pub const PyExc_ArithmeticError = mod.PyExc_ArithmeticError;
pub const PyExc_LookupError = mod.PyExc_LookupError;
pub const PyExc_AssertionError = mod.PyExc_AssertionError;
pub const PyExc_BufferError = mod.PyExc_BufferError;
pub const PyExc_EOFError = mod.PyExc_EOFError;
pub const PyExc_FileExistsError = mod.PyExc_FileExistsError;
pub const PyExc_FileNotFoundError = mod.PyExc_FileNotFoundError;
pub const PyExc_FloatingPointError = mod.PyExc_FloatingPointError;
pub const PyExc_ImportError = mod.PyExc_ImportError;
pub const PyExc_ModuleNotFoundError = mod.PyExc_ModuleNotFoundError;
pub const PyExc_IsADirectoryError = mod.PyExc_IsADirectoryError;
pub const PyExc_MemoryError = mod.PyExc_MemoryError;
pub const PyExc_NotADirectoryError = mod.PyExc_NotADirectoryError;
pub const PyExc_NotImplementedError = mod.PyExc_NotImplementedError;
pub const PyExc_OSError = mod.PyExc_OSError;
pub const PyExc_OverflowError = mod.PyExc_OverflowError;
pub const PyExc_PermissionError = mod.PyExc_PermissionError;
pub const PyExc_ProcessLookupError = mod.PyExc_ProcessLookupError;
pub const PyExc_RecursionError = mod.PyExc_RecursionError;
pub const PyExc_SystemError = mod.PyExc_SystemError;
pub const PyExc_TimeoutError = mod.PyExc_TimeoutError;
pub const PyExc_UnicodeDecodeError = mod.PyExc_UnicodeDecodeError;
pub const PyExc_UnicodeEncodeError = mod.PyExc_UnicodeEncodeError;
pub const PyExc_UnicodeError = mod.PyExc_UnicodeError;
pub const PyExc_ConnectionError = mod.PyExc_ConnectionError;
pub const PyExc_ConnectionAbortedError = mod.PyExc_ConnectionAbortedError;
pub const PyExc_ConnectionRefusedError = mod.PyExc_ConnectionRefusedError;
pub const PyExc_ConnectionResetError = mod.PyExc_ConnectionResetError;
pub const PyExc_BlockingIOError = mod.PyExc_BlockingIOError;
pub const PyExc_BrokenPipeError = mod.PyExc_BrokenPipeError;
pub const PyExc_ChildProcessError = mod.PyExc_ChildProcessError;
pub const PyExc_InterruptedError = mod.PyExc_InterruptedError;
pub const PyExc_SystemExit = mod.PyExc_SystemExit;
pub const PyExc_KeyboardInterrupt = mod.PyExc_KeyboardInterrupt;
pub const PyExc_BaseException = mod.PyExc_BaseException;
pub const PyExc_GeneratorExit = mod.PyExc_GeneratorExit;
pub const PyExc_NameError = mod.PyExc_NameError;
pub const PyExc_UnboundLocalError = mod.PyExc_UnboundLocalError;
pub const PyExc_ReferenceError = mod.PyExc_ReferenceError;
pub const PyExc_StopAsyncIteration = mod.PyExc_StopAsyncIteration;
pub const PyExc_SyntaxError = mod.PyExc_SyntaxError;
pub const PyExc_IndentationError = mod.PyExc_IndentationError;
pub const PyExc_TabError = mod.PyExc_TabError;
pub const PyExc_UnicodeTranslateError = mod.PyExc_UnicodeTranslateError;
pub const PyExc_Warning = mod.PyExc_Warning;
pub const PyExc_BytesWarning = mod.PyExc_BytesWarning;
pub const PyExc_DeprecationWarning = mod.PyExc_DeprecationWarning;
pub const PyExc_FutureWarning = mod.PyExc_FutureWarning;
pub const PyExc_ImportWarning = mod.PyExc_ImportWarning;
pub const PyExc_PendingDeprecationWarning = mod.PyExc_PendingDeprecationWarning;
pub const PyExc_ResourceWarning = mod.PyExc_ResourceWarning;
pub const PyExc_RuntimeWarning = mod.PyExc_RuntimeWarning;
pub const PyExc_SyntaxWarning = mod.PyExc_SyntaxWarning;
pub const PyExc_UnicodeWarning = mod.PyExc_UnicodeWarning;
pub const PyExc_UserWarning = mod.PyExc_UserWarning;

// DateTime operations
pub const PyDateTime_Import = mod.PyDateTime_Import;
pub const PyDateTime_IsInitialized = mod.PyDateTime_IsInitialized;
pub const PyDate_FromDate = mod.PyDate_FromDate;
pub const PyDateTime_FromDateAndTime = mod.PyDateTime_FromDateAndTime;
pub const PyTime_FromTime = mod.PyTime_FromTime;
pub const PyDelta_FromDSU = mod.PyDelta_FromDSU;
pub const PyDate_Check = mod.PyDate_Check;
pub const PyDateTime_Check = mod.PyDateTime_Check;
pub const PyTime_Check = mod.PyTime_Check;
pub const PyDelta_Check = mod.PyDelta_Check;
pub const PyDateTime_GET_YEAR = mod.PyDateTime_GET_YEAR;
pub const PyDateTime_GET_MONTH = mod.PyDateTime_GET_MONTH;
pub const PyDateTime_GET_DAY = mod.PyDateTime_GET_DAY;
pub const PyDateTime_DATE_GET_HOUR = mod.PyDateTime_DATE_GET_HOUR;
pub const PyDateTime_DATE_GET_MINUTE = mod.PyDateTime_DATE_GET_MINUTE;
pub const PyDateTime_DATE_GET_SECOND = mod.PyDateTime_DATE_GET_SECOND;
pub const PyDateTime_DATE_GET_MICROSECOND = mod.PyDateTime_DATE_GET_MICROSECOND;
pub const PyDateTime_TIME_GET_HOUR = mod.PyDateTime_TIME_GET_HOUR;
pub const PyDateTime_TIME_GET_MINUTE = mod.PyDateTime_TIME_GET_MINUTE;
pub const PyDateTime_TIME_GET_SECOND = mod.PyDateTime_TIME_GET_SECOND;
pub const PyDateTime_TIME_GET_MICROSECOND = mod.PyDateTime_TIME_GET_MICROSECOND;
pub const PyDateTime_DELTA_GET_DAYS = mod.PyDateTime_DELTA_GET_DAYS;
pub const PyDateTime_DELTA_GET_SECONDS = mod.PyDateTime_DELTA_GET_SECONDS;
pub const PyDateTime_DELTA_GET_MICROSECONDS = mod.PyDateTime_DELTA_GET_MICROSECONDS;

// Buffer protocol
pub const Py_buffer = mod.Py_buffer;
pub const PyBufferProcs = mod.PyBufferProcs;
pub const PyBUF_SIMPLE = mod.PyBUF_SIMPLE;
pub const PyBUF_WRITABLE = mod.PyBUF_WRITABLE;
pub const PyBUF_FORMAT = mod.PyBUF_FORMAT;
pub const PyBUF_ND = mod.PyBUF_ND;
pub const PyBUF_STRIDES = mod.PyBUF_STRIDES;
pub const PyBUF_C_CONTIGUOUS = mod.PyBUF_C_CONTIGUOUS;
pub const PyBUF_F_CONTIGUOUS = mod.PyBUF_F_CONTIGUOUS;
pub const PyBUF_ANY_CONTIGUOUS = mod.PyBUF_ANY_CONTIGUOUS;
pub const PyBUF_FULL = mod.PyBUF_FULL;
pub const PyBUF_FULL_RO = mod.PyBUF_FULL_RO;
pub const PyBuffer_FillInfo = mod.PyBuffer_FillInfo;
pub const PyObject_GetBuffer = mod.PyObject_GetBuffer;
pub const PyBuffer_Release = mod.PyBuffer_Release;
pub const PyObject_CheckBuffer = mod.PyObject_CheckBuffer;

// GIL operations
pub const PyThreadState = mod.PyThreadState;
pub const PyGILState_STATE = mod.PyGILState_STATE;
pub const PyEval_SaveThread = mod.PyEval_SaveThread;
pub const PyEval_RestoreThread = mod.PyEval_RestoreThread;
pub const PyGILState_Ensure = mod.PyGILState_Ensure;
pub const PyGILState_Release = mod.PyGILState_Release;

// Bytes operations
pub const PyBytes_FromStringAndSize = mod.PyBytes_FromStringAndSize;
pub const PyBytes_AsStringAndSize = mod.PyBytes_AsStringAndSize;
pub const PyBytes_Size = mod.PyBytes_Size;
pub const PyBytes_AsString = mod.PyBytes_AsString;
pub const PyByteArray_FromStringAndSize = mod.PyByteArray_FromStringAndSize;
pub const PyByteArray_AsString = mod.PyByteArray_AsString;
pub const PyByteArray_Size = mod.PyByteArray_Size;

// Path operations
pub const PyPath_FromString = mod.PyPath_FromString;
pub const PyPath_Check = mod.PyPath_Check;
pub const PyPath_AsString = mod.PyPath_AsString;
pub const PyPath_AsStringWithRef = mod.PyPath_AsStringWithRef;
pub const PathStringResult = mod.PathStringResult;

// Embedding API
pub const Py_single_input = mod.Py_single_input;
pub const Py_file_input = mod.Py_file_input;
pub const Py_eval_input = mod.Py_eval_input;
pub const Py_Initialize = mod.Py_Initialize;
pub const Py_InitializeEx = mod.Py_InitializeEx;
pub const Py_IsInitialized = mod.Py_IsInitialized;
pub const Py_Finalize = mod.Py_Finalize;
pub const Py_FinalizeEx = mod.Py_FinalizeEx;
pub const PyRun_SimpleString = mod.PyRun_SimpleString;
pub const PyRun_String = mod.PyRun_String;
pub const PyImport_AddModule = mod.PyImport_AddModule;
pub const PyImport_ImportModule = mod.PyImport_ImportModule;
pub const PyMain_GetGlobal = mod.PyMain_GetGlobal;
pub const PyMain_SetGlobal = mod.PyMain_SetGlobal;
pub const PyEval_Expression = mod.PyEval_Expression;
pub const PyExec_Statements = mod.PyExec_Statements;
