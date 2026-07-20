# NightCityMP — Shared-World Design (rev 2, 2026-07-20)

Rev 2 = rev 1 after a plan-critic adversarial pass (3 blockers, 5 risks — all
folded in below): creation-gate added to M-CHAR (the shipped deferred connect
would fire mid-edit); GUID-lookup HTTP route added to M-ID (the new-vs-
returning decision previously had no delivery path); vanilla Load Game kept as
JOIN fallback until the auto path is proven; WebPort "fix" dropped (client
targets the typed port for HTTP); N1 re-scoped to config-off until N2;
position-restore descoped to a fast-follow behind a teleport spike; N1
quest-safety spot-check made an explicit ship gate.

User request (verbatim): "concentrate completely on the same save file, a file
that will be saved on the host computer and is shared to the people that
connect. plan this out completely first, it should be easy to connect by
pressing multiplayer and then connecting to the server, no picking characters,
if the player was never on the server, there is a character creation screen.
the most important part of this is, that the world all the players are playing
in, is all streamed through the server, so npc's are all the same on everyones
pcs"

Evidence base: six research reports in `design/research/research-R[1-6].md`
(R1 NPC tech, R2 crowd suppression, R3 character creation, R4 save transfer,
R5 persistence, R6 identity). Every mechanism below cites them; nothing here
is guessed.

## 0. The Minecraft mapping — what "the world lives on the server" means here

Minecraft's server owns one world file; clients are thin views. Cyberpunk
cannot do literally that: the engine must load a LOCAL save to boot a world,
and a `sav.dat` is one opaque blob mixing character + world state with no
seam to merge on (R4 Q4). So the design splits "the world" into three layers,
each with the strongest available authority:

| Layer | Authority | Mechanism |
|---|---|---|
| World BASELINE (map/quest state at join) | server-hosted seed save, downloaded | R4: HTTP download + auto-install; local save = disposable bootstrap cache |
| Player identity & progress (who you are, where, what you look like) | server-side profiles | R5/R6: GUID-keyed profiles; server tells you "here is your character" on join |
| Live world state (time, weather, players, vehicles, NPCs) | server-authoritative runtime sync | WorldClock precedent (shipped); M-NPC extends it to ambient people |

The local save file stops mattering: it is installed automatically, loaded
automatically, and everything the player IS comes from the server. That is
the Minecraft feel, achieved with the grain of the engine instead of against
it.

## 1. Target user experience (the whole flow)

1. Main menu → **MULTIPLAYER** → server address (remembered) → CONNECT.
2. Client asks the server over HTTP: world-seed version + server id + "do you
   know me?" (by locally stored GUID).
3. Client ensures the server's world-seed save is installed locally
   (download ~2 MB on first join / on version change; silent otherwise), then
   auto-loads it. **No save picking, ever.** The vanilla Load Game hand-off
   dies.
4. Returning player: server sends their stored character (appearance,
   equipment, last position) → they spawn where they logged out, as
   themselves. Straight into the world.
5. New player: **character creation** — pick body (M/F), name, appearance
   editor, confirm → connect fires, server stores the new profile.
6. In the world: same clock, same weather, same pedestrians for everyone
   (M-NPC), plus everything already shipped (players, vehicles, chat, emotes).

## 2. The four pillars

### M-ID — Identity & server-side characters (foundation, everything keys off this)
Kill `test`/`testuser`. (R6 + R5)
- Client: persistent random GUID in `<Saved Games>/CD Projekt Red/Cyberpunk
  2077/NCMP-identity.json` — survives kit updates because it is user data,
  not mod install data (R6 Q2; the plugin dir is overwritten by updates).
  Display name entered once in the JOIN dialog (Codeware TextInput already
  there; physical-keyboard entry IS live-verified — 2026-07-20 the friend
  typed a non-default Tailscale address into this exact field on Windows and
  connected, and the user typed into it under wine during test 4; the stale
  "unconfirmed" comment at MainMenu.reds:75-79 gets updated during M-ID).
  Fallback name `Player-<shortguid>` so an unset name never hard-rejects.
- Wire: `AuthenticationRequest` += `guid` field; `username` carries the real
  display name (R6 Q4). Empty-name reject + duplicate-name auto-suffix on the
  server (rejection today is a hard kick with no retry UI — suffix instead).
