// ----------------------------------------------------------------------------
// Hand-written P/Invoke binding for the native ServerAPI.
//
// This file replaces the former CppSharp-generated CyberpunkMp.cs. CppSharp
// parses with a bundled Clang and emits Itanium (Clang/GCC) mangled DllImport
// EntryPoints regardless of the target platform, e.g.
//     _ZN9ServerAPI10InitializeEv
// Those names only exist in a Linux/GCC-built Server.Native. A Windows MSVC
// build mangles the same symbols completely differently, so the generated
// binding could never resolve the exports on Windows -- which is why the
// Windows server was not runnable.
//
// The bindings below target the plain, unmangled extern "C" shim exported by
// Server.Native (code/server/native/Scripting/ServerAPIShim.cpp). extern "C"
// disables C++ name mangling, so the export symbol is byte-for-byte identical
// under both the Linux (Itanium) and Windows (MSVC) ABIs. That is what makes a
// single loader binding work on both platforms.
// ----------------------------------------------------------------------------
using System;
using System.Runtime.InteropServices;
using System.Security;

namespace CyberpunkMp
{
    [SuppressUnmanagedCodeSecurity, UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void TUpdateCallback(float delta);

    [SuppressUnmanagedCodeSecurity, UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void TPlayerEvent(ulong playerId);

    /// <summary>
    /// Managed entry points into the native game server. Binds to the plain
    /// extern "C" ServerAPI_* exports of Server.Native.
    /// </summary>
    public static class ServerAPI
    {
        private const string NativeLib = "Server.Native";

        [SuppressUnmanagedCodeSecurity]
        [DllImport(NativeLib, EntryPoint = "ServerAPI_Initialize", CallingConvention = CallingConvention.Cdecl)]
        [return: MarshalAs(UnmanagedType.I1)]
        public static extern bool Initialize();

        [SuppressUnmanagedCodeSecurity]
        [DllImport(NativeLib, EntryPoint = "ServerAPI_Run", CallingConvention = CallingConvention.Cdecl)]
        public static extern void Run();

        [SuppressUnmanagedCodeSecurity]
        [DllImport(NativeLib, EntryPoint = "ServerAPI_Exit", CallingConvention = CallingConvention.Cdecl)]
        public static extern void Exit();

        [SuppressUnmanagedCodeSecurity]
        [DllImport(NativeLib, EntryPoint = "ServerAPI_SetUpdateCallback", CallingConvention = CallingConvention.Cdecl)]
        public static extern void SetUpdateCallback(TUpdateCallback callback);

        [SuppressUnmanagedCodeSecurity]
        [DllImport(NativeLib, EntryPoint = "ServerAPI_SetPlayerJoinCallback", CallingConvention = CallingConvention.Cdecl)]
        public static extern void SetPlayerJoinCallback(TPlayerEvent callback);

        [SuppressUnmanagedCodeSecurity]
        [DllImport(NativeLib, EntryPoint = "ServerAPI_SetPlayerLeftCallback", CallingConvention = CallingConvention.Cdecl)]
        public static extern void SetPlayerLeftCallback(TPlayerEvent callback);
    }
}
