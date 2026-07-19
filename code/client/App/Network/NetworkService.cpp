#include "NetworkService.h"

#include "App/World/NetworkWorldSystem.h"
#include "Game/Utils.h"
#include "RED4ext/Scripting/Natives/Generated/Vector4.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/Object.hpp"
// The 2.31 SDK's entEntity.hpp only forward-declares IPlacedComponent; the
// transformComponent->localTransform reads below need the complete type.
#include "RED4ext/Scripting/Natives/Generated/ent/IPlacedComponent.hpp"
#include "App/World/AppearanceSystem.h"
#include "Game/CharacterCustomizationSystem.h"

NetworkService::NetworkService()
    : Client(client::kIdentifier, server::kIdentifier)
    , m_lastUpdate(std::chrono::steady_clock::now())
{
    BindMessageHandlers();
}

NetworkService::~NetworkService()
{
}

void NetworkService::BindMessageHandlers()
{
    GetSink<server::AuthenticationResponse>().connect<&NetworkService::HandleAuthentication>(this);
}

void NetworkService::OnConsume(const void* apData, uint32_t aSize)
{
    ViewBuffer buf((uint8_t*)apData, aSize);
    Buffer::Reader reader(&buf);

    if(!server::Deserializer::Process(reader, 0, m_dispatcher))
    {
        spdlog::error("Failed to deserialize a message from the server.");
    }
}

void NetworkService::OnConnected()
{
    spdlog::info("Connected to server.");

    client::AuthenticationRequest request;
    request.set_token("test");
    request.set_username("testuser");
    request.set_client_protocol(client::kIdentifier);
    request.set_server_protocol(server::kIdentifier);

    Send(request);
}

void NetworkService::OnDisconnected(EDisconnectReason aReason)
{
    spdlog::info("Disconnected from server {}", static_cast<uint32_t>(aReason));

    // Clear RPC tables on every disconnect path (explicit Close + async status
    // change both converge here) so a fast reconnect never dispatches against a
    // stale definition table.
    if (const auto pRpcService = Core::Container::Get<RpcService>())
        pRpcService->OnDisconnected();

    Red::GetGameSystem<NetworkWorldSystem>()->OnDisconnected(aReason);

    m_authenticated = false;
}

void NetworkService::OnUpdate()
{
    m_dispatcher.update();

    Red::GetGameSystem<NetworkWorldSystem>()->Update(GetClock().GetCurrentTick());
}

void NetworkService::OnGameUpdate(RED4ext::CGameApplication* apApp)
{
    Update();
}

void NetworkService::HandleAuthentication(const PacketEvent<server::AuthenticationResponse>& aResponse)
{
    if (!aResponse.get_success())
    {
        // Handle the error message here
        // aResponse.get_error();
        Close();
        return;
    }

    m_settings = aResponse.get_settings();

    Red::GetGameSystem<NetworkWorldSystem>()->OnConnected();

    client::SpawnCharacterRequest request;
    request.set_is_player(true);

    Red::Handle<Red::GameObject> player;
    // 2.31a exe audit: the hand-declared vtable slot for
    // GetLocalPlayerControlledGameObject drifted (the fake virtuals in
    // PlayerSystem.h landed the call at +0x138 instead of the RE'd +0x1E0).
    // Dispatch by name through RTTI reflection instead, which is immune to
    // vtable-slot layout drift (same pattern as AppearanceSystem GetPlayerItems).
    Red::CallVirtual(Red::GetGameSystem<Game::PlayerSystem>(), "GetLocalPlayerControlledGameObject", player);

    const auto& cEntityPosition = player->transformComponent->localTransform.Position;
    const auto cEntityRotation = Game::ToGlm(player->transformComponent->localTransform.Orientation);

    common::Vector3 pos;
    pos.set_x(cEntityPosition.x);
    pos.set_y(cEntityPosition.y);
    pos.set_z(cEntityPosition.z);

    request.set_position(pos);
    request.set_rotation(cEntityRotation.z);
    request.set_cookie(0);

    auto appSystem = Red::GetGameSystem<NetworkWorldSystem>()->GetAppearanceSystem();
    request.set_equipment(appSystem->GetPlayerItems(player));


    auto ccSystem = Red::GetGameSystem<Red::game::ui::CharacterCustomizationSystem>();
    auto stateHandle = GetCustomizationState(ccSystem);
    if (stateHandle) 
    {
        auto writer = CMPWriter();
        CharacterCustomizationState_Serialize(stateHandle->instance, &writer);
        spdlog::info("Got bytes: {}", writer.bytes.size());
        request.set_ccstate(writer.bytes);
    } 
    else
    {
        spdlog::info("CustomizationState was null");
    }

    Send(request);
}

ScratchAllocator& NetworkService::GetScratch()
{
    thread_local ScratchAllocator s_allocator{1 << 19};
    return s_allocator;
}
