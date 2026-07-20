FINDINGS — R2: Suppressing/limiting vanilla ambient crowds & traffic on 2.31a

## 1. LOCAL GAME FILES (proven)

**Shipped engine inis contain NO crowd/population/traffic keys.** `grep -rniE 'crowd|population|traffic|pedestrian|community|spawn'` over `/home/crocco/Games/Heroic/Cyberpunk 2077/engine/config/` returns empty. The only base inis present are animation/general/multiplayer/rendering/resources/scenesystem/scripts/smartobjects (`engine/config/base/`) plus `platform/pc/{input_loader,platformgameplay,rendering}.ini`. So crowd control inis are NOT present by default — a modder must ADD an ini under `engine/config/platform/pc/`.
- Note: `engine/config/base/multiplayer.ini` exists (the CyberpunkMP net config: `[NetworkEmulation]`, `[Replication]`, `[Multiplayer]` ClientTargetTickRate=30) — unrelated to crowds, just confirming the mod already writes engine inis.

**In-game "Crowd Density" setting CANNOT reach zero.** `r6/config/settings/platform/pc/options.json:454-476`: option `CrowdDensity`, `type: name_list`, `values: ["Low","Medium","High"]`, `default_index: 2` (High), `is_visible: false`, `in_game: true`, `update_policy: "immediately"`. Floor is **Low**, no Off/zero entry. It is runtime-changeable but cannot suppress crowds — insufficient alone. (Duplicated at `r6/config/settings/options.json:1554`.)

## 2. REDMOD SCRIPT DUMP (dump-verified, redscript-callable) — the ideal runtime route

**`CommunitySystem` (native) exposes exactly the runtime crowd controls we want** — `core/systems/communitySystem.script:28-34`:
```
final class CommunitySystem extends ICommunitySystem {
  EnableDynamicCrowdNullArea(areaLocalBBox:Box, areaLocalToWorld:WorldTransform, savable:Bool, duration:Float) : Uint64;
  DisableCrowdNullArea(areaId:Uint64);
  ChangeDensityModifier(modiefier:Float);   // sic — typo in CDPR import
  ResetDensityModifier();
}
```
- Getter: `GameInstance.GetCommunitySystem(self:GameInstance) : CommunitySystem` — `core/systems/gameInstance.script:16` (also on PS context, `core/gameplay/psmImports.script:258`).
- `ChangeDensityModifier(0.0)` = runtime, float-tunable ambient-crowd density scale → set on connect, `ResetDensityModifier()` on disconnect. This is connect-scoped and reversible — exactly "crowds OFF only while connected."
- `EnableDynamicCrowdNullArea(...)` = regional hard suppression of the **dynamic (ambient) crowd**; returns an id you `DisableCrowdNullArea()` on disconnect. Both functions name-scope to *DynamicCrowd*, i.e. ambient population, not quest/scene spawns.

**Traffic (vehicles) has NO scripted suppression API.** `TrafficSystem` — `core/systems/trafficSystem.script:1-5` — exposes only queries (`IsPathIntersectingWithTraffic`, `FindEntitiesNearPlane`). `GameInstance.GetTrafficSystem` exists (`gameInstance.script:52`) but there is no density/disable setter. → runtime vehicle-traffic off is NOT achievable via redscript.

**Per-NPC (not a global toggle):** `CrowdMemberComponent` — `core/components/crowdMemberComponent.script` — `TryStopTrafficMovement()`, `ChangeMoveType()`, `IsInCrowd()`; per-entity, useless for global suppression. `EntitySpawnerEventsBroadcaster` (communitySystem.script:15-22) lets you *listen* to spawn/despawn events (useful to detect/cull ambient spawns) but not prevent them.

**No separate PopulationSystem/CrowdSystem class in the dump** — only `ICommunitySystem`/`CommunitySystem` (grep for class defs). `preventionSpawnSystem` is police-only (`DynamicVehicleType`, `SpawnRequestResult`), not ambient population.

## 3. TweakXL route (dump-verified records exist, but weak for suppression)

`CrowdSettingsPackageBase_Record` / `CrowdSlotMovementPatternBase_Record` / `CrowdSlotMovementSettingsBase_Record` — `core/data/tweakDBRecords.script:3983-3999`. These govern crowd **movement patterns/behavior**, not spawn budget. No spawn-cap-to-zero flat is exposed in the scripted TweakDB surface, and the modding scene puts spawn budgets in engine inis (not TweakDB — see §4). → TweakXL is good for tweaking crowd *behavior* but is NOT the lever for suppressing spawn counts. Spawn-budget-via-TweakXL: UNVERIFIED.

## 4. WEB-SOURCED (ini route — boot-time, all-or-nothing)

