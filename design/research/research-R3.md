Evidence complete. Structured findings below.

---

# R3 — In-session character creation screen: findings

## Q1 — Appearance tooling already in TP core

**Native RawFuncs bound in `code/client/Game/CharacterCustomizationSystem.h`** (all keyed to 2.31a offsets/hashes):
- `CreateHandle_CharacterCustomizationState` (hash 2710710832) — allocates a `game::ui::CharacterCustomizationState` handle. (H:14)
- `CharacterCustomizationState_InitFromPreset` (1993027039) — populate a state from a `CharacterCustomizationPreset`. (H:18) — **bound but unused anywhere in repo.**
- `CharacterCustomizationState_Serialize` (108403442) — the ccstate blob (de)serializer, used both directions. (H:21)
- `ScheduleSynchronizedAppearanceChanges` (386815609) on `world::RuntimeSystemEntityAppearanceChanger` — the native live-appearance-swap call. (H:69) — **bound but commented/unused; no caller in repo.**
- Item/appearance-suffix helpers: `GetItemRecord`, `GetPlacementSlot`, `ItemID_Create`, `ResolveSuffix`, `ResolveVisualTags`, `GetItemAppearanceName`, `GetGameSettings`. (H:33-62)
- `IsCustomizationStateReady(system)` + `GetCustomizationState(system)` — read the live state at `system+0x78`, RTTI-gated against 2.31a offset drift. (H:98-135)

**How it's wired today (the load-bearing seam for creation):**
- Local upload: `NetworkService.cpp:155-188` polls `IsCustomizationStateReady`, then `GetCustomizationState(ccSystem)` → `CharacterCustomizationState_Serialize(state, &writer)` → `request.set_ccstate(...)`. This is a **one-shot at spawn**, 30 s window (`kSpawnCcstateTimeout`, NetworkService.cpp:20,123). **The upload simply snapshots the local V's live CCS at connect time — there is no re-upload-on-change path.**
- Remote apply: `NetworkWorldSystem.cpp:46-53` and `AppearanceSystem.cpp` `ApplyAppearance` deserialize the blob into a fresh state and drive equipment via `AddItems` (TransactionSystem `GiveItem`/`AddItemToSlot`), TPP forced via `PuppetPS.unk72[0]=1` (AppearanceSystem.cpp).
- Reds side (`code/assets/redscript/World/AppearanceSystem.reds`): `native class AppearanceSystem` exposes `ApplyAppearance`, `GetPlayerItems`, `IsEquipmentReady`; puppets tagged `CyberpunkMP.Puppet` get appearance applied on `Entity/Attached`.

**Verdict:** TP core has full ccstate serialize/deserialize + equipment reconstruction, plus a bound-but-dormant native live-appearance-changer. It has **no editor UI, no mirror trigger, no preset-picker** — appearance is captured passively from whatever V looks like at connect.

## Q2 — Vanilla 2.31a: is the full creator invocable outside intro?

**The full new-game creator is a chain of pregame menu scenarios** (`cyberpunk/UI/fullscreen/pregame/preGameScenarios.script`):
- `MenuScenario_LifePathSelection` (:650) → `MenuScenario_BodyTypeSelection` (:681, opens `gender_selection`) → `MenuScenario_CharacterCustomization` (:707) → `MenuScenario_StatsAdjustment` (:741) → `MenuScenario_Summary` (:771).
- `MenuScenario_CharacterCustomization.OnEnterScenario` opens `player_puppet` + `character_customization` menus with a `MorphMenuUserData` (:713-719). These are **`MenuScenario_PreGameSubMenu`** — they run in the **pre-game menu container** (no game world). They cannot be entered once a save is loaded; the whole gender/lifepath/stats scaffold is pregame-only. **The FULL creator is NOT invocable in-session.**

