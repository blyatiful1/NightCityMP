# Installing NightCityMP

Hey — thanks for trying this out! Here's everything you need, in plain steps.

## 1. What you need

- **Cyberpunk 2077**, patch **2.31a**, from GOG or Steam.
- A reasonably clean install (no other big mods conflicting with it). A vanilla or lightly-modded game works best.

## 2. Install

1. **Close the game completely** if it's running.
2. Extract `NightCityMP-<version>-player.zip` **directly into your game folder** — that's the folder that contains `bin/`, `archive/` and `r6/` inside it.
3. When your unzip tool asks about overwriting files, say **yes to all / overwrite everything**.

That's it — nothing else to install, nothing to run separately.

## 3. Update to a new version

Same as installing, every time:

1. **Close the game completely.**
2. Extract the new zip over the game folder, overwriting everything.

> Always fully close the game before updating. Extracting while the game is running can leave you with a broken mix of old and new files.

**If you ever see a red error/compilation popup when the game starts up:**

1. Close the game.
2. Delete the entire folder `red4ext/plugins/zzzCyberpunkMP` inside your game folder.
3. Re-extract the zip over the game folder again.

This clears out leftover files from an older version that the new one doesn't expect.

## 4. Join a game

1. Launch the game and go to the main menu.
2. Select **MULTIPLAYER**.
3. Enter the address your host gives you, then select **JOIN**.
   - If you're both on Tailscale, use the `100.x` address the host gives you.
4. The first time you connect, it takes a few extra seconds while your character's equipment registers — that's normal, just wait for it.

## 5. About that "NCMP-Template-F" save

You'll see a save called **NCMP-Template-F** in your Load Game list. That's just the shared starter save the multiplayer world is built on — it's not meant for you personally.

For now, **load your own save** and play as your own character, then connect through MULTIPLAYER as usual.

## 6. Troubleshooting

- **Everyone looks naked / other players have no clothes or gear:** you're most likely on an older version. Do the **Update** steps above (game fully closed) and try again.
- **Can't connect:** double-check you typed the address exactly as the host gave it, and confirm with them that their server is actually running.

Still stuck? Ask whoever gave you the zip — they'll know what version and setup you're both on.
