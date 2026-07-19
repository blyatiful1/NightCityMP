module CyberpunkMP.Ink

// import Codeware.UI.*
import CyberpunkMP.*
import CyberpunkMP.World.*

public class ChatController extends inkHUDGameController {
    private let m_messagesRef: inkWidgetRef;
    private let m_inputRef: inkTextInputRef;
    private let m_scrollRef: inkScrollAreaRef;

    private let m_uiSystem: wref<UISystem>;
    private let m_player: wref<PlayerPuppet>;
    private let m_repeatingScrollActionEnabled: Bool = false;
    private let m_messageController: ref<ListController>;
    private let m_chatInputOpen: Bool;
    private let m_input: wref<inkTextInput>;
    private let m_lastMessageData: ref<ChatMessageData>;
    private let m_connected: Bool;
    private let m_connectedBBId: ref<CallbackHandle>;
    private let m_hideGeneration: Int32;
    private let m_fadeProxy: ref<inkAnimProxy>;

    protected cb func OnInitialize() -> Bool {
        FTLog(s"[ChatController] OnInitialize");
        this.m_player = this.GetPlayerControlledObject() as PlayerPuppet;
        if !IsDefined(this.m_player) {
            FTLog(s"[ChatController] NO PLAYER");
        }
        this.m_uiSystem = GameInstance.GetUISystem(this.m_player.GetGame());
        this.m_messageController = inkWidgetRef.GetController(this.m_messagesRef) as ListController;
        this.m_input = inkWidgetRef.Get(this.m_inputRef) as inkTextInput;
        this.m_player.RegisterInputListener(this, n"UIEnterChatMessage");

        this.UpdateInputHints();

        // The chat panel is part of the always-loaded HUD layer: keep it hidden
        // until we are actually connected, and let it fade out when idle.
        let blackboard = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UIGameData);
        this.m_connected = blackboard.GetBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer);
        this.m_connectedBBId = blackboard.RegisterListenerBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer, this, n"OnConnectionStateChanged");
        this.GetRootWidget().SetVisible(this.m_connected);
    }

    protected cb func OnUninitialize() -> Bool {
        FTLog(s"[ChatController] OnUninitialize");
        this.m_player.UnregisterInputListener(this, n"UIEnterChatMessage");
        let blackboard = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UIGameData);
        blackboard.UnregisterListenerBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer, this.m_connectedBBId);
    }

    protected cb func OnConnectionStateChanged(value: Bool) -> Bool {
        this.m_connected = value;
        this.GetRootWidget().SetVisible(value);
        if value {
            this.WakeChat();
        } else {
            if this.m_chatInputOpen {
                this.ShowChatInput(false);
            }
        }
        this.UpdateInputHints();
    }

    // Show the chat panel at full opacity and schedule it to fade once idle.
    private func WakeChat() -> Void {
        this.m_hideGeneration += 1;
        if IsDefined(this.m_fadeProxy) && this.m_fadeProxy.IsPlaying() {
            this.m_fadeProxy.Stop();
        }
        this.GetRootWidget().SetOpacity(1.0);
        let cb = new ChatFadeCallback();
        cb.m_controller = this;
        cb.m_generation = this.m_hideGeneration;
        GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(cb, 10.0, false);
    }

    public func OnFadeTimeout(generation: Int32) -> Void {
        // A newer wake (message/typing) supersedes this fade.
        if generation != this.m_hideGeneration || this.m_chatInputOpen || !this.m_connected {
            return;
        }
        let anim = new inkAnimDef();
        let interp = new inkAnimTransparency();
        interp.SetStartTransparency(1.0);
        interp.SetEndTransparency(0.0);
        interp.SetDuration(0.8);
        interp.SetType(inkanimInterpolationType.Linear);
        anim.AddInterpolator(interp);
        this.m_fadeProxy = this.GetRootWidget().PlayAnimation(anim);
    }

    private func UpdateInputHints() -> Void {
        let evt = new UpdateInputHintMultipleEvent();
        evt.targetHintContainer = n"GameplayInputHelper";
        evt.AddInputHint(CreateInputHint(n"Chat", n"UIEnterChatMessage", false), this.m_connected && !this.m_chatInputOpen);
        evt.AddInputHint(CreateInputHint(n"Cancel", n"back", false), this.m_chatInputOpen);
        evt.AddInputHint(CreateInputHint(n"Send", n"EnterChat", false), this.m_chatInputOpen);
        evt.AddInputHint(CreateInputHint(n"Scroll up", n"navigate_up", false), this.m_chatInputOpen);
        evt.AddInputHint(CreateInputHint(n"Scroll down", n"navigate_down", false), this.m_chatInputOpen);
        evt.AddInputHint(CreateInputHint(n"Top of chat", n"ChatTop", false), this.m_chatInputOpen);
        evt.AddInputHint(CreateInputHint(n"End of chat", n"ChatBottom", false), this.m_chatInputOpen);
        this.m_uiSystem.QueueEvent(evt);
    }

    protected cb func OnChatMessageUIEvent(evt: ref<ChatMessageUIEvent>) -> Bool {
        FTLog(s"[ChatController] OnChatMessageUIEvent");
        let messageData = new ChatMessageData();
        messageData.m_author = evt.author;
        messageData.m_message = evt.message;
        messageData.m_isSelf = Equals(StringToName(evt.author), StringToName(GameInstance.GetNetworkWorldSystem().GetChatSystem().GetUsername()));
        if IsDefined(this.m_lastMessageData) {
            messageData.m_needsAuthorLabel = NotEquals(StringToName(this.m_lastMessageData.m_author), StringToName(messageData.m_author));
        } else {
            messageData.m_needsAuthorLabel = true;
        }
        this.m_lastMessageData = messageData;
        this.WakeChat();
        inkScrollAreaRef.ScrollVertical(this.m_scrollRef, 0.0);
        this.m_messageController.PushData(messageData, true);

        let targets = new inkWidgetsSet();
        targets.Select(this.m_messageController.GetItemAt(this.m_messageController.Size() - 1));
        this.PlayLibraryAnimationOnTargets(n"new_message", targets);

        inkScrollAreaRef.ScrollVertical(this.m_scrollRef, 1.0);
    }

    private func ShowChatInput(show: Bool) -> Void {
        let blackboardSystem: ref<BlackboardSystem> = GameInstance.GetBlackboardSystem(GetGameInstance());
        let uiBlackboard: ref<IBlackboard> = blackboardSystem.Get(GetAllBlackboardDefs().UIGameData);
        if show {
            let targets = new inkWidgetsSet();
            targets.Select(this.GetWidget(n"wrapper/input_box"));
            targets.Select(this.GetWidget(n"wrapper/input_box/size_provider"));
            targets.Select(this.GetWidget(n"wrapper/chat/mask"));
            targets.Select(this.GetWidget(n"wrapper/chat/bg"));
            this.PlayLibraryAnimationOnTargets(n"to_input", targets);

            this.RequestSetFocus(inkTextInputRef.Get(this.m_inputRef));
            uiBlackboard.SetBool(GetAllBlackboardDefs().UIGameData.UIChatInputContextRequest, true, true);
            this.m_player.RegisterInputListener(this, n"OpenPauseMenu");
            this.m_player.RegisterInputListener(this, n"back");
            this.m_player.RegisterInputListener(this, n"navigate_up");
            this.m_player.RegisterInputListener(this, n"navigate_down");
            this.m_player.RegisterInputListener(this, n"ChatTop");
            this.m_player.RegisterInputListener(this, n"ChatBottom");
            this.m_player.RegisterInputListener(this, n"EnterChat");
        } else {
            this.m_repeatingScrollActionEnabled = false;
            let targets = new inkWidgetsSet();
            targets.Select(this.GetWidget(n"wrapper/input_box"));
            targets.Select(this.GetWidget(n"wrapper/input_box/size_provider"));
            targets.Select(this.GetWidget(n"wrapper/chat/mask"));
            targets.Select(this.GetWidget(n"wrapper/chat/bg"));
            this.PlayLibraryAnimationOnTargets(n"from_input", targets);

            uiBlackboard.SetBool(GetAllBlackboardDefs().UIGameData.UIChatInputContextRequest, false, true);
            this.m_player.UnregisterInputListener(this, n"OpenPauseMenu");
            this.m_player.UnregisterInputListener(this, n"back");
            this.m_player.UnregisterInputListener(this, n"navigate_up");
            this.m_player.UnregisterInputListener(this, n"navigate_down");
            this.m_player.UnregisterInputListener(this, n"ChatTop");
            this.m_player.UnregisterInputListener(this, n"ChatBottom");
            this.m_player.UnregisterInputListener(this, n"EnterChat");
            this.m_input.SetText("");
            this.RequestSetFocus(null);
        }
        this.m_chatInputOpen = show;
        this.WakeChat();
        this.UpdateInputHints();
    }

    private final func SendChat() -> Void {
        let textEntered: String = this.m_input.GetText();
        if NotEquals(textEntered, "") {
            FTLog(s"[ChatController] SendChat \"\(textEntered)\"");

            GameInstance.GetNetworkWorldSystem().GetChatSystem().Send(textEntered);
        };
    }

    private func Scroll(up: Bool) {
        let contentSize = inkScrollAreaRef.GetContentSize(this.m_scrollRef);
        // let viewportSize = this.m_scrollArea.GetViewportSize();
        let delta = 100.0 / contentSize.Y;
        // if contentSize.Y > viewportSize.Y {
        //     delta = contentSize.Y;
        // }
        let current = inkScrollAreaRef.GetVerticalScrollPosition(this.m_scrollRef);
        if up {
            inkScrollAreaRef.ScrollVertical(this.m_scrollRef, current - delta);
        } else {
            inkScrollAreaRef.ScrollVertical(this.m_scrollRef, current + delta);
        }
    }

    protected cb func OnChatInputAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
        let actionName: CName = ListenerAction.GetName(action);
        let actionType: gameinputActionType = ListenerAction.GetType(action);
        if Equals(actionType, gameinputActionType.REPEAT) {
            if !this.m_repeatingScrollActionEnabled {
                return false;
            };
            switch actionName {
            case n"navigate_up":
                this.Scroll(true);
                return true;
                break;
            case n"navigate_down":
                this.Scroll(false);
                return true;
                break;
            };
        } else if Equals(actionType, gameinputActionType.BUTTON_PRESSED) {
            if !this.m_repeatingScrollActionEnabled {
                this.m_repeatingScrollActionEnabled = true;
            };
            switch actionName {
            case n"EnterChat":
                this.SendChat();
                this.ShowChatInput(false);
                return true;
                break;
            case n"OpenPauseMenu":
                ListenerActionConsumer.DontSendReleaseEvent(consumer);
                return true;
                break;
            case n"navigate_up":
                this.Scroll(true);
                return true;
                break;
            case n"navigate_down":
                this.Scroll(false);
                return true;
                break;
            case n"ChatTop":
                inkScrollAreaRef.ScrollVertical(this.m_scrollRef, 0.0);
                return true;
                break;
            case n"ChatBottom":
                inkScrollAreaRef.ScrollVertical(this.m_scrollRef, 1.0);
                return true;
                break;
            case n"back":
                this.ShowChatInput(false);
                return true;
                break;
            };
        };
        return false;
    }

    protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
        let actionName: CName = ListenerAction.GetName(action);
        let actionType: gameinputActionType = ListenerAction.GetType(action);

        if !this.m_connected {
            return false;
        }

        if !this.m_chatInputOpen {
            if Equals(actionName, n"UIEnterChatMessage") && Equals(actionType, gameinputActionType.BUTTON_RELEASED) {
                // let targets = new inkWidgetsSet();
                // targets.Select(this.m_phoneIconWidget);
                // this.PlayLibraryAnimationOnTargets(n"onUse", targets);
                this.ShowChatInput(true);
                return true;
            } else {
                return false;
            }
        } else {
            return this.OnChatInputAction(action, consumer);
        }
    }
}

public class ChatFadeCallback extends DelayCallback {
    public let m_controller: wref<ChatController>;
    public let m_generation: Int32;

    public func Call() -> Void {
        if IsDefined(this.m_controller) {
            this.m_controller.OnFadeTimeout(this.m_generation);
        }
    }
}