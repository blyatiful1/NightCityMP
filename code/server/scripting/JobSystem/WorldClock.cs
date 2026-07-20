using System;
using System.Globalization;
using System.IO;
using CyberpunkSdk;
using CyberpunkSdk.Systems;
using CyberpunkSdk.Types;

namespace JobSystem
{
    // Server-authoritative time of day + weather: every client gets the same
    // clock and sky so the worlds match across sessions. Hosted in the
    // JobSystem plugin to reuse its wiring; semantically world-state, not a job.
    //
    // The clock is persisted (world-clock.txt next to the server binary) so
    // the world's time survives server restarts — first piece of the
    // "world lives on the server" model. Weather is a deterministic cycle
    // derived from total elapsed game time, so it both matches across clients
    // and survives restarts for free.
    internal class WorldClock
    {
        // Vanilla-ish pacing: 8 real seconds per game minute.
        private const double GameSecondsPerRealSecond = 60.0 / 8.0;
        private const string StateFile = "world-clock.txt";
        private const double WeatherPeriodGameSeconds = 2.0 * 3600.0; // sky changes every 2 game hours

        // 2.x environment weather states; cycle chosen to be mostly-clear.
        private static readonly string[] WeatherCycle =
        {
            "24h_weather_sunny",
            "24h_weather_light_clouds",
            "24h_weather_cloudy",
            "24h_weather_rain",
            "24h_weather_heavy_clouds",
            "24h_weather_fog",
            "24h_weather_sunny",
            "24h_weather_pollution",
        };

        // Total game seconds since world creation (never wraps); the display
        // clock is total % 86400. Starts at noon for a fresh world.
        private double totalGameSeconds = 12.0 * 3600.0;
        private readonly object clockLock = new();
        private readonly Logger logger = new Logger("WorldClock");
        private string lastWeather = "";

        internal WorldClock()
        {
            Load();
            Server.PlayerSystem.PlayerJoinEvent += OnPlayerJoin;
            Server.World.UpdateEvent += Update;
            Server.Timer.Add(Broadcast, 60.0f);
        }

        private void Update(float delta)
        {
            lock (clockLock)
            {
                totalGameSeconds += delta * GameSecondsPerRealSecond;
            }
        }

        private void OnPlayerJoin(ulong playerId)
        {
            Send(playerId, 0.0f);
        }

        private void Broadcast(float delta)
        {
            foreach (var id in Server.PlayerSystem.PlayerIds)
                Send(id, 15.0f);
            Save();
        }

        private void Send(ulong playerId, float blend)
        {
            uint hours, minutes, seconds;
            string weather;
            lock (clockLock)
            {
                var t = (long)(totalGameSeconds % 86400.0);
                hours = (uint)(t / 3600);
                minutes = (uint)(t / 60 % 60);
                seconds = (uint)(t % 60);
                weather = WeatherCycle[(long)(totalGameSeconds / WeatherPeriodGameSeconds) % WeatherCycle.Length];
            }
            Cyberpunk.Rpc.Client.Plugins.WorldStateClient.SetWorldState(playerId, hours, minutes, seconds, new CName(weather), blend);
            if (weather != lastWeather)
            {
                logger.Info($"weather -> {weather}");
                lastWeather = weather;
            }
            logger.Info($"sent {hours:D2}:{minutes:D2}:{seconds:D2} to player {playerId}");
        }

        private void Load()
        {
            try
            {
                if (File.Exists(StateFile) &&
                    double.TryParse(File.ReadAllText(StateFile).Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var saved) &&
                    saved > 0.0)
                {
                    totalGameSeconds = saved;
                    logger.Info($"restored world clock: {(long)(saved / 86400.0)} day(s), {(long)(saved % 86400.0) / 3600:D2}:{(long)(saved % 86400.0) / 60 % 60:D2}");
                }
            }
            catch (Exception e)
            {
                logger.Info($"could not restore world clock ({e.Message}); starting fresh at noon");
            }
        }

        private void Save()
        {
            try
            {
                double total;
                lock (clockLock) { total = totalGameSeconds; }
                File.WriteAllText(StateFile, total.ToString("R", CultureInfo.InvariantCulture));
            }
            catch (Exception e)
            {
                logger.Info($"could not persist world clock: {e.Message}");
            }
        }
    }
}
