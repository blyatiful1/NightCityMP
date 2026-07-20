module CyberpunkMP.Saves

// P3 — MP-dedicated save system. Redscript declarations for the native module
// at code/client/App/Saves/SaveManager.* (DESIGN.md rev 2 §D "MP saves").
//
// NEW, self-contained module kept separable from the Tilted-Phoques-derived
// core (PLAN.local.md FUTURE / license-exit doctrine).
//
// MpSaveManager is a static-only native namespace (mirrors Codeware's
// `abstract native class` pattern) so every function is callable at the MAIN
// MENU (pre-game) — it does not depend on a game world or game-system
// container, which is exactly where the save picker runs.

// One enumerated save. `internalName` is the save-folder name (== the game's
// internalName on 2.31a); resolve a fresh saveIndex for LoadSavedGame() by
// matching this against SaveMetadataInfo.internalName from RequestSavesForLoad()
// (saveIndex is not stable). `displayName` is a UI-only label. `isMpSave` is the
// "NCMP-" prefix test result.
public native class NcmpSaveInfo extends IScriptable {
    public native let internalName: String;
    public native let displayName: String;
    public native let isMpSave: Bool;
}

public abstract native class MpSaveManager {
    // "NCMP-" prefix test. Apply to SaveMetadataInfo.internalName to filter the
    // vanilla Load Game list down to MP saves, or to any save name.
    public static native func IsMpSaveName(name: String) -> Bool;

    // Absolute path to the Cyberpunk 2077 save directory ("" if unresolved).
    public static native func GetSavesPath() -> String;

    // Native save enumeration with metadata (folder name + metadata.9.json).
    // Provided for a custom NCMP-only picker; the vanilla Load Game screen
    // filtered by IsMpSaveName() is the fallback path (DESIGN §D).
    public static native func ListSaves() -> array<ref<NcmpSaveInfo>>;
    public static native func ListMpSaves() -> array<ref<NcmpSaveInfo>>;

    // Install the pristine NCMP-Template-M/-F seeds into the save dir if absent
    // (idempotent; call when the MP menu opens). Returns true when both
    // templates exist on disk afterwards. Returns false until the template
    // saves are hand-produced (P3 follow-up — see code/assets/Saves/README.md).
    public static native func EnsureTemplatesInstalled() -> Bool;

    // Create a new MP character NCMP-<newName> by copying a template folder
    // (redscript cannot copy folders). templateName must be "NCMP-Template-M"
    // or "NCMP-Template-F". Returns true on success.
    public static native func CreateSaveFromTemplate(templateName: String, newName: String) -> Bool;

    // --- Auto-connect NCMP gate (native-side; survives the save/world load) ---
    // The JOIN/HOST menu flow records the chosen MP save's internalName here
    // BEFORE it calls LoadSavedGame(); World/NetworkAutoConnect.reds then
    // consults PendingSaveAllowsConnect() so a single-player save is never
    // auto-connected. See DESIGN §D / P3 phasing.
    public static native func SetPendingSave(internalName: String) -> Void;
    public static native func ClearPendingSave() -> Void;
    public static native func PendingSaveAllowsConnect() -> Bool;
}
