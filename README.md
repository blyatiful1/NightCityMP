# NightCityMP

**Multiplayer for Cyberpunk 2077 (patch 2.31a).** Roam Night City with your friends: see each other's characters, move, emote, chat — with one of you hosting the session, Minecraft-style.

NightCityMP is a continuation of [CyberpunkMP](https://github.com/tiltedphoques/CyberpunkMP) by Tilted Phoques SRL, whose development stopped in December 2024 (game patch 2.2 era). This project ported it to the current game patch **2.31a** and continues development. It is not affiliated with CD PROJEKT RED or Tilted Phoques SRL.

> ⚠️ **Early days.** The mod is playable and actively developed, but expect rough edges. Check the roadmap below for what works and what doesn't yet.

## What works today

Verified in real play sessions (Linux host + Windows friend over Tailscale):

- Connect / disconnect to a server from inside the game (F7), with on-screen status messages
- See other players as their own V: appearance, clothes and drawn weapon are synced
- Movement replication with walking / sprinting animations
- Player nameplates and chat (F6), with auto-hiding chat panel
- Server-authoritative time of day (everyone shares the same clock)
- Emote wheel, and upstream's demo jobs (taxi, delivery)

Not synced yet: NPCs, traffic and world state (each client still simulates its own crowd), quest progress, combat damage between players.

## Roadmap — "Minecraft-style" multiplayer

The goal is that playing with friends works like a Minecraft LAN session:

1. **MULTIPLAYER entry in the main menu** — Host a session or join one by address. No launch arguments, no console commands, no in-game hotkey magic.
2. **Multiplayer saves** — dedicated saves made for the mod, where everyone keeps *their own* character while sharing the host's session.
3. **One-click hosting** — the game starts the bundled server for you; friends just join.
4. Server builds for both Linux and Windows hosts.

## Installing (players)

Requirements: Cyberpunk 2077 **2.31a** (GOG/Steam/Epic; Proton works — this project is developed on Linux).

1. **Download the player kit** — `NightCityMP-<version>-player.zip` from [GitHub Releases](https://github.com/blyatiful1/NightCityMP/releases). One zip bundles the mod **and** its full runtime stack, so there is nothing else to download or install. (No public release is cut yet; until one is, you can build the kit yourself with [`scripts/make-release-kit.sh`](scripts/make-release-kit.sh) — it pulls the client from a green CI run and the exact pinned dependencies in [`release/assets-manifest.json`](release/assets-manifest.json), verifying every one against its SHA-256.)
2. **Extract it over your game root** — the folder that contains `bin/`, `archive/` and `r6/`. Every file lands where it belongs (`bin/`, `engine/`, `r6/`, `red4ext/`); nothing needs moving afterward.
3. **Launch the game and open MULTIPLAYER from the main menu** — host a session or join a friend by address, Minecraft-style. No launch arguments, no console commands.
   > The main-menu UI is landing now; on builds that predate it, connect with launch args `--launcher-skip --online --ip=<HOST> --port=11778` and press **F7** in-game (**F6** = chat).

Everything the mod depends on is bundled and integrity-checked against pinned hashes: [RED4ext](https://github.com/wopss/RED4ext) 1.30.0, [redscript](https://github.com/jac3km4/redscript) 0.5.31, [Codeware](https://github.com/psiberx/cp2077-codeware) 1.20.3, [ArchiveXL](https://github.com/psiberx/cp2077-archive-xl) 1.26.8, [TweakXL](https://github.com/psiberx/cp2077-tweak-xl) 1.11.3 and [Input Loader](https://github.com/jackhumbert/cyberpunk2077-input-loader) 0.2.3 — all MIT, with full license texts in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). A raw CI `Artifacts.zip` (Actions → *Build windows*) contains **only** the mod itself and still needs that stack.

> **Where to get it:** NightCityMP is distributed through [GitHub](https://github.com/blyatiful1/NightCityMP) and the project's own website **only** — never through Nexus Mods or other third-party mod platforms. The upstream license permits GitHub / own-site distribution and forbids third-party platforms.

## Hosting a server (today: Linux)

```sh
xmake build -y Server.Loader     # or grab a server bundle from Releases (soon)
./scripts/start-server.sh
```

The server listens on UDP 11778 (game) and TCP 11778 (admin API). Set real `CYBERPUNKMP_ADMIN_USERNAME` / `CYBERPUNKMP_ADMIN_PASSWORD` env vars before exposing it beyond localhost. For playing over the internet without port forwarding, [Tailscale](https://tailscale.com/) works well.

## Building from source

Toolchain: [xmake](https://xmake.io) 3.0.9, .NET SDK 8/9, and on Windows MSVC 2022+. Clone with submodules:

```sh
git clone --recursive https://github.com/blyatiful1/NightCityMP.git
xmake -y                      # Linux: server stack
xmake -y Client && xmake pack # Windows: client mod (Artifacts.zip)
```

The client targets game patch 2.31a via a [ported RED4ext.SDK](https://github.com/blyatiful1/RED4ext.SDK/tree/cp2077-2.31a).

## Credits & license

- **Tilted Phoques SRL** — the original [CyberpunkMP](https://github.com/tiltedphoques/CyberpunkMP), which this project is based on. Distributed under the same [license](LICENSE.md) with attribution, as its terms require.
- **WopsS** — RED4ext and RED4ext.SDK · **psiberx** — Codeware, ArchiveXL, TweakXL · **jac3km4** — redscript · **jackhumbert** — Input Loader.

Per the license, this software may only be distributed through GitHub or the project's own website — **not** through third-party modding platforms.
