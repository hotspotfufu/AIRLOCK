# AIRLOCK — Milestone 1: Technical Foundation

Four-player co-op sci-fi survival horror. Engine: **Godot 4.7.x** (Forward+).

## Open the project
1. Install Godot **4.7.x standard** (not .NET) from godotengine.org.
2. Project Manager → **Import** → select this folder's `project.godot`.
3. The first open imports assets and builds the class cache (takes a few seconds).
   If Godot asks to upgrade or reports errors, copy the **Output** panel text and send it to me.

## Test four players on one PC
1. **Debug → Customize Run Instances…**
2. Tick *Enable Multiple Instances*, set **4**.
3. Instance 1 launch arguments: `--host`. Instances 2–4: `--join`.
4. Press **F5**. Four windows open; the host starts the session and the other three connect automatically (they retry for ~5 s).

Manual alternative: run normally, click **Host Game** in one window and **Join** (127.0.0.1) in the others.
Across two PCs on the same network: join using the host's local IP. Over the internet, direct IP needs port **7777/UDP** forwarded on the host's router — Steam networking (Milestone 8) removes that need.

## Controls
| Key | Action |
| --- | --- |
| WASD / arrows | Move |
| Mouse | Look |
| Shift (forward) | Run |
| Ctrl or C (hold) | Crouch |
| F | Flashlight on/off |
| Esc | Menu (Resume / Leave Session) |
| E | Reserved for interaction (Milestone 2) |

## Milestone 1 test checklist
- [ ] 4 players spawn in Crew Quarters, facing the corridor
- [ ] Each player sees the other three move, turn, look up/down
- [ ] Crouch is visible on other screens; you can crouch into the maintenance crawlspace and can't stand up inside it
- [ ] Flashlight toggles are visible on other screens
- [ ] A 5th instance can't join (session full message)
- [ ] A client leaving removes their astronaut for everyone; they can rejoin
- [ ] The host leaving returns everyone to the menu with a message

## How the pieces connect
```
core/main.tscn  (persistent)            multiplayer/network_manager.gd (autoload)
 ├─ Level  ← LevelSpawner copies the     host() / join() / leave(), session signals
 │          host's level to clients     core/input_setup.gd (autoload)
 │   └─ levels/test_ship/test_ship.tscn  all key bindings
 │        ├─ SpawnPoints (4 markers)
 │        ├─ Players ← PlayerSpawner (levels/level.gd spawns 1 astronaut per peer)
 │        │    └─ characters/astronaut/player.tscn
 │        │         ├─ player.gd: first-person controller (owner's machine only)
 │        │         └─ MultiplayerSynchronizer: position, facing, pitch, crouch, flashlight
 └─ UI: MainMenu, PauseMenu, StatusLabel
```

## What is real vs placeholder (Milestone 1)
**Implemented:** host/join/leave over ENet (direct IP), 4-player cap, level replication (late joiners get the level), player spawning/despawning, first-person walk/run/crouch/look, headroom check, synced flashlight, pause menu, auto host/join launch args, folder structure, physics/render layer names.

**Placeholder:** astronaut is a capsule with a visor; level is greybox CSG; menu is plain text; no audio; remote players snap to network updates without interpolation (fine on LAN, smoothing comes later).

**Not implemented yet:** Steam (see below), interaction, doors, power, oxygen, alien, voice chat, damage/revive.

**Not yet run in Godot by me** — this code was written without access to the engine. Expect a round of small fixes on first open.

## Steam (prepared, not connected)
Plan for Milestone 8 (earlier if you want to test online with friends):
1. Install the **GodotSteam GDExtension** matching your Godot version into `addons/` (Godot Asset Library → "GodotSteam GDExtension").
2. Add a `SteamTransport` in `multiplayer/transports/` using `SteamMultiplayerPeer`; `NetworkManager.host()/join()` switch to it. Nothing else changes.
3. For development, create `steam_appid.txt` containing `480` (Valve's test app) next to the executable. Your real App ID comes after paying the Steam Direct fee.
4. Export: Project → Export → add **Windows Desktop** (and **Linux** for Steam Deck) presets; install export templates when prompted.