- Server: `PlayerProfile` struct (native, `NLOHMANN_DEFINE_TYPE_INTRUSIVE`,
  one JSON per GUID under `<server>/players/`) — name, ccstate, equipment,
  body template, position-at-logout, timestamps (R5 Q2 schema, keyed by GUID
  per R6, not username). Loaded/created in `HandleAuthentication`, saved in
  `OnDisconnection` (new hook — R5 seam 7).
- Returning-player inversion: `Level::HandleSpawnCharacterRequest` substitutes
  the STORED ccstate/equipment for what the client sent, and a new
  `NotifyOwnCharacterLoad` message (field 13) tells the owning client to apply
  it to the local V via the existing `ApplyAppearance` primitive (R5 Q3 —
  message shape copied from `NotifyCharacterLoad`).
- POSITION RESTORE IS DESCOPED from the first M-ID cut (plan-critic): no
  client-side "teleport local player" API is known (R5 gap). M-ID v1 spawns
  at the save's default; a TeleportationFacility gate-spike runs during M-ID
  and position restore ships as a fast-follow only once the spike proves an
  API exists.
- NEW (plan-critic blocker 2): the "does the server know me?" answer needs a
  delivery path usable BEFORE any save is loaded (the game-protocol handshake
  only fires after world attach). M-ID therefore includes an HTTP route on
  the existing EmbedIO surface — `GET /api/v1/players/<guid>` → `{known,
  bodyTemplate, name}` — implemented in the C# WebApi by reading the
  native-written `players/<guid>.json` files off disk (the store is plain
  JSON precisely so both layers can read it). Registered before the
  admin-auth module like mods/statistics.
- Security posture, stated honestly: the GUID is a bearer token. Friends-server
  trust, no anti-cheat, consistent with the codebase's existing posture (R6 Q3).
- Effort: ~1–2 sessions. Needs one Windows CI round (client DLL + server).

### M-WORLD — Server-hosted world seed (the "same save file" pillar)
The host's canonical save is served to every client. (R4)
- Server: `GET /api/v1/world-save/` (sav.dat, ~2 MB) + `/api/v1/world-save/meta`
  (JSON: server_id GUID, version counter, sha256, size) registered BEFORE the
  admin-auth module like mods/statistics so players don't need admin
  credentials (R4 Q1). The `Port`→`WebPort` mismatch is left ALONE
  (plan-critic): HTTP deliberately stays on the same number the player typed
  (:11778 TCP next to the game's UDP — independent namespaces, verified
  harmless), so the client derives its HTTP base from the typed address with
  zero extra config. Binding WebPort would break exactly that.
- Client: WinHTTP download (`add_syslinks("winhttp")` — zero new third-party
  deps, matches the raw-Win32 style of SaveManager; GNS game protocol is the
  wrong tool: 512 KiB hard per-message cap, no chunking infra — R4 Q2).
- Install: new native `InstallDownloadedSave(serverId, bytes...)` writing
  `NCMP-<server-id>/{sav.dat, metadata.9.json}` (screenshot omitted, saves
  100 KB), following the existing seed-install + metadata-rewrite patterns
  (R4 Q3). Version sidecar file per server id (NOT inside CDPR's
  metadata.9.json schema).
- JOIN flow wiring at the `RouteToMpSaveSelection` stub (the deliberately
  deferred P3 seam): check meta → download if absent/stale → resolve the save
  index by name via `RequestSavesForLoad`/`OnSavesForLoadReady` (index =
  array position, re-resolved fresh every time) → `LoadSavedGame(idx)`.
  All of this happens BEFORE the game protocol handshake, which fires only
  after world attach — so HTTP, not the auth response, must carry the version
  signal (R4 Q4).
- FALLBACK KEPT (plan-critic blocker 3): the vanilla Load Game hand-off does
  NOT die on day one. Any failure in the auto path (download error, install
  failure, index-resolution miss, load race) drops the player into the
  current, live-verified Load Game flow with a short notice — joining must
  never become impossible because the new path hiccuped. The hand-off is
  removed only after the auto path has survived real friend-server use.
