module CyberpunkMP.World

import CyberpunkMP.Saves.*

// Auto-connect on world attach when a session has been armed (native pending
// state set by the -online launch arg at boot or by the multiplayer menu at
// runtime). This replaces the retired boot-time `enabled` gate: the mod is now
// always loaded and only connects when a session is explicitly armed.
//
// Requirements folded in from the rejected ConnectionManager draft (see
// ~/CyberpunkMP/PLAN.md):
//   * connected-guard   — never Connect() while already connected
//                         (UIMultiplayerConnectedToServer blackboard bool).
//   * local-player-only — IsControlledByLocalPeer() rejects remote muppets and
//                         any other puppet that is not the local V.
//   * not-pregame       — the BARE MAIN MENU spawns a background/preview
//                         PlayerPuppet that ALSO fires OnGameAttached and passes
//                         both guards above (~389ms after boot). Left ungated it
//                         fired a premature Connect() at the menu, which consumed
//                         the one-shot pending flag and uploaded an empty
//                         appearance (server: "CustomizationState was null" /
//                         "instance=0x0"). inkISystemRequestsHandler.IsPreGame()
//                         is TRUE at the main menu and only becomes FALSE once a
//                         real save has loaded, so it is the discriminator
//                         between the menu-preview puppet and the real post-load
//                         V. Reached via the Codeware-provided
//                         GameInstance.GetSystemRequestsHandler() accessor
//                         (verified on 2.31a via the redscript compile gate).
//   * one-shot per arm  — ClearPendingSession() consumes the pending flag before
//                         connecting, so a re-attach (menu re-entry, save reload)
//                         never reconnects unless the session is re-armed. It
//                         sits INSIDE the !IsPreGame() guard, so a skipped
//                         menu-preview attach never consumes the flag — the
//                         pending session survives until the real post-load
//                         attach, where it is consumed exactly once.
//   * ncmp-save gate    — (P3) never auto-connect onto a single-player save.
//                         The JOIN/HOST menu records the chosen MP save's
//                         internalName via MpSaveManager.SetPendingSave() before
//                         it calls LoadSavedGame(); here we only connect when
//                         MpSaveManager.PendingSaveAllowsConnect() is true — i.e.
//                         the recorded save is an NCMP- save, OR nothing was
//                         recorded (the -online / dev / back-compat arm path,
//                         which stays exactly as P1 validated it). A recorded
//                         non-NCMP save fully disarms without connecting.
//                         NOTE: this trusts the menu-recorded intent; there is
//                         no verified API to read the ACTUALLY-loaded save's name
//                         at attach time, so the -online path is not save-gated
//                         (see the P3 report / DESIGN §D open questions).
//
// Deferred connect: the equipment scriptable data is not queryable yet at
// OnGameAttached — observed live 2026-07-20: capture at immediate connect
// returned 0 items (remote puppets spawned naked) while +10s probes returned
// the full outfit. So the armed connect polls equipment readiness (via
// AppearanceSystem.GetPlayerItems) and only then calls Connect(), which makes
// the one-shot C++ spawn upload carry the real clothing list. A timeout still
// connects after ~15s so a genuinely empty-equipment character can't stall
// joining forever.
public class NcmpDeferredConnect extends DelayCallback {
    public let attemptsLeft: Int32;

    public func Call() -> Void {
        // World left while waiting (back at menu): drop the armed connect.
        let handler: wref<inkISystemRequestsHandler> = GameInstance.GetSystemRequestsHandler();
        if !IsDefined(handler) || handler.IsPreGame() {
            return;
        }
        let system = GameInstance.GetNetworkWorldSystem();
        if !IsDefined(system) {
            return;
        }
        let appearance = system.GetAppearanceSystem();
        let ready = IsDefined(appearance) && appearance.IsEquipmentReady();
        if ready || this.attemptsLeft <= 0 {
            system.Connect();
            return;
        }
        let cb = new NcmpDeferredConnect();
        cb.attemptsLeft = this.attemptsLeft - 1;
        GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(cb, 0.75, false);
    }
}

// Wraps a VANILLA class only: @wrapMethod on the mod's own Ink classes fails with
// UNRESOLVED_REF (see PLAN.md). PlayerPuppet.OnGameAttached fires once the local
// player enters a world, which is exactly the "load save -> auto-connect" seam.
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let result = wrappedMethod();

    if this.IsControlledByLocalPeer() {
        // Skip the main-menu background/preview puppet: only a real loaded save
        // takes the game out of pre-game. Everything below (incl. the one-shot
        // ClearPendingSession) is unreachable at the menu, so the pending flag
        // survives until the real post-load attach.
        let handler: wref<inkISystemRequestsHandler> = GameInstance.GetSystemRequestsHandler();
        if IsDefined(handler) && !handler.IsPreGame() {
            let system = GameInstance.GetNetworkWorldSystem();
            if IsDefined(system) && system.HasPendingSession() {
                let blackboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGame())
                    .Get(GetAllBlackboardDefs().UIGameData);
                let connected: Bool = blackboard.GetBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer);
                if !connected {
                    // P3 NCMP-save gate: only auto-connect onto a multiplayer
                    // (NCMP-) save. See the ncmp-save gate note in the header.
                    if MpSaveManager.PendingSaveAllowsConnect() {
                        system.ClearPendingSession();
                        MpSaveManager.ClearPendingSave();
                        // Connect deferred until equipment reads back (~1-10s)
                        // so the spawn upload includes the outfit — see
                        // NcmpDeferredConnect above.
                        let cb = new NcmpDeferredConnect();
                        cb.attemptsLeft = 20;
                        GameInstance.GetDelaySystem(this.GetGame()).DelayCallback(cb, 0.75, false);
                    } else {
                        // Armed, but the recorded save is not an NCMP- MP save:
                        // fully disarm without connecting. Never auto-connect a
                        // single-player save.
                        system.ClearPendingSession();
                        MpSaveManager.ClearPendingSave();
                    }
                }
            }
        }
    }

    return result;
}
