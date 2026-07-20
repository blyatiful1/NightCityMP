// NightCityMP — pause-menu "Leave Session" (Minecraft-style clean disconnect).
//
// License-separable module (see MainMenu.reds header). With the legacy F7
// connect/disconnect hotkey retired, this is the ONLY in-session disconnect path, so it
// is shown only while a session is live (DESIGN rev 2 A.9). Interface to the
// Tilted-Phoques-derived core is the single GameInstance.GetNetworkWorldSystem() seam.
//
// PauseMenuGameController overrides OnMenuItemActivated directly (it does NOT route
// through the base HandleMenuItemActivate), so the activation seam here is
// OnMenuItemActivated — unlike the main menu, which uses HandleMenuItemActivate.
module NightCityMP.Menu

import CyberpunkMP.World.*

@addMethod(PauseMenuGameController)
private func IsNcmpConnected() -> Bool {
    let bb = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UIGameData);
    if !IsDefined(bb) {
        return false;
    }
    return bb.GetBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer);
}

// Append "LEAVE SESSION" after the vanilla items, only while connected. The base
// ShowActionsList() runs Refresh() again after PopulateMenuItemList() returns, so the
// appended item renders (just before the auto-appended "Close game" item).
@wrapMethod(PauseMenuGameController)
private func PopulateMenuItemList() -> Void {
    wrappedMethod();
    if this.IsNcmpConnected() {
        this.AddMenuItem("LEAVE SESSION", n"OnNightCityMPLeave");
    }
}

// Intercept our item, disconnect + clear the pending session, then close the pause menu.
@wrapMethod(PauseMenuGameController)
protected cb func OnMenuItemActivated(index: Int32, target: ref<ListItemController>) -> Bool {
    let data = target.GetData() as PauseMenuListItemData;
    if IsDefined(data) && Equals(data.eventName, n"OnNightCityMPLeave") {
        let system = GameInstance.GetNetworkWorldSystem();
        if IsDefined(system) {
            // Clear first so an in-flight arm can't re-trigger auto-connect after we drop.
            system.ClearPendingSession();
            system.Disconnect();
        }
        // Close the pause menu (the same event the "Resume" item dispatches).
        if IsDefined(this.m_menuEventDispatcher) {
            this.m_menuEventDispatcher.SpawnEvent(n"OnClosePauseMenu");
        }
        return true;
    }
    return wrappedMethod(index, target);
}
