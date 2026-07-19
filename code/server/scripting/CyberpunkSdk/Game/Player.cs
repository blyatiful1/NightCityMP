using CyberpunkSdk.Internal;

namespace CyberpunkSdk.Game
{
    public class Player
    {
        private IPlayer player;

        internal Player(IPlayer player)
        {
            this.player = player;
        }

        public void SendChat(string From, string Message)
        {
            // GetById wraps a null native handle once the player disconnected;
            // chatting at a gone player must be a no-op, not an NRE (an NRE on
            // the finalizer thread kills the whole server process).
            player?.SendChat(From, Message);
        }

        // True while the underlying native player still exists; false after
        // disconnect (GetById then wraps a null handle).
        public bool IsValid
        {
            get { return player != null; }
        }

        public ulong Id
        {
            get { return player?.Id ?? 0; }
        }

        public ulong PuppetId
        {
            get {  return player?.PuppetId ?? 0; }
        }

        public uint ConnectionId
        {
            get {  return player?.ConnectionId ?? 0; }
        }

        public Components.MovementComponent MovementComponent
        {
            get { return new Components.MovementComponent(player.MovementComponent); }
        }

        public Components.AttachmentComponent AttachmentComponent
        {
            get { return new Components.AttachmentComponent(player.AttachmentComponent); }
        }

        public string Username
        {
            get { return player.Username; }
        }
    }
}
