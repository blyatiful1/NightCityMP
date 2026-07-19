#pragma once

namespace fs = std::filesystem;

struct Settings
{
    static Settings& Get()
    {
        static Settings instance;
        return instance;
    }
    static void Load();

    // Point the client at a server endpoint at runtime (menu / native ConnectTo).
    static void SetEndpoint(const char* aIp, uint16_t aPort)
    {
        Get().ip = aIp;
        Get().port = aPort;
    }

    fs::path exePath{};
    fs::path gamePath{};
    String Version{};
    String ip = "127.0.0.1";
    uint16_t port = 11778;
    Vector<fs::path> mods = {};
    // Auto-connect armed for the next world attach (from -online or the menu).
    // Native-side state: survives save/world reloads, cleared once consumed.
    bool pendingSession = false;
    // Dev-only ImGui debug overlay (-debug). Default off; never a player-facing UI.
    bool debug = false;
    bool RpcOnly = false;
    fs::path RpcPath{};

private:
    Settings() = default;
};