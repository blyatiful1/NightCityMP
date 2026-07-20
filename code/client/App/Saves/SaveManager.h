#pragma once

// ===========================================================================
// NightCityMP — MP-dedicated save system (P3)
// ---------------------------------------------------------------------------
// NEW, self-contained module. Per the project's license-separability doctrine
// (PLAN.local.md FUTURE section) this subsystem deliberately keeps a THIN
// interface to the Tilted-Phoques-derived core: it does not include, subclass,
// or edit any TP client system. It only touches:
//   * the RED4ext RTTI machinery (RedLib, MIT) to expose statics to redscript,
//   * the process-global GCyberpunkMpLocation (an extern owned by Main.cpp),
// so a future core swap replaces the minimum.
//
// Responsibilities (DESIGN.md rev 2 §D "MP saves"):
//   * Resolve the Cyberpunk 2077 save directory (SHGetKnownFolderPath /
//     FOLDERID_SavedGames + "CD Projekt Red/Cyberpunk 2077").
//   * Enumerate saves with metadata read from each save's metadata.9.json.
//   * Detect MP saves by the "NCMP-" internalName/folder prefix.
//   * Install the pristine template seeds (NCMP-Template-M / NCMP-Template-F)
//     into the save dir, idempotently, and create new NCMP-<name> characters
//     by copying a template folder (redscript cannot copy folders).
//   * Hold the "pending MP save" gate consulted by the world-attach
//     auto-connect hook so a single-player save never auto-connects.
//
// Everything here is exposed to redscript as STATIC native functions on
// `CyberpunkMP.Saves.MpSaveManager` (mirrors Codeware's `abstract native class`
// static-namespace pattern), so it is callable at the MAIN MENU (pre-game),
// independent of any game world / game-system container — which is exactly
// where the save picker runs.
// ===========================================================================

#include "Red/TypeInfo/Macros/Definition.hpp"

// Data holder returned to redscript as `ref<NcmpSaveInfo>`. Mirrors the proven
// ChatSystem pattern: derive from IScriptable, no explicit RTTI_PARENT (RedLib
// defaults the parent to IScriptable), RTTI_ALIAS names the redscript FQN.
struct NcmpSaveInfo : RED4ext::IScriptable
{
    RTTI_IMPL_TYPEINFO(NcmpSaveInfo);
    RTTI_IMPL_ALLOCATOR();

    // Save folder name == the game's internalName (verified 2.31a; the folder
    // name and metadata.9.json "name" field agree). This is the stable identity
    // used to resolve a fresh saveIndex via redscript's RequestSavesForLoad().
    Red::CString internalName;
    // Human-facing label (internalName + " — " + metadata timestamp when it
    // could be read). Never load-bearing; purely for the picker UI.
    Red::CString displayName;
    // True iff internalName starts with the "NCMP-" MP-save prefix.
    bool isMpSave{false};
};

RTTI_DEFINE_CLASS(NcmpSaveInfo, {
    RTTI_ALIAS("CyberpunkMP.Saves.NcmpSaveInfo");
    RTTI_PROPERTY(internalName);
    RTTI_PROPERTY(displayName);
    RTTI_PROPERTY(isMpSave);
});

// Static-only native namespace exposed to redscript. All methods are free
// functions (no IScriptable context param) so RedLib registers them as
// `static native func` (CClassStaticFunction) — see Red/TypeInfo/Definition.hpp
// AddFunction: a free-function pointer has context_type = void -> static.
struct MpSaveManager : RED4ext::IScriptable
{
    RTTI_IMPL_TYPEINFO(MpSaveManager);
    RTTI_IMPL_ALLOCATOR();

    // The MP-save namespace prefix. Single source of truth.
    static constexpr const char* kPrefix = "NCMP-";
    // The two template character seeds shipped in the release (hand-produced
    // later — see code/assets/Saves/README.md). Registered here as the known
    // template set the menu offers and EnsureTemplatesInstalled() installs.
    static constexpr const char* kTemplateMale = "NCMP-Template-M";
    static constexpr const char* kTemplateFemale = "NCMP-Template-F";

    // "NCMP-" prefix check. Trivial but centralised so the prefix lives in one
    // place. The menu applies this to SaveMetadataInfo.internalName to filter.
    static bool IsMpSaveName(const Red::CString& aName);

    // Absolute path to the Cyberpunk 2077 save directory, or "" if it could not
    // be resolved. (Under Proton/wine, FOLDERID_SavedGames maps into the prefix
    // — needs one live confirmation, see report.)
    static Red::CString GetSavesPath();

    // All saves on disk, newest-first is NOT guaranteed (directory order).
    static Red::DynArray<Red::Handle<NcmpSaveInfo>> ListSaves();
    // Convenience: only saves whose internalName starts with "NCMP-".
    static Red::DynArray<Red::Handle<NcmpSaveInfo>> ListMpSaves();

    // Copy the pristine template seeds from the plugin dir into the save dir if
    // they are not already present. Idempotent; safe to call every time the MP
    // menu opens. Returns true if, after the call, both templates exist on disk
    // (i.e. the picker can offer them). No-ops cleanly (returns false) when the
    // seeds have not been hand-produced yet.
    static bool EnsureTemplatesInstalled();

    // Create a new MP character NCMP-<aNewName> by copying an existing template
    // folder. aTemplateName must be one of the kTemplate* names. Returns true on
    // success. The destination is always namespaced with "NCMP-".
    static bool CreateSaveFromTemplate(const Red::CString& aTemplateName, const Red::CString& aNewName);

    // --- Auto-connect NCMP gate (native-side; survives the save/world load) ---
    // The menu records the chosen MP save's internalName here BEFORE it calls
    // LoadSavedGame(). The world-attach auto-connect hook then consults
    // PendingSaveAllowsConnect() so it never connects onto a single-player save.
    static void SetPendingSave(const Red::CString& aInternalName);
    static void ClearPendingSave();
    // true when it is safe to auto-connect for the current pending session:
    //   * a recorded save that IS an NCMP- MP save            -> true
    //   * NO recorded save (the -online / dev / back-compat    -> true
    //     arm path records nothing; preserve P1's behaviour)
    //   * a recorded save that is NOT an NCMP- save            -> false
    static bool PendingSaveAllowsConnect();
};

RTTI_DEFINE_CLASS(MpSaveManager, {
    RTTI_ALIAS("CyberpunkMP.Saves.MpSaveManager");
    RTTI_ABSTRACT();
    RTTI_METHOD(IsMpSaveName);
    RTTI_METHOD(GetSavesPath);
    RTTI_METHOD(ListSaves);
    RTTI_METHOD(ListMpSaves);
    RTTI_METHOD(EnsureTemplatesInstalled);
    RTTI_METHOD(CreateSaveFromTemplate);
    RTTI_METHOD(SetPendingSave);
    RTTI_METHOD(ClearPendingSave);
    RTTI_METHOD(PendingSaveAllowsConnect);
});