Community "disable crowds" mods work by dropping an ini into `engine\config\platform\pc\` with a `[Crowd]` section. Exact keys (from Alternate Crowd Behavior mod docs / stoker25's ini dump):
- `[Crowd]`: `Enabled=true`, `EnablePedestrians=true`, `EnableVehicles=true`, `SpawnLimit=69999`, `MinStreamingVelocityNormalizedToBlockSpawn`, `UseFrustum`, `DespawnLastSeenMinTime=120`. Setting `EnablePedestrians=false` / `EnableVehicles=false` (or `Enabled=false`) disables ambient peds/vehicles. `[CrowdMovement]` holds 60+ behavior params. (cyberpunk2077mod.com/alternate-crowd-behavior; nexusmods 7159 "Psycho Crowds", 526.)
- The "Disabled Crowd" mod (Drahsid) ships an `engine` folder and its own description states it removes street pedestrians and vehicles while **"mission characters will not be removed"** — direct corroboration that the ini crowd-off does NOT touch quest NPCs. (umodder.com/archive/35141; modslab 2HN8f2iKQr.)
- **`EnableVehicles=false` is the ONLY proven full vehicle-traffic kill switch** (fills the §2 gap), but it is a boot-time static file → crowds/traffic would also be OFF offline. Not connect-scoped without extra logic.

## RANKED MECHANISMS

| Rank | Mechanism | Source class | Runtime? | Connect-scoped? | Peds | Vehicles | Quest-NPC safe? |
|---|---|---|---|---|---|---|---|
| 1 | `CommunitySystem.ChangeDensityModifier(0.0)` on connect / `ResetDensityModifier()` on disconnect | dump-verified `communitySystem.script:31-32` | **Yes, tunable float** | **Yes** | Yes | Likely no (peds only) | Yes (DynamicCrowd only) |
| 2 | `EnableDynamicCrowdNullArea(box,tf,false,dur)` around player + `DisableCrowdNullArea(id)` on disconnect | dump-verified `communitySystem.script:30,31` | Yes, regional | Yes | Yes | UNVERIFIED | Yes (DynamicCrowd only) |
| 3 | `[Crowd] EnablePedestrians=false` / `EnableVehicles=false` ini in `engine/config/platform/pc/` | web (nexus 7159/526/175) + preserves-quest confirmed | No (boot only) | **No — off offline too** | Yes | **Yes (only proven vehicle-off)** | Yes (proven by Disabled Crowd mod) |
| 4 | `CrowdDensity` → "Low" via options.json | local `options.json:454` | Yes (immediately) | possible | floor Low, ≠0 | no | Yes |
| 5 | TweakXL `CrowdSettingsPackage*` records | dump `tweakDBRecords.script:3983` | load-time | No | behavior only | no | Yes |

## RECOMMENDATION / RISKS
- **Primary (connect-scoped, ideal):** #1 `ChangeDensityModifier(0.0)` on server-connect, `ResetDensityModifier()` on disconnect, reinforced by #2 null-area(s) around each player. Both are dump-verified importonly natives → should pass the redscript compile gate; call via `GameInstance.GetCommunitySystem(GetGameInstance())`. This keeps vanilla crowds fully intact OFFLINE and suppresses ambient population only while connected.
- **Vehicle-traffic gap:** there is NO runtime scripted traffic-off. If ambient cars must also vanish while connected, options are (a) accept `[Crowd] EnableVehicles=false` ini = traffic off offline too, or (b) a native RED4ext hook on the traffic/crowd system (out of R2 scope). Whether `ChangeDensityModifier` also thins traffic is UNVERIFIED — treat as peds-only.
- **Quest-NPC safety:** the CommunitySystem levers act on the *DynamicCrowd* (ambient) subsystem and are corroborated quest-safe by the ini "Disabled Crowd" mod ("mission characters will not be removed"). Residual UNVERIFIED risk: a minority of missions gate on ambient community NPCs; density 0 / null-area over a scripted-community zone could thin those — low risk, worth a live spot-check (needs runtime; not testable read-only here).
- **`duration`/`savable` semantics** of `EnableDynamicCrowdNullArea` (does duration=0 mean permanent? does savable persist to save file?) are UNVERIFIED from the dump signature alone — verify empirically before shipping a persistent null area.

Sources: https://www.nexusmods.com/cyberpunk2077/mods/7159 · https://www.nexusmods.com/cyberpunk2077/mods/526 · https://www.nexusmods.com/cyberpunk2077/mods/175 · https://www.nexusmods.com/cyberpunk2077/mods/248 · https://www.umodder.com/archive/35141 · https://www.cyberpunk2077mod.com/alternate-crowd-behavior/ · https://www.thegamer.com/cyberpunk-2077-mod-unlocks-crowd-density-setting/