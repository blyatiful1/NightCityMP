// NightCityMP — top-level MULTIPLAYER main-menu entry (Route 1).
//
// License-separable module (PLAN.local.md FUTURE / nightcitymp-license-exit): this
// file references ONLY vanilla game classes, Codeware.UI widgets, and the P1 network
// natives reached through GameInstance.GetNetworkWorldSystem(). That native accessor
// is the single thin seam to the Tilted-Phoques-derived core, so a future clean-room
// core swap replaces the minimum. No new ink/archive assets are shipped — the overlay
// is built entirely from script.
//
// Mechanism (compile-proven on 2.31a — ~/cp2077-audit/ncmp-design/menu-injection.md):
//   (A) wrap SingleplayerMenuGameController.PopulateMenuItemList -> append a top-level
//       MULTIPLAYER item via the AddMenuItem(String, CName) overload.
//   (B) wrap HandleMenuItemActivate -> intercept our eventName, toggle a self-built
//       Codeware overlay, and consume the activation (return true, never SpawnEvent).
//
// JOIN flow (DESIGN rev 2, P2): parse the ip[:port] field, arm the native pending
// session (SetPendingSession — native-side, survives the save load), then route to the
// vanilla Load Game screen (SpawnEvent 'OnLoadGame'). The P1 world-attach auto-connect
// (World/NetworkAutoConnect.reds) consumes the armed session once a save has loaded.
// HOST is present but disabled until P4 delivers hosting.
module NightCityMP.Menu

import Codeware.UI.*
import CyberpunkMP.World.*

// Default endpoint offered in the JOIN field (matches the client default port 11778).
public func NcmpDefaultAddress() -> String = "127.0.0.1:11778"

// Strong refs keep the script-built controllers alive for the menu screen's lifetime;
// the overlay canvas is retained by the widget tree once reparented (wref is enough).
@addField(SingleplayerMenuGameController) private let m_ncmpOverlay: wref<inkCanvas>;
@addField(SingleplayerMenuGameController) private let m_ncmpInput: ref<TextInput>;
@addField(SingleplayerMenuGameController) private let m_ncmpJoinButton: ref<SimpleButton>;
@addField(SingleplayerMenuGameController) private let m_ncmpHostButton: ref<SimpleButton>;
@addField(SingleplayerMenuGameController) private let m_ncmpBackButton: ref<SimpleButton>;
@addField(SingleplayerMenuGameController) private let m_ncmpBuilt: Bool;

// (A) Append the MULTIPLAYER item after the vanilla items. The outer ShowActionsList()
// runs Refresh() again after PopulateMenuItemList() returns, so the pushed item renders
// (it lands just before the auto-appended "Close game" item).
@wrapMethod(SingleplayerMenuGameController)
private func PopulateMenuItemList() -> Void {
    wrappedMethod();
    this.AddMenuItem("MULTIPLAYER", n"OnNightCityMP");
}

// (B) Intercept our item's activation on the controller (1 hop, no scenario data).
@wrapMethod(SingleplayerMenuGameController)
protected func HandleMenuItemActivate(data: ref<PauseMenuListItemData>) -> Bool {
    if Equals(data.eventName, n"OnNightCityMP") {
        this.ToggleNightCityMPScreen();
        return true;
    }
    return wrappedMethod(data);
}

@addMethod(SingleplayerMenuGameController)
private func ToggleNightCityMPScreen() -> Void {
    if !this.m_ncmpBuilt {
        this.BuildNightCityMPScreen();
    }
    let overlay = this.m_ncmpOverlay;
    if !IsDefined(overlay) {
        return;
    }
    let show = !overlay.IsVisible();
    overlay.SetVisible(show);
    // Keyboard focus for the IP field is click-to-focus (Codeware TextInput handles
    // OnFocusReceived when the field is clicked). A programmatic focus request has no
    // inkWidget API on 2.31a; confirming in-menu keystroke capture is a live-validation
    // item (menu-injection §5/§9).
}