**The in-game mirror (2.0+ appearance change)** — `cyberpunk/UI/fullscreen/ingame/inGameScenarios.script`:
- `MenuScenario_CharacterCustomizationMirror extends MenuScenario_BaseMenu` (:287) opens `character_customization_scenes` then, on `OnCCOPuppetReady`, `player_puppet` + `character_customization` with a `MorphMenuUserData` (:293-310). It **reuses the same `character_customization` menu** as the creator but runs in the **in-game** menu container.
- **CRITICAL GAP:** searching the entire dump, `MenuScenario_CharacterCustomizationMirror` / `'character_customization_scenes'` appear **only** in `inGameScenarios.script` — **nothing in scripts requests/switches to this scenario.** It is triggered **natively** (engine/quest-scene driven by the mirror device interaction). There is **no script-visible entry point** (no `SwitchToScenario`, no menu-request event) to launch the mirror on demand. This is the biggest unknown for designs (a)/(b).
- What the mirror can edit: gated by `gameuiICharacterCustomizationSystem` option queries. The system exposes `GetHeadOptions`, `GetBodyOptions`, `GetArmsOptions`, `GetUnitedOptions(head,body,arms,...)`, `HasOption`, `HasTag`, plus `ApplyChangeToOption`, `ApplyUIPreset`, `ApplyEditTag`, `RandomizeOptions`, `InitializeState/FinalizeState/ReFinalizeState/CancelFinalizedStateUpdate`, `GetState` (`characterCreationMenu.script:96-118`). The community-known constraint (matches `code/assets/Saves/README.md:40`): the in-game mirror covers **hair/face/makeup/tattoos/cyberware/body-morph sliders but NOT body-frame gender or voice** — those are set only via `State.SetIsBodyGenderMale`/`SetIsBrainGenderMale` (`characterCreationMenu.script:80-82`), which the mirror path does not expose. UNVERIFIED whether the mirror in 2.31a exposes body-morph sliders vs hair/makeup-only — the dump doesn't encode the per-option in-mirror editability (it's data/quest-driven).

**System accessor exists in-world:** `GameInstance.GetCharacterCustomizationSystem(GameInstance)` (`core/systems/gameInstance.script:87`) — so the *system* API is reachable from an in-session script; only the *menu scenario* lacks a script trigger.

**The in-game customization controller** (`inGameCharacterCustomizationGameController.script`) equips `Items.CharacterCustomizationMaHead`/`WaHead`/`CharacterCustomizationArms` on the preview puppet and strips underwear per `IsNudityAllowed()` — this is the puppet-prep the mirror menu drives.

## Q3 — Cleanest way to editor + capture ccstate

The capture side is **already solved and passive**: `NetworkService.cpp:183-188` serializes the live CCS at connect. So the only real work is (i) getting the player into an editor while on a template save, and (ii) ensuring the edited state is what gets captured (edit *before* connect, or add a re-upload message — the current one-shot upload will NOT pick up post-connect edits).

Two clean patterns:
- **Edit-before-connect:** open the editor during the post-load, pre-`Connect()` window. `NetworkAutoConnect.reds` already defers `Connect()` behind `IsEquipmentReady()` polling (up to ~15 s) — a creation gate could hold the deferred connect open until the player confirms appearance, so the existing one-shot upload captures the finished look. No protocol change.
- **Re-upload after edit:** add a client→server ccstate-update message so appearance changes propagate anytime. Larger (protocol + server + remote re-apply), but needed if editing happens after spawn or for later re-customization.

---

# Three creation-screen designs (ranked)

### (a) Invoke the vanilla in-game mirror scenario directly — HIGHEST fidelity, HIGHEST risk
Drive `MenuScenario_CharacterCustomizationMirror` (inGameScenarios.script:287) right after the template save loads, capturing the result through the existing ccstate upload.
- **Evidence:** scenario exists (inGameScenarios.script:287-311); reuses `character_customization` menu; capture path already live (NetworkService.cpp:183-188).
- **Blocking open question:** **no script trigger found** — the scenario is native/quest-invoked. Must find how the mirror device fires it (RE the native menu-request, or a quest phase / `interactionChoice`), or find a menu-request event that accepts a scenario CName. If no scriptable trigger exists, this design is **not reachable from the mod** without native code.
- **Also open:** does the mirror expose only hair/makeup on 2.31a? If so it can't fully differentiate two characters sharing one template. Needs live test.
- **Effort:** LOW if a trigger is found (reuse everything); HIGH/uncertain if it requires native reverse-engineering of the menu-request. Fidelity: full vanilla mirror.

### (b) Vanilla mirror via a real mirror device / staged trigger — HIGH fidelity, MEDIUM effort
Rather than synthesize the scenario, reuse the game's own path: place/point the player at an appearance-change mirror (or replay the interaction the mirror device uses) so the engine opens the scenario the supported way, then capture on connect.
- **Evidence:** mirror flow is the intended in-game route (inGameScenarios.script:287); `inGameCharacterCustomizationGameController` handles puppet prep (whole file); template README already assumes "the appearance mirror covers hair/face/makeup" (README.md:40).
- **Open questions:** how the mirror device requests the menu (device/interaction wiring not in the redmod script dump — likely in world/quest data); whether it can be triggered without a specific worldspace mirror prop; whether body-frame is editable. Same hair/makeup-only caveat as (a).
- **Effort:** MEDIUM — depends on locating a device/interaction that legitimately opens the scenario and staging it at the template spawn point. Fidelity: full vanilla mirror (whatever it natively allows).

