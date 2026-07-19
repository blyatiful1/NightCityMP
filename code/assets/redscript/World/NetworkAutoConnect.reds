module CyberpunkMP.World

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
//   * one-shot per arm  — ClearPendingSession() consumes the pending flag before
//                         connecting, so a re-attach (menu re-entry, save reload)
//                         never reconnects unless the session is re-armed.
//
// Wraps a VANILLA class only: @wrapMethod on the mod's own Ink classes fails with
// UNRESOLVED_REF (see PLAN.md). PlayerPuppet.OnGameAttached fires once the local
// player enters a world, which is exactly the "load save -> auto-connect" seam.
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let result = wrappedMethod();

    if this.IsControlledByLocalPeer() {
        let system = GameInstance.GetNetworkWorldSystem();
        if IsDefined(system) && system.HasPendingSession() {
            let blackboard: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGame())
                .Get(GetAllBlackboardDefs().UIGameData);
            let connected: Bool = blackboard.GetBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer);
            if !connected {
                system.ClearPendingSession();
                system.Connect();
            }
        }
    }

    return result;
}
