#include "World.h"

#include "Config.h"
#include "PlayerManager.h"
#include "Level.h"

#include "Components/MovementComponent.h"
#include "Components/PlayerComponent.h"
#include "Components/AttachmentComponent.h"
#include "Components/VehicleComponent.h"

#include "Systems/ChatSystem.h"
#include "Systems/ServerListSystem.h"

World::World(const FlecsConfig& acFlecsConfig)
{
    set_entity_range(1, 5'000'000);

    emplace<Level>(this);
    emplace<PlayerManager>(this);
    emplace<ChatSystem>(this);
    emplace<ServerListSystem>(this);

    if (acFlecsConfig.IsEnabled())
    {
        set<flecs::Rest>({
            .port = acFlecsConfig.GetPort(),
            // flecs takes ownership of EcsRest::ipaddr and releases it with
            // ecs_os_free() from the component destructor during ecs_fini (world
            // teardown). The previous const_cast<char*>(...c_str()) handed flecs a
            // pointer into a std::string's internal buffer, so teardown called
            // free() on memory glibc never allocated -> "free(): invalid size"
            // SIGABRT at shutdown. Give flecs its own heap copy from the matching
            // allocator (ecs_os_strdup pairs with ecs_os_free).
            .ipaddr = ecs_os_strdup(acFlecsConfig.GetIpAddress()),
            .impl = nullptr
        });
        spdlog::info("Running Flecs REST API on {}:{}", acFlecsConfig.IpAddress, acFlecsConfig.Port);
    }

    this->import<flecs::units>();
    this->import<flecs::stats>();

    component<std::string>()
        .opaque(flecs::String)
        .serialize(
            [](const flecs::serializer* s, const std::string* data)
            {
                const char* str = data->c_str();
                return s->value(flecs::String, &str); // Forward to serializer
            })
        .assign_string(
            [](std::string* data, const char* value)
            {
                *data = value; // Assign new value to std::string
            });

    MovementComponent::Register(*this);
    AttachmentComponent::Register(*this);
    PlayerComponent::Register(*this);
    VehicleComponent::Register(*this);
}

World::~World()
{
}

void World::Update(float aDelta)
{
    progress(aDelta);
}

gsl::not_null<WorldScriptInstance*> World::GetScriptInstance() noexcept
{
    return &m_scriptInstance;
}

gsl::not_null<const WorldScriptInstance*> World::GetScriptInstance() const noexcept
{
    return &m_scriptInstance;
}
