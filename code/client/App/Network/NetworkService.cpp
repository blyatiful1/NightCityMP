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

namespace
{
// Upper bound on how long the deferred SpawnCharacterRequest waits for the
// CharacterCustomizationSystem to populate. Real save-loads populate CCS within a
// few seconds of world attach; this generous bound only trips on a genuinely
// never-populated state (PLAN.md M7 saw a pathological 93s-still-empty case), in
// which we fall back to spawning with default appearance instead of hanging.
constexpr auto kSpawnCcstateTimeout = std::chrono::seconds(30);
}

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
    // Abandon any in-flight deferred spawn so a fast reconnect starts clean.
    m_pendingSpawn = false;
}

void NetworkService::OnUpdate()
{
    m_dispatcher.update();

    // Poll after dispatch so an AuthenticationResponse handled this tick can also
    // spawn this tick when CCS is already populated (the manual-timing fast path).
    if (m_pendingSpawn)
        TrySendSpawnCharacter();

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
    m_authenticated = true;

    Red::GetGameSystem<NetworkWorldSystem>()->OnConnected();

    // Defer the SpawnCharacterRequest instead of sending it here. It is the only
    // client->server message that carries ccstate, and the server ingests it
    // exactly once (Level::HandleSpawnCharacterRequest) with no re-upload message
    // in the protocol. Menu-driven auto-connect authenticates right at world
    // attach, in the exact window where the CharacterCustomizationSystem state is
    // still empty ("CCS state handle drift: instance=0x0"), so sending now would
    // upload an empty appearance with no way to correct it. Arm the deferred send
    // and try immediately: if CCS (and the local player) are already populated —
    // the historical manual-F7 timing — it fires this tick; otherwise OnUpdate
    // keeps polling the native readiness signal until it is.
    m_pendingSpawn = true;
    m_spawnDeadline = std::chrono::steady_clock::now() + kSpawnCcstateTimeout;
    TrySendSpawnCharacter();
}

void NetworkService::TrySendSpawnCharacter()
{
    if (!m_pendingSpawn)
        return;

    // Connection dropped while we were waiting; the disconnect path already
    // cleared m_pendingSpawn, but guard anyway.
    if (!IsConnected())
    {
        m_pendingSpawn = false;
        return;
    }

    Red::Handle<Red::GameObject> player;
    // 2.31a exe audit: the hand-declared vtable slot for
    // GetLocalPlayerControlledGameObject drifted (the fake virtuals in
    // PlayerSystem.h landed the call at +0x138 instead of the RE'd +0x1E0).
    // Dispatch by name through RTTI reflection instead, which is immune to
    // vtable-slot layout drift (same pattern as AppearanceSystem GetPlayerItems).
    Red::CallVirtual(Red::GetGameSystem<Game::PlayerSystem>(), "GetLocalPlayerControlledGameObject", player);

    // Position is mandatory for the spawn. Without a local player puppet there is
    // nothing to send, so keep waiting (even past the ccstate deadline) rather
    // than dereferencing a null player — the crash the old inline path risked on
    // a fast auto-connect.
    if (!player || !player->transformComponent)
        return;

    auto ccSystem = Red::GetGameSystem<Red::game::ui::CharacterCustomizationSystem>();
    const bool ccReady = IsCustomizationStateReady(ccSystem);
    const bool timedOut = std::chrono::steady_clock::now() >= m_spawnDeadline;

    // Keep polling until the engine populates CCS, or the fallback deadline hits.
    if (!ccReady && !timedOut)
        return;

    client::SpawnCharacterRequest request;
    request.set_is_player(true);

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

    if (ccReady)
    {
        if (auto stateHandle = GetCustomizationState(ccSystem))
        {
            auto writer = CMPWriter();
            CharacterCustomizationState_Serialize(stateHandle->instance, &writer);
            spdlog::info("Uploading ccstate: {} bytes", writer.bytes.size());
            request.set_ccstate(writer.bytes);
        }
    }
    else
    {
        spdlog::warn("CharacterCustomizationSystem never became ready within {}s; "
                     "spawning with default appearance (empty ccstate).",
                     std::chrono::duration_cast<std::chrono::seconds>(kSpawnCcstateTimeout).count());
    }

    Send(request);
    m_pendingSpawn = false;
}

ScratchAllocator& NetworkService::GetScratch()
{
    thread_local ScratchAllocator s_allocator{1 << 19};
    return s_allocator;
}
