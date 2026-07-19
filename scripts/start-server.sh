#!/usr/bin/env bash
# Start the NightCityMP dedicated server (built via `xmake build -y Server.Loader`).
#
# Environment:
# - DOTNET_ROLL_FORWARD=LatestMajor: the loader apphost targets net8.0; lets it
#   run on newer installed runtimes (e.g. .NET 9).
# - CYBERPUNKMP_ADMIN_USERNAME / _PASSWORD: required by the admin WebApi; the
#   process dies on the first update tick without them. The defaults below are
#   for LOCAL play only — set real values before exposing the server.
set -euo pipefail

cd "$(dirname "$0")/../build/linux/x86_64/release"

export DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-LatestMajor}"
export CYBERPUNKMP_ADMIN_USERNAME="${CYBERPUNKMP_ADMIN_USERNAME:-admin}"
export CYBERPUNKMP_ADMIN_PASSWORD="${CYBERPUNKMP_ADMIN_PASSWORD:-localtest123}"

echo "NightCityMP server starting (game udp :11778, admin api tcp :11778, flecs rest 127.0.0.1:27750)"
echo "Stop with Ctrl+C or SIGTERM (clean shutdown)."
exec ./Server.Loader "$@"
