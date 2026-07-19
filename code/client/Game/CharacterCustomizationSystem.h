#pragma once

#include <RED4ext/Scripting/Natives/Generated/game/ui/CharacterCustomizationSystem.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/ui/CharacterCustomizationState.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/ui/CharacterCustomizationPreset.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/data/Item_Record.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/data/AttachmentSlot_Record.hpp>
#include <RED4ext/Scripting/Natives/Generated/ink/GameSettingsResource.hpp>
#include <RED4ext/Scripting/Natives/CResource.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/RuntimeSystemEntityAppearanceChanger.hpp>
#include "Game/Utils.h"

using namespace Red;

constexpr auto CreateHandle_CharacterCustomizationState = Core::RawFunc<2710710832UL, 
    Handle<game::ui::CharacterCustomizationState> * (*)(Handle<game::ui::CharacterCustomizationState> *)>();


constexpr auto CharacterCustomizationState_InitFromPreset = Core::RawFunc<1993027039UL, 
    Handle<game::ui::CharacterCustomizationState> * (*)(game::ui::CharacterCustomizationState *, Handle<game::ui::CharacterCustomizationPreset> *)>();

constexpr auto CharacterCustomizationState_Serialize = Core::RawFunc<108403442UL, 
    void (*)(game::ui::CharacterCustomizationState *, CMPStream *)>();

// constexpr auto gameTransactionSystem_AddItemToSlot = Core::RawFunc<56564470UL, 
//     void (*)(game::TransactionSystem *, const AddItemToSlotContext *)>();

constexpr auto GetGameSettings = Core::RawFunc<394336209UL, 
    ink::GameSettingsResource const * (*)(void)>();

// constexpr auto ItemID_SetUniqueCounterValue = Core::RawFunc<1713639304UL, void (*)(ItemID *)>();

constexpr auto ItemID_Create = Core::RawFunc<3020231866UL, ItemID * (*)(ItemID *, TweakDBID, int64_t seed)>();

constexpr auto GetItemRecord = Core::RawFunc<3236045910UL, 
    Handle<game::data::Item_Record> * (Handle<game::data::Item_Record>::*)(TweakDBID)>();

constexpr auto GetPlacementSlot = Core::RawFunc<1934369954UL, 
    Handle<game::data::AttachmentSlot_Record> * (game::data::Item_Record::*)(Handle<game::data::AttachmentSlot_Record> *, int32_t)>();

constexpr auto EvalArrayTweakDBID = Core::RawFunc<523315084UL, 
    DynArray<TweakDBID> const & (game::data::Val::*)(void)>();

constexpr auto EvalCName = Core::RawFunc<3648983380UL, 
    CName const & (game::data::Val::*)(void)>();

constexpr auto ResolveSuffix = Core::RawFunc<4124714348UL, 
    CString * (*)(void *, CString *, Handle<game::data::Item_Record> &, bool isMale)>();

constexpr auto ResolveVisualTags = Core::RawFunc<1337337421UL, 
    CString * (*)(CName, CString *, Handle<game::data::Item_Record> &)>();

constexpr auto GetItemAppearanceName = Core::RawFunc<3029088864UL, 
    CString * (*)(CString *, Handle<game::Object> const &, Handle<game::Object> const &, Handle<game::data::Item_Record> const &, ItemID const &)>();

template <class T>
struct Span 
{
    T * start;
    T * end;
};

constexpr auto ScheduleSynchronizedAppearanceChanges = Core::RawFunc<386815609UL, 
    void (*)(world::RuntimeSystemEntityAppearanceChanger *, 
        WeakHandle<game::Object> &, 
        Span<world::EntityAppearanceChangeParameter::Key> * old_keys,
        Span<world::EntityAppearanceChangeParameter::Key> * new_keys,
        std::function<void (void)> const &,
        uint32_t //io::EAsyncPriority
    )>();

// CharacterCustomizationSystem
// THandle<game::ui::CharacterCustomizationState> unk78

// could use game::ui::CharacterCustomizationState::Serialize to pass data to server

inline Handle<game::ui::CharacterCustomizationState> * GetCustomizationState(game::ui::CharacterCustomizationSystem * self)
{
    // 2.31a exe audit: self+0x78 is reflection-opaque and the class grew
    // 0x388->0x398 in 2.31 (growth position vs 0x78 unknown), so this offset is a
    // genuine drift RISK. A drifted 0x78 yields a garbage-but-non-null instance
    // that passes a bare null-check and CTDs on the first appearance serialize.
    // Gate it with RTTI: instance+refCount must be non-null AND the pointed-to
    // object must really be a CharacterCustomizationState (a drifted offset lands
    // on a different member whose type will not match). Bail to nullptr on failure.
    auto * h = reinterpret_cast<Handle<game::ui::CharacterCustomizationState> *>((uintptr_t)self + 0x78);
    if (!h->instance || !h->refCount ||
        !h->instance->GetType()->IsA(GetClass<game::ui::CharacterCustomizationState>()))
    {
        spdlog::error("CCS state handle drift: self+0x78 instance={} type={}",
            fmt::ptr(h->instance),
            h->instance ? h->instance->GetType()->GetName().ToString() : "null");
        return nullptr;
    }
    return h;
}
