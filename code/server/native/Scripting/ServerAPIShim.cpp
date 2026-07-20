// ----------------------------------------------------------------------------
// Plain-C export shim over the C++ ServerAPI static methods.
//
// The C# loader (Server.Loader / CyberpunkMp.cs) P/Invokes the server by these
// exact, unmangled names. C++ member functions mangle differently per toolchain
// (Itanium on Linux/GCC-Clang, MSVC on Windows), so a binding compiled against
// one ABI cannot resolve the exports of the other. Wrapping the calls in an
// extern "C" layer disables name mangling entirely: the export symbols
// (ServerAPI_Initialize, ...) are byte-for-byte identical on both platforms,
// giving the loader a single, portable binding surface.
//
// TP_EXPORT expands to __declspec(dllexport) on Windows and
// __attribute__((visibility("default"))) elsewhere (see ScriptingBase.h), so
// each function is actually exported from Server.Native under both toolchains.
// ----------------------------------------------------------------------------
#include "ServerAPI.h"

extern "C"
{
    TP_EXPORT bool ServerAPI_Initialize()
    {
        return ServerAPI::Initialize();
    }

    TP_EXPORT void ServerAPI_Run()
    {
        ServerAPI::Run();
    }

    TP_EXPORT void ServerAPI_Exit()
    {
        ServerAPI::Exit();
    }

    TP_EXPORT void ServerAPI_SetUpdateCallback(TUpdateCallback aCallback)
    {
        ServerAPI::SetUpdateCallback(aCallback);
    }

    TP_EXPORT void ServerAPI_SetPlayerJoinCallback(TPlayerEvent aCallback)
    {
        ServerAPI::SetPlayerJoinCallback(aCallback);
    }

    TP_EXPORT void ServerAPI_SetPlayerLeftCallback(TPlayerEvent aCallback)
    {
        ServerAPI::SetPlayerLeftCallback(aCallback);
    }
}
