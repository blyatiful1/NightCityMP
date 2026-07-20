#include "SaveManager.h"

#include <ShlObj.h>

#include <cctype>
#include <fstream>
#include <mutex>
#include <string>
#include <string_view>
#include <system_error>

// Plugin install directory (red4ext/plugins/zzzCyberpunkMP/...), owned by
// Main.cpp. RpcCsharp.cpp externs it the same way. Used only to locate the
// pristine template seeds under <plugin>/assets/Saves/.
extern std::filesystem::path GCyberpunkMpLocation;

namespace fs = std::filesystem;

namespace
{
// FOLDERID_SavedGames = {4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}. Defined locally
// so this TU does not depend on the KNOWNFOLDERID GUID symbols in uuid.lib
// (which the client target does not link) — a plain SHGetKnownFolderPath call.
const KNOWNFOLDERID kSavedGamesFolderId = {
    0x4C5C32FF, 0xBB9D, 0x43B0, {0xB5, 0xB4, 0x2D, 0x72, 0xE5, 0x4E, 0xAA, 0xA4}};

// The CDPR save-dir suffix under FOLDERID_SavedGames — same on Steam + GOG on
// real Windows (DESIGN.md §D); under Proton it maps into the wine prefix.
constexpr const wchar_t* kSaveSubdir = L"CD Projekt Red\\Cyberpunk 2077";

// Relative location of the pristine template seeds inside the plugin dir. The
// seeds themselves are hand-produced later (see code/assets/Saves/README.md);
// this module only installs/copies whatever is present.
constexpr const char* kSeedSubdir = "assets/Saves";

// The "pending MP save" gate. Native-side (process-global) so it survives the
// save/world load between the menu recording it and the world-attach hook
// consuming it. Empty string == nothing recorded (the -online/dev arm path).
std::mutex g_pendingMutex;
std::string g_pendingSaveName;

std::string ToUtf8(const std::wstring& aWide)
{
    if (aWide.empty())
        return {};
    const int size = ::WideCharToMultiByte(CP_UTF8, 0, aWide.data(), static_cast<int>(aWide.size()),
                                           nullptr, 0, nullptr, nullptr);
    if (size <= 0)
        return {};
    std::string out(static_cast<size_t>(size), '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, aWide.data(), static_cast<int>(aWide.size()), out.data(), size,
                          nullptr, nullptr);
    return out;
}

bool HasMpPrefix(std::string_view aName)
{
    const std::string_view prefix{MpSaveManager::kPrefix};
    return aName.size() >= prefix.size() && aName.substr(0, prefix.size()) == prefix;
}

fs::path SavesDir()
{
    PWSTR raw = nullptr;
    if (FAILED(::SHGetKnownFolderPath(kSavedGamesFolderId, 0, nullptr, &raw)) || raw == nullptr)
    {
        if (raw)
            ::CoTaskMemFree(raw);
        spdlog::error("[NCMP saves] SHGetKnownFolderPath(FOLDERID_SavedGames) failed");
        return {};
    }
    fs::path base = raw;
    ::CoTaskMemFree(raw);
    return base / kSaveSubdir;
}

// Best-effort read of a save's metadata.9.json. Never throws; leaves outputs
// untouched on any failure. Schema (verified from a real 2.31a save):
//   { "Data": { "metadata": { "name": "...", "timestampString": "...", ... } } }
void ReadMetadata(const fs::path& aSaveDir, std::string& aOutName, std::string& aOutTimestamp)
{
    try
    {
        std::ifstream file(aSaveDir / "metadata.9.json");
        if (!file)
            return;
        nlohmann::json json;
        file >> json;
        if (json.contains("Data") && json["Data"].contains("metadata"))
        {
            const auto& meta = json["Data"]["metadata"];
            aOutName = meta.value("name", std::string{});
            aOutTimestamp = meta.value("timestampString", std::string{});
        }
    }
    catch (...)
    {
        // Malformed / partial metadata is non-fatal: the folder name is the
        // authoritative identity; metadata only enriches the display label.
    }
}

bool LooksLikeSave(const fs::path& aDir)
{
    std::error_code ec;
    return fs::exists(aDir / "sav.dat", ec) || fs::exists(aDir / "metadata.9.json", ec);
}

std::string SanitizeCharacterName(std::string_view aIn)
{
    // Drop an existing NCMP- prefix (re-added below) and keep only filesystem-
    // safe characters so a caller can never escape the save dir.
    if (HasMpPrefix(aIn))
        aIn.remove_prefix(std::string_view{MpSaveManager::kPrefix}.size());

    std::string out;
    for (const char ch : aIn)
    {
        const unsigned char uc = static_cast<unsigned char>(ch);
        if (std::isalnum(uc) || ch == '-' || ch == '_' || ch == ' ')
            out += ch;
    }
    // Trim surrounding spaces.
    const auto first = out.find_first_not_of(' ');
    const auto last = out.find_last_not_of(' ');
    if (first == std::string::npos)
        return {};
    return out.substr(first, last - first + 1);
}

Red::DynArray<Red::Handle<NcmpSaveInfo>> ListSavesImpl(bool aMpOnly)
{
    Red::DynArray<Red::Handle<NcmpSaveInfo>> result;

    const fs::path dir = SavesDir();
    std::error_code ec;
    if (dir.empty() || !fs::exists(dir, ec))
        return result;

    for (const auto& entry : fs::directory_iterator(dir, ec))
    {
        if (ec)
            break;
        if (!entry.is_directory(ec))
            continue;
        if (!LooksLikeSave(entry.path()))
            continue;

        const std::string name = ToUtf8(entry.path().filename().wstring());
        const bool isMp = HasMpPrefix(name);
        if (aMpOnly && !isMp)
            continue;

        std::string metaName;
        std::string timestamp;
        ReadMetadata(entry.path(), metaName, timestamp);

        std::string display = name;
        if (!timestamp.empty())
            display += " - " + timestamp;

        auto info = RED4ext::MakeHandle<NcmpSaveInfo>();
        info->internalName = name.c_str();
        info->displayName = display.c_str();
        info->isMpSave = isMp;
        result.PushBack(info);
    }

    return result;
}

// Copy one pristine seed folder into the save dir if it is not already there.
// Returns true when the template exists in the save dir after the call.
bool InstallSeedIfAbsent(const fs::path& aSeedRoot, const fs::path& aSavesDir, const char* aName)
{
    std::error_code ec;
    const fs::path dst = aSavesDir / aName;
    if (fs::exists(dst, ec))
        return true;

    const fs::path src = aSeedRoot / aName;
    if (!fs::exists(src, ec))
    {
        // Expected until the template saves are hand-produced (P3 follow-up).
        spdlog::warn("[NCMP saves] template seed '{}' not present at {} (not produced yet)", aName,
                     ToUtf8(src.wstring()));
        return false;
    }

    fs::create_directories(aSavesDir, ec);
    fs::copy(src, dst, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
    if (ec)
    {
        spdlog::error("[NCMP saves] failed to install template '{}': {}", aName, ec.message());
        return false;
    }
    spdlog::info("[NCMP saves] installed template '{}'", aName);
    return true;
}

// Best-effort: rewrite the copied save's metadata.9.json "name" field to match
// its new folder. The folder name is the authoritative identity for loading,
// but the metadata "name" should agree. Guarded — on ANY failure the verbatim
// copy is left intact (which already loads). NEEDS live validation during the
// hand-production session (does the game key off folder vs metadata name?).
void TryRewriteMetadataName(const fs::path& aSaveDir, const std::string& aNewName)
{
    try
    {
        const fs::path metaPath = aSaveDir / "metadata.9.json";
        std::ifstream in(metaPath);
        if (!in)
            return;
        nlohmann::json json;
        in >> json;
        in.close();

        if (!(json.contains("Data") && json["Data"].contains("metadata")))
            return;
        json["Data"]["metadata"]["name"] = aNewName;

        std::ofstream out(metaPath, std::ios::trunc);
        if (!out)
            return;
        out << json.dump();
    }
    catch (...)
    {
        // Leave the verbatim copy in place.
    }
}
} // namespace

bool MpSaveManager::IsMpSaveName(const Red::CString& aName)
{
    return HasMpPrefix(std::string_view{aName.c_str()});
}

Red::CString MpSaveManager::GetSavesPath()
{
    return Red::CString{ToUtf8(SavesDir().wstring()).c_str()};
}

Red::DynArray<Red::Handle<NcmpSaveInfo>> MpSaveManager::ListSaves()
{
    return ListSavesImpl(false);
}

Red::DynArray<Red::Handle<NcmpSaveInfo>> MpSaveManager::ListMpSaves()
{
    return ListSavesImpl(true);
}

bool MpSaveManager::EnsureTemplatesInstalled()
{
    const fs::path saves = SavesDir();
    if (saves.empty())
        return false;

    const fs::path seedRoot = GCyberpunkMpLocation / kSeedSubdir;
    const bool male = InstallSeedIfAbsent(seedRoot, saves, kTemplateMale);
    const bool female = InstallSeedIfAbsent(seedRoot, saves, kTemplateFemale);
    return male && female;
}

bool MpSaveManager::CreateSaveFromTemplate(const Red::CString& aTemplateName, const Red::CString& aNewName)
{
    const std::string templateName = aTemplateName.c_str();
    if (templateName != kTemplateMale && templateName != kTemplateFemale)
    {
        spdlog::error("[NCMP saves] CreateSaveFromTemplate: unknown template '{}'", templateName);
        return false;
    }

    const std::string sanitized = SanitizeCharacterName(aNewName.c_str());
    if (sanitized.empty())
    {
        spdlog::error("[NCMP saves] CreateSaveFromTemplate: empty/invalid character name");
        return false;
    }
    const std::string finalName = std::string{kPrefix} + sanitized;

    const fs::path saves = SavesDir();
    if (saves.empty())
        return false;

    std::error_code ec;
    const fs::path src = saves / templateName;
    if (!fs::exists(src, ec))
    {
        // Template not installed yet — try once, then give up cleanly.
        if (!EnsureTemplatesInstalled() || !fs::exists(src, ec))
        {
            spdlog::error("[NCMP saves] CreateSaveFromTemplate: template '{}' not installed", templateName);
            return false;
        }
    }

    const fs::path dst = saves / finalName;
    if (fs::exists(dst, ec))
    {
        spdlog::error("[NCMP saves] CreateSaveFromTemplate: '{}' already exists", finalName);
        return false;
    }

    fs::copy(src, dst, fs::copy_options::recursive, ec);
    if (ec)
    {
        spdlog::error("[NCMP saves] CreateSaveFromTemplate: copy failed: {}", ec.message());
        return false;
    }

    TryRewriteMetadataName(dst, finalName);
    spdlog::info("[NCMP saves] created MP character '{}' from '{}'", finalName, templateName);
    return true;
}

void MpSaveManager::SetPendingSave(const Red::CString& aInternalName)
{
    std::scoped_lock lock(g_pendingMutex);
    g_pendingSaveName = aInternalName.c_str();
}

void MpSaveManager::ClearPendingSave()
{
    std::scoped_lock lock(g_pendingMutex);
    g_pendingSaveName.clear();
}

bool MpSaveManager::PendingSaveAllowsConnect()
{
    std::scoped_lock lock(g_pendingMutex);
    if (g_pendingSaveName.empty())
        return true; // -online / dev / back-compat arm: nothing recorded, preserve P1.
    return HasMpPrefix(g_pendingSaveName);
}
