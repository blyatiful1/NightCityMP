#include "Settings.h"
#include <RED4ext/LaunchParameters.hpp>

void Settings::Load()
{
    Settings& settings = Get();

    auto& launchParameters = RED4ext::GetLaunchParameters();

    // -online no longer gates the mod (it is always-on now); it arms a boot-time
    // pending session that auto-connects on the next world attach using -ip/-port
    // below. Dev / observer / back-compat path.
    if (launchParameters.Contains(RED4ext::CString("-online")))
        settings.pendingSession = true;

    // -debug enables the dev-only ImGui overlay (DebugService). Default off so no
    // player ever sees an in-game connect button.
    if (launchParameters.Contains(RED4ext::CString("-debug")))
        settings.debug = true;

    if (const auto ip = launchParameters.Get("-ip"); ip)
    {
        if (ip->size > 0)
            settings.ip = (*ip)[0].c_str();
    }

    if (const auto port = launchParameters.Get("-port"); port)
    {
        if (port->size > 0)
            settings.port = std::strtoul((*port)[0].c_str(), nullptr, 10) & 0xFFFF;
    }

    if (const auto mods = launchParameters.Get("-mod"); mods)
    {
        for (const auto& mod : *mods)
            settings.mods.push_back(mod.c_str());
    }

    if (launchParameters.Contains("-rpc"))
    {
        settings.RpcOnly = true;
    }

    if (const auto rpcDir = launchParameters.Get("-rpcdir"); rpcDir)
    {
        if (rpcDir->size > 0)
        {
            // For some reason cyberpunk adds a \ at the start and end of the path...
            std::string path = std::string((*rpcDir)[0].c_str());
            path = path.substr(1, path.length() - 2);

            settings.RpcPath = path;
        }
    }
}
