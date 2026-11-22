# Wave 1 grid standard

Every kit piece and the block generator use one grid, so pieces from any
wave snap together.

| Measure | Value | Notes |
|---|---|---|
| Module | 4.0 m | Wall length, floor and roof tile, pavement and road tile |
| Half module | 2.0 m | `wall_half`, `slab_half`, `roof_half`, `parapet_half` |
| Storey | 3.25 m | 3.0 m wall plus a 0.25 m floor slab |
| Exterior wall | 0.25 m thick | Centred on the module line; corner pillars (0.4 m) close the corners |
| Interior wall | 0.12 m thick | Plaster partitions, not load bearing |
| Door opening | 1.4 m x 2.4 m | Front doors; interior doors 1.0 m x 2.2 m |
| Window opening | 1.6 m x 1.4 m, sill 0.9 m | Half window 1.0 m wide |
| Shop window | 3.2 m x 1.8 m, sill 0.5 m | Shop door module: 1.4 m door plus a 1.5 m window |
| Garage opening | 3.2 m x 2.6 m | |
| Stairs | 17 steps, 0.19 m rise, 0.22 m run, 1.2 m wide | One storey in one 4 m tile, with `slab_stairwell` above |
| Pavement | 0.15 m high | Buildings stand on it; anything below 0.2 m counts as on the ground |
| Road | 0.05 m slab at ground level | Ring three modules wide round each block |
| Parapet | 1.0 m high | Round every flat roof |

## Kit pieces (34)

Walls: `wall`, `wall_window`, `wall_door`, `wall_half`, `wall_half_window`,
`wall_shopfront`, `wall_shopdoor`, `wall_garage`, `parapet`, `parapet_half`.
Interior: `int_wall`, `int_wall_door`, `int_wall_half`.
Floors and structure: `slab`, `slab_half`, `slab_stairwell`, `stairs`,
`roof`, `roof_half`, `column`, `column_thin`.
In openings: `glass_window`, `glass_half_window`, `glass_shopfront`,
`glass_shopdoor`, `door_closed`, `garage_door`.
Street: `pavement`, `road`, `road_line`, `road_crossing`, `low_wall`,
`bollard`, `lamp_post`.

Each piece has a pre-fractured twin (Voronoi cells, convex for Jolt), built
by `tools/blender/build_kit_fractured.py` into
`assets/models/kit/kit_fractured.glb`. Exterior walls are recoloured per
building in the game (material `kit_wall`), so one kit gives many looks.
Glass hangs in its wall (it stands while the wall stands) and is drawn
see-through.

## The block (`game/city/block_generator.gd`)

A block is 12 x 12 modules of pavement inside a road ring. Buildings line
the four sides facing the street, 4 to 6 of them, 2 to 6 modules wide and 2
to 3 deep, 1 to 3 storeys, as shops, houses or garages. Two are enterable:
open doorways, a partition wall with a door, and stairs to the upper floor.
Gaps become yards and alleys. The same seed gives the same block, with the
same piece ids, on every machine (`tests/unit/test_city_block.gd`).