// Build the overlay once, lazily, then toggle visibility on re-entry (no duplicates).
@addMethod(SingleplayerMenuGameController)
private func BuildNightCityMPScreen() -> Void {
    let root = this.GetRootWidget() as inkCompoundWidget;
    if !IsDefined(root) {
        return;
    }

    // Full-screen container.
    let overlay = new inkCanvas();
    overlay.SetName(n"ncmp_overlay");
    overlay.SetAnchor(inkEAnchor.Fill);
    overlay.SetMargin(0.0, 0.0, 0.0, 0.0);
    overlay.Reparent(root);

    // Dimming scrim so the panel reads over the animated menu background.
    let scrim = new inkRectangle();
    scrim.SetName(n"ncmp_scrim");
    scrim.SetAnchor(inkEAnchor.Fill);
    let scrimColor: HDRColor;
    scrimColor.Red = 0.02;
    scrimColor.Green = 0.02;
    scrimColor.Blue = 0.03;
    scrimColor.Alpha = 1.0;
    scrim.SetTintColor(scrimColor);
    scrim.SetOpacity(0.88);
    scrim.Reparent(overlay);

    // Centered column.
    let panel = new inkVerticalPanel();
    panel.SetName(n"ncmp_panel");
    panel.SetAnchor(inkEAnchor.Centered);
    panel.SetAnchorPoint(0.5, 0.5);
    panel.SetHAlign(inkEHorizontalAlign.Center);
    panel.SetVAlign(inkEVerticalAlign.Center);
    panel.Reparent(overlay);

    let accent: HDRColor;
    accent.Red = 0.98;
    accent.Green = 0.86;
    accent.Blue = 0.20;
    accent.Alpha = 1.0;

    let title = new inkText();
    title.SetName(n"ncmp_title");
    title.SetText("MULTIPLAYER");
    title.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    title.SetFontSize(60);
    title.SetTintColor(accent);
    title.SetHAlign(inkEHorizontalAlign.Center);
    title.SetMargin(0.0, 0.0, 0.0, 8.0);
    title.Reparent(panel);

    let subtitle = new inkText();
    subtitle.SetName(n"ncmp_subtitle");
    subtitle.SetText("Enter a host's address, then load a save to join their session.");
    subtitle.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    subtitle.SetFontSize(30);
    subtitle.SetHAlign(inkEHorizontalAlign.Center);
    subtitle.SetMargin(0.0, 0.0, 0.0, 28.0);
    subtitle.Reparent(panel);

    let label = new inkText();
    label.SetName(n"ncmp_label");
    label.SetText("SERVER ADDRESS (IP:PORT)");
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    label.SetFontSize(28);
    label.SetHAlign(inkEHorizontalAlign.Center);
    label.SetMargin(0.0, 0.0, 0.0, 6.0);
    label.Reparent(panel);

    // JOIN-by-IP field (Codeware TextInput; no ink asset). Pre-filled with the default.
    let input = TextInput.Create();
    input.SetName(n"ncmp_ip");
    input.SetDefaultText(NcmpDefaultAddress());
    input.SetText(NcmpDefaultAddress());
    input.SetMaxLength(64);
    input.Reparent(panel);
    let inputRoot = input.GetRootWidget();
    inputRoot.SetHAlign(inkEHorizontalAlign.Center);
    inputRoot.SetMargin(0.0, 0.0, 0.0, 24.0);
    this.m_ncmpInput = input;

    let join = SimpleButton.Create();
    join.SetName(n"ncmp_join");
    join.SetText("JOIN SESSION");
    join.Reparent(panel);
    let joinRoot = join.GetRootWidget();
    joinRoot.SetHAlign(inkEHorizontalAlign.Center);
    joinRoot.SetMargin(0.0, 0.0, 0.0, 12.0);
    join.RegisterToCallback(n"OnBtnClick", this, n"OnNcmpJoin");
    this.m_ncmpJoinButton = join;

    // HOST is disabled until P4 — present, greyed, and inert (no dead-end click).
    let host = SimpleButton.Create();
    host.SetName(n"ncmp_host");
    host.SetText("HOST SESSION");
    host.Reparent(panel);
    host.SetDisabled(true);
    let hostRoot = host.GetRootWidget();
    hostRoot.SetHAlign(inkEHorizontalAlign.Center);
    hostRoot.SetMargin(0.0, 0.0, 0.0, 6.0);
    this.m_ncmpHostButton = host;

    let hostNote = new inkText();
    hostNote.SetName(n"ncmp_host_note");
    hostNote.SetText("Hosting arrives in a future update.");
    hostNote.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    hostNote.SetFontSize(24);
    hostNote.SetOpacity(0.6);
    hostNote.SetHAlign(inkEHorizontalAlign.Center);
    hostNote.SetMargin(0.0, 0.0, 0.0, 28.0);
    hostNote.Reparent(panel);

    let back = SimpleButton.Create();
    back.SetName(n"ncmp_back");
    back.SetText("BACK");
    back.Reparent(panel);
    let backRoot = back.GetRootWidget();
    backRoot.SetHAlign(inkEHorizontalAlign.Center);
    back.RegisterToCallback(n"OnBtnClick", this, n"OnNcmpBack");
    this.m_ncmpBackButton = back;

    overlay.SetVisible(false);
    this.m_ncmpOverlay = overlay;
    this.m_ncmpBuilt = true;
}

// JOIN: arm the pending session with the typed endpoint, then route to save loading.
@addMethod(SingleplayerMenuGameController)
protected cb func OnNcmpJoin(e: ref<inkPointerEvent>) -> Bool {
    let addr = this.m_ncmpInput.GetText();
    if StrLen(addr) == 0 {
        addr = NcmpDefaultAddress();
    }

    let ip = addr;
    let port: Uint32 = 11778u;
    let parts = StrSplit(addr, ":");
    if ArraySize(parts) >= 1 && StrLen(parts[0]) > 0 {
        ip = parts[0];
    }
    if ArraySize(parts) >= 2 {
        let parsed = StringToInt(parts[1], 11778);
        if parsed > 0 && parsed <= 65535 {
            port = Cast<Uint32>(parsed);
        }
    }

    let system = GameInstance.GetNetworkWorldSystem();
    if IsDefined(system) {
        // Native-side pending state survives the save load; World/NetworkAutoConnect.reds
        // consumes it exactly once, on the real post-load world attach.
        system.SetPendingSession(ip, port);
    }

    // Hide before switching scenarios so a cancelled Load Game returns to a clean menu.
    if IsDefined(this.m_ncmpOverlay) {
        this.m_ncmpOverlay.SetVisible(false);
    }

    // Route to the vanilla Load Game screen — the exact path the "Load Game" item takes.
    if IsDefined(this.m_menuEventDispatcher) {
        this.m_menuEventDispatcher.SpawnEvent(n"OnLoadGame");
    }
    return true;
}

@addMethod(SingleplayerMenuGameController)
protected cb func OnNcmpBack(e: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.m_ncmpOverlay) {
        this.m_ncmpOverlay.SetVisible(false);
    }
    return true;
}
