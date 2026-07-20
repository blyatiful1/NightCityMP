# NCMP template save seeds

STATUS 2026-07-20: **NCMP-Template-F is produced and live** (from a pristine
2.31a post-prologue Female V StreetKid save; metadata `name` rewritten;
install verified live: client logged "installed template 'NCMP-Template-F'"
and the folder appeared in the player's Saved Games). NCMP-Template-M is
still TODO (no male-body save exists yet to seed it from). The release kit
overlays these seeds into the player zip (see scripts/make-release-kit.sh).

This directory holds the **pristine MP template character saves** that the
NightCityMP client installs into the player's Cyberpunk 2077 save directory.
The template saves themselves are **not code** — they must be produced by hand,
in-game, with the user (they are game-patch-coupled and cannot be automated;
re-produce per game patch). This README is the registration stub + spec; the
native + redscript scaffolding around it is already implemented.

## Expected layout (populate during the hand-production session)

```
code/assets/Saves/
├── NCMP-Template-M/          <- male-body clean template
│   ├── sav.dat
│   ├── metadata.9.json       ("name": "NCMP-Template-M", isModded=false, saveVersion 269)
│   └── screenshot.png
└── NCMP-Template-F/          <- female-body clean template
    ├── sav.dat
    ├── metadata.9.json       ("name": "NCMP-Template-F", ...)
    └── screenshot.png
```

The template folder **name is the save's identity** (== the game's
`internalName` on 2.31a). The two names above are hard-wired in
`code/client/App/Saves/SaveManager.h` (`kTemplateMale` / `kTemplateFemale`) and
declared for the menu in `code/assets/redscript/Saves/SaveManager.reds`.

## Template requirements (DESIGN.md rev 2 §D)

- Clean 2.31a **post-prologue sandbox** save (open world reachable, no active
  main-quest lock). `isModded = false`, `saveVersion = 269`, `gameVersion 2310`.
- **Two** templates because the appearance mirror covers hair/face/makeup/
  tattoos/cyberware but **not body/voice** — one male-body + one female-body.
  Everything else syncs at runtime via the ccstate appearance upload.
- Keep the seeds **pristine**. Never edit them in place. New characters are made
  by copying a template to `NCMP-<name>` (done natively by
  `MpSaveManager.CreateSaveFromTemplate`).

## How the runtime uses these (already implemented)

1. `MpSaveManager.EnsureTemplatesInstalled()` copies these seeds from the plugin
   dir (`red4ext/plugins/zzzCyberpunkMP/assets/Saves/`) into the player's save
   directory if absent (idempotent). The menu calls this when it opens.
2. `MpSaveManager.CreateSaveFromTemplate("NCMP-Template-M"|"-F", "<name>")`
   copies a template to `NCMP-<name>` for a new character.
3. The save picker offers NCMP- saves; loading one arms auto-connect via the
   NCMP-save gate (see `World/NetworkAutoConnect.reds`).

## Packaging TODO (P5 release-kit — NOT wired yet)

These seeds are **not** currently built into the artifact. When the templates
exist, wire them into the install/release layout so they ship inside the
plugin at `red4ext/plugins/zzzCyberpunkMP/assets/Saves/` (the path
`SaveManager.cpp` reads via `GCyberpunkMpLocation / "assets/Saves"`). Mirror the
other `code/assets/*/xmake.lua` install rules (a new `TP_SAVES_LOCATION` +
`add_deps`/install into `distrib/launcher/mod/assets/Saves/`), or add them in
the P5 release-assembly step. Until then `EnsureTemplatesInstalled()` no-ops
cleanly (logs a "not produced yet" warning) and the rest of the flow degrades
gracefully.

## Live-validation checklist for the hand-production session

- [ ] Confirm `SHGetKnownFolderPath(FOLDERID_SavedGames)` resolves into the
      wine/Proton prefix (C:/users/<user>/Saved Games/...), not `Z:/`.
- [ ] Confirm the game lists a copied `NCMP-<name>` save under its **folder**
      name (does it read the folder name or `metadata.9.json` `name`? — the
      native does a best-effort rewrite of the metadata `name`; verify it is
      correct / necessary and does not break the save).
- [ ] Confirm a copied template loads cleanly and reaches the open world.
- [ ] Windows friends: document disabling GOG Galaxy cloud saves for CP2077
      (cross-profile clobber + 200 MB quota with template installs).
