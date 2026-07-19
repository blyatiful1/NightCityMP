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

1. Download the latest release zip (GitHub Releases — first packaged release coming soon; until then, the client mod is built by CI on every push, see Actions → *Build windows* → `Artifacts.zip`, and needs the runtime stack below).
2. Extract it over your game root folder (the one containing `bin/`, `archive/`, `r6/`).
3. Start the game. Until the main-menu UI lands, connecting uses launch args `--launcher-skip --online --ip=<HOST> --port=11778` and F7 in-game (F6 = chat).

The full runtime stack the mod depends on: [RED4ext](https://github.com/WopsS/RED4ext) 1.30+, [redscript](https://github.com/jac3km4/redscript) 0.5.31, [Codeware](https://github.com/psiberx/cp2077-codeware) 1.20+, [ArchiveXL](https://github.com/psiberx/cp2077-archive-xl), [TweakXL](https://github.com/psiberx/cp2077-tweak-xl), [Input Loader](https://github.com/jackhumbert/cp2077-input-loader). Release zips bundle all of it; CI artifacts contain only the mod itself.

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
