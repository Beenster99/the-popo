# Wave 5: content and polish (v0.6.0)

## Phase 5.1: catalogue expansion

- `game/world/props.gd`: new street furniture placed by district
  (`_street_furniture`): phone boxes, post boxes, vending machines, planters,
  bike racks and wheelie bins downtown; wheelie bins and post boxes on
  residential streets; tyres and cones in industrial yards and the docks; a
  hydrant on every block. New room props: TVs, fridges, washers, armchairs,
  plants, bookcases, water coolers, vending machines in lobbies, tyres in
  stores. Planters break like concrete.
- `game/vehicles/civilian_vehicle.gd`: liveries on existing bodies
  (`VARIANTS`): taxi (roof sign, chequer band), work van (ladder rack,
  beacon), courier van (side stripe), ice cream van. They join the traffic
  and parked cars.
- `game/actors/suspect_look.gd`: more shirt, trouser and hat colours.

## Phase 5.2: audio

- `tools/audio/make_wave5.py`: radio key-up, squelch and garbled talkers,
  and three music loops (menu, patrol, action), all made from scratch.
- `game/audio/police_radio.gd` (PoliceRadio): every radio line keys the
  radio; other units chatter between calls; lines queue.
- `game/audio/music_director.gd` (MusicDirector): patrol bed, crossfading to
  the action track for 14 s after a shot within earshot, or while the siren
  is on. The menu plays the title theme.
- New buses Music and Radio, with sliders in Settings > Sound.

## Phase 5.3: UI and onboarding

- `game/ui/first_shift.gd` (FirstShift): the First Shift tutorial from the
  main menu, twelve steps from walking to booking, keys shown from the live
  bindings, a marker to follow. Calls stay off until it is done, and the
  tutorial city is never saved (`BlockState.no_save`). Control rebinding and
  settings were already in place.

## Phase 5.4: stability

- `tests/unit/test_soak.gd`: a busy shift run fast (calls, blasts, weather,
  the clock past midnight, repair crews) with checks that suspects, nodes
  and repair sites stay bounded.

## Phase 5.5: release decision

- The game stays friends-only (decided by beenster): no store release.