### (c) Custom Codeware ink editor driving `gameuiICharacterCustomizationSystem` — MEDIUM fidelity, HIGH-but-known effort, LOWEST risk
Build an in-session overlay (same Codeware.UI pattern as `MainMenu.reds`) that calls the customization **system** API directly — no menu scenario needed, so no native-trigger unknown.
- **API in hand (all `import` = callable):** `GameInstance.GetCharacterCustomizationSystem(game)` (gameInstance.script:87); `InitializeState`, `GetState`, `GetHeadOptions/GetBodyOptions/GetArmsOptions/GetUnitedOptions`, `ApplyChangeToOption(option,newValue)`, `ApplyUIPreset`, `RandomizeOptions`, `FinalizeState`/`ReFinalizeState` (characterCreationMenu.script:100-118); `State.SetIsBodyGenderMale`/`SetIsBrainGenderMale` (:80-82). Capture: existing NetworkService.cpp:183-188 path (or serialize via `CharacterCustomizationState_Serialize`, already bound, CharacterCustomizationSystem.h:21).
- **Design:** load template → open overlay → enumerate `GetUnitedOptions` → render sliders/pickers in Codeware ink → `ApplyChangeToOption` live on the preview → `FinalizeState` on confirm → let deferred `Connect()` capture. Body-frame stays fixed by the M/F template choice (matches the 2-template reality); brain-gender/voice untouched.
- **Open questions:** whether `ApplyChangeToOption` updates the live V mesh outside the pregame puppet-preview controller (it registers a `PuppetPreviewGameController`, characterCreationMenu.script:120 — may need a live preview target or `ScheduleSynchronizedAppearanceChanges`, CharacterCustomizationSystem.h:69, to reflect changes on the real body); whether `HasCharacterCustomizationComponent(V)` holds in-session (it does for player V per `inGameCharacterCustomizationGameController`); reproducing the option→UI mapping is substantial hand-work.
- **Effort:** HIGH but fully de-risked (no native unknowns; every call is a confirmed `import`). Fidelity: as deep as the option list allows (full head/body/arms sliders), but the UI is bespoke, not CDPR-polished.

**Recommendation for the orchestrator:** (c) is the only design with **zero native-trigger unknowns** and it reuses the already-working passive capture; pursue (a)/(b) only after RE confirms a scriptable or device-stageable mirror trigger exists on 2.31a. All three converge on the same capture seam (NetworkService.cpp:183-188), so the editor is the only new surface.

---

# "Neutral" template requirement (replacing today's NCMP-Template-F)

Today's `NCMP-Template-F` is a clone of the user's personal V (`code/assets/Saves/README.md`: "from a pristine 2.31a post-prologue Female V StreetKid save") — so every new female character **starts wearing the user's face** until edited. For a creation flow, "neutral" means:
- A **default/preset appearance**, not the user's — ideally the creator's default preset for that body (`ApplyUIPreset` / `RandomizeOptions` baseline) so edits start from a blank slate, not someone's identity.
- **Post-prologue open-world reachable**, `isModded=false`, `saveVersion=269`, `gameVersion 2310` (README.md template requirements) — unchanged.
- **Both M and F** produced (NCMP-Template-M is still TODO per README.md) since body-frame/voice can't change via ccstate — the two templates ARE the body/voice choice; the editor only does head/hair/makeup on top.
- **Stripped loadout ideal:** since equipment is synced separately (`GetPlayerItems`/`IsEquipmentReady`, AppearanceSystem.reds), a neutral template should carry a plain default outfit so new characters don't inherit the user's gear. UNVERIFIED whether the current F template was gear-stripped.
- Produced **by hand per game patch** (README.md: "game-patch-coupled and cannot be automated").

**Files:** `code/client/Game/CharacterCustomizationSystem.h`, `code/client/App/Network/NetworkService.cpp`, `code/client/App/World/{NetworkWorldSystem,AppearanceSystem}.cpp`, `code/assets/redscript/World/{AppearanceSystem,NetworkAutoConnect}.reds`, `code/assets/redscript/NightCityMP/MainMenu.reds`, `code/assets/redscript/Saves/SaveManager.reds`, `code/assets/Saves/README.md`; dump: `cyberpunk/UI/fullscreen/{ingame/inGameScenarios.script, pregame/preGameScenarios.script, pregame/characterCreationMenu.script, ingame/inGameCharacterCustomizationGameController.script}`, `core/systems/gameInstance.script:87`.