- Update semantics — DECIDED: **one-way ratchet (R4 option B) + server-side
  progress (option C's spirit)**: the server's seed installs on first join or
  when the server operator bumps the world version; it never silently clobbers
  a local copy mid-session. Player progress does NOT live in that file — it
  lives in M-ID profiles and the runtime sync layer. The seed is the world's
  SPAWN state, like a Minecraft world generator seed, not a continuously
  merged save. (True continuous world-file merging is impossible without
  reverse-engineering the sav.dat format — R4 flags this honestly.)
- Seed content: TWO neutral saves (M/F body — required because body/voice
  cannot change via ccstate) produced by hand from a fresh post-prologue
  playthrough with default appearance and plain default gear (R3 "neutral
  template" — today's NCMP-Template-F is a clone of the user's personal V and
  gets replaced). The server serves the one matching the player's body choice.
- Effort: ~3–5 sessions (plan-critic: the download/install/load chain is
  Windows-only native client code — the highest-CI-iteration-cost work in the
  plan; budget multiple Windows CI rounds, it will not land first try) + one
  hand-production session for the neutral saves (M-body save must be created
  in-game first — none exists on this machine).

### M-CHAR — Character creation screen (first-join flow)
- DECIDED: design (c) from R3 — a custom Codeware ink editor driving the
  game's own `gameuiICharacterCustomizationSystem` API (`InitializeState`,
  `GetUnitedOptions`, `ApplyChangeToOption`, `FinalizeState`,
  `SetIsBodyGenderMale` …) — every call is a confirmed script-import on
  2.31a (R3 Q2/Q3). The vanilla creator is pregame-only (menu-scenario chain
  cannot run in-world), and the in-game mirror scenario has NO script-visible
  trigger (native/quest-invoked only) — both dead ends confirmed, not
  assumed (R3).
- Flow: `GET /api/v1/players/<guid>` says unknown → JOIN UI adds the creation
  step: body M/F pick (= which seed save downloads) + name → world loads →
  NCMP creation overlay opens over the world → player edits appearance (live
  on their V; `ScheduleSynchronizedAppearanceChanges` is already bound native
  if the option-apply needs a nudge) → CONFIRM → connect fires → the existing
  one-shot ccstate upload captures the finished look → server stores the
  profile (M-ID).
- CREATION GATE — REAL NEW WORK (plan-critic blocker 1, was wrongly claimed
  free in rev 1): the shipped deferred connect fires on equipment-ready OR a
  hard 15 s timeout — both would trigger MID-EDIT and upload the unedited
  neutral face (the upload is one-shot; no re-upload path exists). M-CHAR
  adds a redscript hold: while the creation overlay is open, the deferred
  connect's fire condition is suppressed and only CONFIRM releases
  `Connect()`. Small, but it must exist before any creation UI does.
- Staged delivery: v1 = body pick + name + preset/randomize baseline
  (`ApplyUIPreset`/`RandomizeOptions`) with a handful of key options; v2 =
  full slider/option editor (the option→UI mapping is substantial hand-work).
- Known unknown (R3): whether `ApplyChangeToOption` refreshes the live V mesh
  outside the pregame preview controller — first implementation step is a
  spike that answers exactly this in-game before UI work starts.
- Effort: v1 ~2 sessions (after the spike), v2 +2–4 sessions.

