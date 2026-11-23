# v0.10.0: taller city and rooftops

Asked for after the v0.6.0 screenshots: much taller buildings with working
lifts, blocks of different sizes so the grid is less regular, and (beenster's
idea) a grapple hook to reach the roofs, with rooftop clutter and an abseil
that crashes in through windows.

## Varied blocks

- `game/city/city_generator.gd`: each column and row of lots is 9 to 15
  modules (`LOT_RANGE`, picked from the seed by `pick_sizes`); the station's
  lot stays 12. `road_at`, `lot_origin`, `lot_size`, `block_at`, `extent_x/z`
  replace the old even-grid sums everywhere (ground, roads, crossings, props,
  dispatch, peds, skyline).

## Towers and lifts

- `game/city/city_styles.gd`: downtown office and flats buildings at least
  4 x 3 modules can become a `tower` (up to two per block, 7 to 10 storeys,
  open-plan floors over a lobby). The lift shaft is the module left of the
  stairs (`shaft_rect`): no floor slab in it, interior walls round it and a
  doorway on every floor. Its back wall has no floor under it, so each storey
  hangs on the one below (`held_by`).
- `game/city/lifts.gd` (Lifts): one car per tower (AnimatableBody3D), a
  sliding door on every floor, open only while the car stands there. Host
  runs it (net messages 130, 131); clients run the same movement between
  updates. `game/ui/lift_panel.gd`: the floor buttons.

## Rooftops

- Buildings of two storeys or more (not houses or the station) get stairs to
  a hut on the roof (`_roof_hut`), a third of them locked.
- `game/world/props.gd`: `ac_unit`, `roof_vent`, `water_tank`, `sat_dish`,
  `aerial`, `roof_box`, placed by `_furnish_roof`.

## Grapple and abseil

- `game/station/armoury.gd`: item 27, Grapple hook (Gear, 1500).
- `game/city/rooftops.gd` (Rooftops): building lookup, roof height and the
  nearest outside wall.
- `game/actors/officer.gd`: states GRAPPLE (hook flies, line hauls you up,
  climb over the parapet), ROPE (W/S up and down, Shift fast, aim and shoot,
  F let go) and SWING (Space: kick off and crash in through the window at
  chest height; the host breaks the glass). All worked out from `state_t`
  and the synced move fields, so prediction and remote copies agree.
- `game/actors/grapple_rope.gd`: the line and hook you see, and the sounds.
- `tools/audio/make_v070.py`: lift chime, grapple launch, hook clank, rope
  slide.

## Tests

`tests/unit/test_city_layout.gd`, `tests/unit/test_towers.gd` (towers and
shafts, the whole city stands up, the lift carries an officer to the fourth
floor, grapple onto a roof, abseil and crash in through a window).
