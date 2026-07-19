
#include "DebugService.h"
#include <App/Network/NetworkService.h>
#include <App/Settings.h>

namespace App
{
    DebugService::DebugService()
    {
    }

    DebugService::~DebugService()
    {
    }

    void DebugService::OnBootstrap()
    {
    }

    void DebugService::Draw()
    {
        // Dev-only overlay: gated behind -debug (default off), never behind the
        // retired enabled flag. No player ever sees an in-game connect button.
        if (!Settings::Get().debug)
            return;

        if (ImGui::BeginMainMenuBar())
        {
            if (ImGui::BeginMenu("Test"))
            {
                if (ImGui::Button("Connect"))
                {
                    Core::Container::Get<NetworkService>()->Connect("127.0.0.1:11778");

                    /*auto handle = Red::GetGameSystem<NetworkWorldSystem>();
                    Red::EntityID id;
                    Red::ScriptGameInstance game;
                    Red::CallVirtual(handle, "CreatePuppet", id, game);*/
                }
                ImGui::EndMenu();
            }
            ImGui::EndMainMenuBar();
        }

    }
}
