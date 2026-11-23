# AIRLOCK

Four-player co-op sci-fi survival horror. Engine: **Godot 4.7.x**, Compatibility renderer (runs in browsers and on weaker PCs).

**Keep this repository PRIVATE.** It contains purchased Fab assets, whose licence does not allow sharing the raw files.

## Play it in the browser (itch.io)
1. Push to `main`. GitHub Actions (`.github/workflows/export-web.yml`) builds the Web version.
2. Actions → latest run → download **airlock-web**.
3. Upload that zip to itch.io as an HTML game: 1280 × 720, fullscreen button on, SharedArrayBuffer off.

The browser build is **solo with 3 AI crew**. Online 4-player works in desktop builds only (browsers block the connection type it uses).

## Controls
| Key | Action |
| --- | --- |
| WASD / arrows, mouse | Move, look |
| Shift | Run |
| Space | Jump · in zero-g: up / push off a wall |
| Ctrl or C | Crouch · in zero-g: down |
| E (press or hold) | Use: doors, levers, consoles, pick up, revive |
| G | Put down the carried item |
| F | Flashlight |
| Esc | Menu |

## Level 1: Restore Power
1. Leave the medical bay: break the emergency glass by the door, pull the manual release.
2. Find 2 power cells (their places change every run) and fit them to the generator in Engineering (west).
3. Two crew hold both main breakers at once. Solo: hold one, an AI crew member takes the other.
4. Restart air circulation at Life Support (Engineering side room).
5. Restore communications in the Control Room (east end of the medical bay).
Optional: cycle the service tunnel airlock (south), float through the zero-g tunnel, inspect the impact-zone bulkhead.

Oxygen falls and CO2 rises until step 4. Below 16 % oxygen helmets seal and you live on suit oxygen; refill at the green O2 cabinets (3 uses each).

## What is real, what is placeholder
**Working and tested** (scripted playthrough of every step, plus a 2-player host/client test, plus the browser build loading the level):
station built from the purchased models with collision; four astronauts; weighted first-person movement, jump, crouch, zero-g; flashlight battery; interaction system; AIRLOCK doors with emergency glass and manual release; powered doors; a two-door airlock; power cells, generator, two-person breakers; life support and atmosphere; suit oxygen, health, going down and reviving; AI crew that follow, take the second breaker, revive (one medkit each) and call out power cells; objectives; HUD; emergency/main lighting; multiplayer sync of all of it through `StationState`.

**Placeholder / simplified:**
- Astronaut animation is code-driven: the purchased model has no skeleton, so it is cut into 7 rigid parts. Replace with a Mixamo-rigged model later.
- The nanite swarm is drawn from code and only appears as scripted/random glimpses. No alien AI, no attacks, no hosts yet (Phase 4).
- All sounds are synthesised stand-ins (`tools/make_audio.py`). Never listened to on real speakers.
- Crew names are "CREW 1-4". AI crew do not use oxygen, carry items, or enter zero-g.
- Engineering model and Moon Base arrived without textures; they are tinted flat colours.
- Not built: keypads/keycards, inventory beyond one carried item, proximity voice, Steam, stairs/ramps (the models have none).

## Project map
```
core/            main scene, input bindings, Sfx sound manager
multiplayer/     NetworkManager (host/join/solo)
characters/astronaut/   player.gd (Astronaut), astronaut_visual.gd, bot_brain.gd, revive_point.gd
systems/state/   StationState: the shared table every system reads and writes
systems/interaction/  Interactable base, consoles, O2/med stations, inspect points
systems/doors/   AirlockDoor, door button, emergency release, AirlockChamber
systems/power/   generator sockets, breakers        systems/items/  power cell
systems/atmosphere/  station air                    systems/lighting/  main/emergency lights
systems/zones/   vacuum, zero-g, hazard, trigger zones, sparks
alien/swarm/     swarm visual + glimpse director
levels/level.gd  spawning, AI crew, player requests  levels/station/  Level 1 rules + generated scene
ui/              title screen, pause menu, HUD
environments/    model wrapper, build kit (AIRLOCK colours/logo), star sky
assets/          models (optimised), audio, title art
tools/           DEV ONLY: build_station.gd (generates the level), make_audio.py, pipeline/ (model optimiser)
```
`levels/station/station.tscn` is **generated**. Change the layout in `tools/build_station.gd` and run
`godot --headless --path . -s tools/build_station.gd` rather than editing the scene by hand.
See `docs/ASSET_PIPELINE.md` for how the purchased models were shrunk and how collision is made.

## Desktop multiplayer test
Debug → Customize Run Instances → 4 instances, first with `--host`, the rest with `--join`, then F5.
Direct IP only for now (port 7777/UDP); Steam networking is planned for the polish phase.
