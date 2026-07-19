#include "RED4ext/Scripting/Natives/Generated/cp/PlayerSystem.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/Object.hpp"

namespace Game
{
// 2.31a exe audit: the hand-declared vtable slots below drifted. The 6 filler
// stubs mislaid GetLocalPlayerControlledGameObject at vtable+0x138 instead of the
// RE'd +0x1E0 (the SDK base vtable ends at 0x100 and the required 0x108..0x1A8
// filler virtuals were missing), so a raw virtual dispatch invoked the wrong
// method (ctd-on-first-use). Callers now use Red::CallVirtual(...) name dispatch,
// so the fake virtuals are removed entirely.
struct PlayerSystem : Red::PlayerSystem
{
};
}