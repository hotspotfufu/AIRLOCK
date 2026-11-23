# Asset pipeline (dev notes)

The purchased files were 185 MB and several million triangles: too big for GitHub's
25 MB web upload and too heavy for a browser. `tools/pipeline/` shrinks them.

| Game file | Source (Fab) | What was done |
| --- | --- | --- |
| station/junction.glb | Sci-Fi Horror Corridor (66 MB, 501k tris) | textures to 1024 px JPEG, vertex clustering 2 cm (251k tris), doorways cut through the four solid end walls |
| station/room_interior.glb | Space Station Corridor interior (79 MB, 1.52M tris, no textures) | duplicate meshes shared, clustering 3.5 cm (287k tris), unused UVs dropped, floor outside the walls trimmed, south end wall removed for a doorway, flat material colours |
| station/window_corridor.glb | Sci-Fi Corridor trimsheet (35 MB) | textures 4096 -> 1024 px |
| station/tunnel.glb | Tunnel SciFi | unchanged apart from re-packing |
| station/moon_base.fbx | Moon Base | unchanged (imported by Godot directly) |
| astronaut/astronaut.glb | Astronaut (static, 87k tris) | 39k tris, cut into 7 rigid parts with joint pivots, turned to face -Z, feet at y=0 |

Commands (need Python 3 with numpy, Pillow, scipy; originals are NOT in the repo):
```
python3 tools/pipeline/glbopt.py <in.glb> <out.glb> --tex 1024 --cell 0.02 [...]
python3 tools/pipeline/make_astronaut.py
```

## Collision
Character collision is not the render meshes. `tools/build_station.gd -- dump` writes every
triangle between ankle and head height; `tools/pipeline/collide.py` turns them into a 20 cm
wall map and merges it into ~290 boxes (`levels/station/collision_boxes.json`). Floors are
flat slabs listed in `build_station.gd`. The AI crew's navmesh is baked from those boxes.
If a model moves, re-run dump -> collide.py -> build.

## Known engine quirk
Exported builds dropped `PackedStringArray` / typed-array `@export` values saved in the
level scene (fine in the editor, empty in the export). Level-facing exports therefore use
plain comma-separated Strings.
