using CyberpunkSdk;
using CyberpunkSdk.Systems;
using CyberpunkSdk.Types;

namespace JobSystem
{
    // Server-authoritative time of day: every client gets the same clock so
    // lighting/ambience match across sessions. Hosted in the JobSystem plugin
    // to reuse its wiring; semantically world-state, not a job.
    internal class WorldClock
    {
        // Vanilla-ish pacing: 8 real seconds per game minute.
        private const double GameSecondsPerRealSecond = 60.0 / 8.0;

        private double gameSeconds = 12.0 * 3600.0; // server boots at noon
        private readonly object clockLock = new();
        private readonly Logger logger = new Logger("WorldClock");

        internal WorldClock()
        {
            Server.PlayerSystem.PlayerJoinEvent += OnPlayerJoin;
            Server.World.UpdateEvent += Update;
            Server.Timer.Add(Broadcast, 60.0f);
        }

        private void Update(float delta)
        {
            lock (clockLock)
            {
                gameSeconds = (gameSeconds + delta * GameSecondsPerRealSecond) % 86400.0;
            }
        }

        private void OnPlayerJoin(ulong playerId)
        {
            Send(playerId, 0.0f);
        }

        private void Broadcast(float delta)
        {
            foreach (var id in Server.PlayerSystem.PlayerIds)
                Send(id, 2.0f);
        }

        private void Send(ulong playerId, float blend)
        {
            uint hours, minutes, seconds;
            lock (clockLock)
            {
                var t = (long)gameSeconds;
                hours = (uint)(t / 3600);
                minutes = (uint)(t / 60 % 60);
                seconds = (uint)(t % 60);
            }
            // Empty weather CName = leave each client's local weather alone.
            Cyberpunk.Rpc.Client.Plugins.WorldStateClient.SetWorldState(playerId, hours, minutes, seconds, new CName(""), blend);
            logger.Info($"sent {hours:D2}:{minutes:D2}:{seconds:D2} to player {playerId}");
        }
    }
}