### M-NPC — Shared ambient world (the headline: same NPCs on every PC)
- DECIDED architecture (R1 + R2), three stages with honest fidelity labels:
  1. **N1 — suppress local ped randomness (days), SHIPPED OFF BY DEFAULT:**
     on connect, `GameInstance.GetCommunitySystem(...).ChangeDensityModifier(0.0)`;
     `ResetDensityModifier()` on disconnect — runtime, connect-scoped,
     dump-verified native, believed quest-NPC-safe (acts on the ambient
     DynamicCrowd only; corroborated by the Disabled Crowd mod's "mission
     characters not removed") (R2). HONEST SCOPE (plan-critic): this is
     PEDS-ONLY — ambient vehicle traffic has no runtime kill switch and stays
     divergent between players through N1–N3. Empty sidewalks + mismatched
     cars would FEEL like a regression on a 2–3-friend server, so N1 ships as
     a config toggle defaulting to vanilla crowds, and flips on together with
     N2 when server pedestrians exist to fill the streets. Ship gates for
     N1: a live quest-safety spot-check (R2's residual UNVERIFIED risk) and
     the compile-gate probe of the CommunitySystem calls.
  2. **N2 — server-owned pedestrians (weeks):** server keeps a deterministic,
     persistent NPC roster (seeded spawner around the player centroid,
     roster in the world state next to world-clock.txt). Spawn path: extend
     `NotifyCharacterLoad` with a `record_id` field (today the client
     hardcodes MaMuppet/WaMuppet — R1 Q2) so the server can spawn civilian
     records with `ReactionPresets.NoReaction` (the shipped AI-off precedent,
     CyberpunkMP.tweak:71). Clients render them through the EXISTING tagged
     puppet path — interpolation, appearance, everything reused with zero
     client render changes (R1 Q3: remote players ARE externally-driven NPC
     puppets already). Server drives motion as model A: ownerless flecs
     entity + MovementComponent set server-side, auto-replicated to all by
     the existing observer — cheat-proof, identical on every PC, but
     waypoint/loiter motion only (the server has no navmesh) (R1).
  3. **N3 — natural walking (weeks, after N2):** authority-client delegation
     (model B): the server parents each NPC to one client (the host player by
     default); that client computes real navmesh paths
     (`NavigationSystem.CalculatePathOnlyHumanNavmesh`) and drives
     `AIMoveToCommand`, streaming positions back exactly like its own puppet;
     the existing authority check already permits it (`child_of(player)`)
     (R1). Hand-off on disconnect/range is the hard part and is designed
     server-side (reassign parent, N2 motion as fallback).
  4. **N4 — vehicle traffic (stretch, months):** explicitly OUT of the
     committed plan. No runtime traffic-off exists (only a boot-time ini that
     would kill traffic offline too — R2), driverless vehicle motion has no
     proven path and the vehicle code is the most fragile in the tree (R1
     Q4). Vanilla ambient cars stay on and divergent between players for now
     — stated honestly instead of promised. Revisit after N3 ships.
- Per-NPC cost is real (each is a full dynamic puppet, far heavier than a
  vanilla crowd member — R1): N2 targets ~20–30 pedestrians in a bubble
  around the players, not vanilla-density streets. Density can grow with
  profiling.
- Effort: N1 days; N2 ~2–3 weeks of sessions; N3 +2–3 weeks; N4 unbounded.

## 3. Phase order & why

1. **M-ID** — identity + profiles + the `/players/<guid>` route; smallest; one CI round. (Position restore descoped to a fast-follow behind the teleport spike.)
2. **M-WORLD** — the join UX transformation (no save picking, vanilla flow kept as fallback). Only loosely coupled to M-ID: the seed-serving pillar needs just its own server_id; the do-you-know-me route is M-ID's (plan-critic dependency correction).
3. **M-CHAR v1** — needs M-ID (profile store + route) + M-WORLD (seed download by body pick). Starts with TWO spikes: ApplyChangeToOption live-mesh, and the creation-gate hold on the deferred connect.
4. **M-NPC N1** — tiny, ships dark (config off) behind its quest-safety spot-check.
5. **M-NPC N2 → N3** — the long arc; starts once M-WORLD is stable; N1 flips on with N2.
6. M-CHAR v2 (full editor) and M-NPC N4 as capacity allows.

Milestone framing for the user: after M-ID+M-WORLD (~1.5–2 weeks of sessions):
"press MULTIPLAYER, connect, you're your character in the server's world."
After M-CHAR v1 (+few days): "first-timers create their character."
After N2 (+weeks, with N1 flipping on): "the same pedestrians on every PC."
After N3 (+weeks): "they walk naturally." Ambient CARS stay per-player until
the N4 stretch — said plainly here because it will be visible.

## 4. Open decisions for the user (none block M-ID start)

- Vanilla ambient TRAFFIC stays divergent (different cars per player) until
  the N4 stretch. Acceptable? (No good alternative exists — see R2/R1; the
  only full traffic kill is a boot-time ini that would also kill it offline.)
- World-seed resets: when the operator bumps the world version, everyone's
  local copy is replaced (character/appearance/position survive server-side
  in profiles). OK?
- (Decided by plan-critic, veto if you disagree: N1 crowd suppression ships
  config-OFF and only flips on when server pedestrians (N2) exist — avoids an
  empty-streets interim.)

## 5. Honest limits (so nobody is surprised later)

- Quest/story NPCs and quest STATE are not synced by any of this — story
  content stays per-player (engine scene system, out of any mod's reach today).
- The world seed is a spawn baseline, not a continuously merged world file —
  the sav.dat format has no exploitable character/world seam (R4).
- GUID identity is friends-grade trust, not accounts/anti-cheat (R6).
- All NPC fidelity claims above are for AMBIENT pedestrians; combat/police
  sync is a separate future subsystem entirely (nothing exists in TP core).
