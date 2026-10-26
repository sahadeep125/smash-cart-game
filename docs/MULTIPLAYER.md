# Kart Clash multiplayer

Kart Clash supports three ways to play, all running the same game code:

| | Solo | LAN | Online |
|---|---|---|---|
| Players | 1 + up to 15 bots | up to 16 karts (humans + bots) | up to 4 humans + bots |
| Transport | none | ENet (UDP), port 24680 | Supabase Realtime broadcast (WebSocket) |
| Finding a game | — | automatic LAN discovery (UDP 24681) or type the host IP | 5-letter room code |
| Platforms | all | Android, iOS, desktop (not web: browsers can't open UDP sockets) | all, including web |

Modes: **Free-for-all** and **Team Deathmatch** (2–4 teams of 1–4 karts; empty slots are
filled with bots; no friendly fire; team kills don't score; the team with the most kills wins).

## Design: host-authoritative, owner-driven karts

One player hosts (peer 1). The host's game is the authority:

- **Host simulates** bots, all weapons and damage, crates, deaths, respawns and the match
  clock, and sends a snapshot of every kart (position, velocity, health, weapon, ammo,
  shield) plus crate state and time left 20×/s on LAN, 6×/s online.
- **Each player drives their own kart locally** (no input lag) and sends its state to the
  host 20×/s on LAN, 4×/s online. Other karts are shown with dead reckoning
  (last position + velocity) eased toward each update.
- **Shooting:** pressing fire on a client sets a trigger flag in its next state packet; the
  host fires the real weapon for that kart. Rockets, mines and explosions are sent as
  reliable events and shown as visual-only copies on clients; machine-gun tracers are
  drawn on clients while the snapshot says a kart is firing.
- **Knockback** that hits a client's kart on the host is forwarded to that client.
- **Kills, respawns and scores** come from the host as reliable events, so every screen
  shows the same scoreboard. The automated test checks that host and client end with
  identical results.
- If a client leaves mid-match its kart becomes a bot. If the host leaves, everyone
  returns to the Play screen with a message.

Files: `scripts/net/net.gd` (autoload: sessions, lobby, start/return), `scripts/net/match_sync.gd`
(in-match sync), `scripts/net/lan_discovery.gd`, `scripts/net/supabase_peer.gd`.

## Online through Supabase

`SupabasePeer` is a Godot `MultiplayerPeerExtension`, so all game RPCs work unchanged over it.
It joins the Realtime channel `realtime:kartclash-<ROOM>` (Phoenix protocol v1, JSON over a
WebSocket), batches Godot packets into one broadcast per send tick, base64-encodes them, and
drops packets addressed to other peers. Nothing runs on Supabase except its built-in Realtime
relay: no tables, functions or database schema are needed.

**Setup (once, free):**
1. Create a project at supabase.com.
2. In *Project Settings → API*, copy the **Project URL** and the **anon public** key.
3. Make sure *Realtime* is enabled and public channels are allowed
   (*Realtime → Settings → "Allow public access"*), which is the default.
4. In the game: *Play → Online*, paste both values. One player taps **Create a room** and
   reads out the code; the others type it and tap **Join**.

The anon key is designed to be public (it ships in every Supabase web app), but anyone with
it can use your project's Realtime quota, so don't post it widely.

**Quota.** Supabase's free plan allows 100 Realtime messages per second for the whole project,
counting every delivery. Measured with the mock server (which counts the same way), a
2-player room uses about 25–30 messages/s and a 4-player room about 72/s (peaks around 92),
so four humans fit in the free plan, but only one room at a time per project. Larger rooms need the Pro plan (500/s), and
`Net.MAX_ONLINE_PLAYERS` / the send rates in `net.gd` can be raised accordingly. If the quota is
exceeded Supabase disconnects the socket and the game returns to the Play screen.

**Latency.** Messages go through Supabase's servers, so online play has noticeably more delay
than LAN (each player still drives their own kart instantly; what lags is other karts and
hit confirmation).

## Testing

- `tests/run_net_test.sh lan` starts a host and a client as two headless Godot processes on
  this machine, plays a 60-second 4v4 Team Deathmatch and checks join, lobby, teams, driving,
  sync, kills, respawns, match end, identical results and return to the lobby.
- `tests/run_net_test.sh online` does the same through `tests/mock_realtime.py`, a small
  stand-in for Supabase Realtime that implements the documented protocol and prints the
  message rate (needs `pip install websockets`).

The online path has **not** been tested against a real Supabase project (the build machine
can't reach supabase.co); the mock follows Supabase's published message shapes.

## Platform notes

- **Android:** the export preset enables the INTERNET and Wi-Fi multicast permissions.
  Some phones still filter UDP broadcasts; if a game doesn't appear in the list, join by IP.
- **iOS:** the preset adds the Local Network usage description. Receiving LAN broadcasts on
  iOS 14+ needs Apple's multicast entitlement, so discovery may not list games there; joining
  by IP and online play work without it.
- **Web:** online only (browsers can't use UDP). LAN hosting needs the app on another device.
- All players need the same game version (checked when joining).
