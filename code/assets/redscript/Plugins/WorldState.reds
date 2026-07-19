module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*

// Server-authoritative world clock: the server sends its game time on join
// and periodically resyncs, so lighting/ambience match across sessions.
// Weather rides the same RPC; an empty CName leaves local weather alone.
public class WorldStateClient extends ClientRpc {
    public func SetWorldState(hours: Uint32, minutes: Uint32, seconds: Uint32, weather: CName, blend: Float) -> Void {
        GameInstance.GetTimeSystem(GetGameInstance()).SetGameTimeByHMS(Cast<Int32>(hours), Cast<Int32>(minutes), Cast<Int32>(seconds));
        if NotEquals(weather, n"") {
            GameInstance.GetWeatherSystem(GetGameInstance()).SetWeather(weather, blend, 5u);
        }
    }
}
