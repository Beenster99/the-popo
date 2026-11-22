# Wave 1: first playable block

Wave 1 turns the Wave 0 prototypes into one small game loop on a generated
city block. It is built phase by phase; each phase ends with a build.

## Phase 1.1: kit and generator, version 1 (v0.2.0)

- Grid standard: [grid.md](grid.md) (4 m modules, 3.25 m storeys).
- Kit: 34 pieces (walls, shop fronts, garage, parapets, interior walls,
  floors, stairwell and stairs, roofs, columns, glass, doors, pavement,
  roads, crossings, low wall, bollard, lamp post), each with its fractured
  twin, from `tools/blender/build_kit_fractured.py`.
- Generator: `game/city/block_generator.gd` lays out one block from a seed:
  a road ring with lane dashes and crossings, pavement, and 4 to 6 buildings
  (shops, houses, garages, 1 to 3 storeys, recoloured per building). Two are
  enterable, with rooms, an interior door and stairs to the floor above.
- Everything is breakable: the block is built into the DestructionWorld, so
  walls, floors, glass and lamp posts shatter and fall like the Wave 0 shops.
- Same seed, same block: checked by `tests/unit/test_city_block.gd` (same
  fingerprint for the same seed, a different one for another seed; 40 seeds
  checked for 4 to 6 buildings, two enterable, none overlapping; the whole
  block stands; an officer walks up the stairs). The host sends the seed to
  everyone, so all machines build the same block with the same piece ids.
- Officers now step up stairs and kerbs (up to 0.36 m).
- Playable as "1.1 City block" in the launcher. G (host) builds a new block
  for everyone.

![Block overview](img/block_overview.png)
![Inside an enterable shop](img/block_inside.png)

## Phase 1.2: movement and gunplay (v0.2.1)

- Climb, roll and mantle polish: hands stay on the ledge through a climb,
  rolls and vaults finish at running pace instead of stopping dead.
- Gun handling: 15-round magazine, reload (R), holster and draw (H), recoil
  kick and spread bloom, blind fire from cover (fire without aiming), torch
  (T) that everyone sees.
- Traversal: one forward scan finds the top of whatever is ahead, so the
  officer vaults low walls, car bonnets and window sills once the glass is
  gone (glass shards and splinters never block), and climbs ledges up to
  2.4 m.
- Cover: walls, cars and rubble all give cover. In cover, a direction plus
  the cover key runs to the next cover that way (up to 10 m), or swings round
  the end of the wall to its side face.
- Melee: punch (shoves and hurts), kick (bursts doors in off their hinges,
  breaks other pieces), and a shoulder barge when sprinting. All hits are
  worked out on the host (`game/actors/melee.gd`).
- Health: 100 hp. Shots (friendly fire is on), blasts and falls of more than
  about 4 m hurt. At zero the officer goes down (full ragdoll); a teammate
  holding interact next to them for 2 s gets them up with 50 hp, or they get
  up alone after 30 s with 25 hp. Health, revive progress and stagger are in
  the synced officer state.
- Playable as "1.2 Training yard" in the launcher; the City block also has
  melee, kickable doors and friendly fire.
- Ladders are left for later: none of the kit pieces needs one yet.

![Training yard](img/yard.png)

### v0.2.2: officer model fixes (beenster's playtest)

- Arms and legs are now single skinned tubes (`skinned_limb` in
  `tools/blender/officer/officer.py`), with weights blended across the
  elbow and knee, so the ball joints are gone. The torso and vest are
  lofted, skinned shells, narrow under the arms so the arms hang clear.
- Navy baseball cap with a curved peak and yellow lettering replaces the
  police hat.
- Prone: elbows down, both hands forward on the pistol, barrel level.
- Aiming at the ground near the feet no longer folds the body over (the
  barrel line-up ignores points closer than 1 m and limits the pitch).
- Kicked-in doors come off their frame and fall in.

![Officer v0.2.2](img/officer_v0_2_2.png)

### v0.2.3: menus, settings, cover and animation fixes (beenster's playtest)

- Opening menu (`game/ui/main_menu.tscn`, now the main scene): Single
  Player (pick a scene), Online (the host / join lobby), Settings, Quit.
  Esc in a game opens a pause menu (Resume, Settings, Leave to main menu);
  alone it pauses the game, online the game carries on and your officer
  stands still.
- Settings (`game/core/settings.gd`, autoload `Settings`): one SCHEMA list
  drives the screen, saved in `user://settings.cfg`, applied live.
  Graphics: window mode, size, screen, V-Sync, frame cap, renderer and
  driver (restart, through `user://override.cfg`), presets Low to Max,
  render scale, FSR 1/2, MSAA, FXAA/SMAA, TAA, debanding, anisotropy,
  mipmap bias, LOD, occlusion culling, sun and lamp shadows (size,
  distance, splits, softness, filter, 16-bit), SSAO, SSIL, SSR, SDFGI,
  VoxelGI, glow, volumetric fog, haze, subsurface scattering, specular AA,
  tone mapping, exposure, brightness, contrast, saturation. Sound: bus
  volumes, output device, mute in background. Gameplay: friendly fire
  (host's setting), camera speeds and zoom, cutaway on/off, HUD parts,
  stick dead zone, key changes. Debug: FPS and performance readout,
  network overlay, render debug views, collision shapes, fake lag, jitter
  and loss, game speed.
- Ammo panel bottom right: weapon, rounds in the gun, spare rounds
  (60 to start, 90 max; the yard's ammo box refills them).
- Inside a building, everything that would hide any part of the floor you
  stand on fades out, at any camera angle (`game/render/roof_fader.gd`).
- Hand-keyed reload (drop the mag, fresh one from the belt pouch, seat,
  rack), holster and draw clips.
- Cover: snaps to the nearest wall, car or ledge within 1.6 m any way
  round; the officer stands (or crouches, head well below a 1 m wall)
  with his back to it; moving away leaves cover; cover that is shot or
  blown away drops you out of it.
- Prone legs lie on the ground.

![Menu](img/menu_v0_2_3.png)
![Settings](img/settings_v0_2_3.png)
![Low cover and reload](img/cover_v0_2_3.png)

## Phase 1.3: police car (v0.2.4)

- Patrol car built in Blender (`tools/blender/build_police_car.py` writes
  `assets/models/vehicles/police_car.glb`): body, four doors, bonnet, boot,
  bumpers, push bar, mirrors, six windows, roof light bar and an interior.
  It drives on the shared `Car` physics (`game/vehicles/police_car.gd`).
- Damage: body, doors, bonnet and boot dent; parts near a hard hit build up
  damage and come off as loose physics pieces past their limit. Every
  window shatters when shot. Shots and blasts are worked out on the host
  and sent to everyone (`game/actors/gunfire.gd`, `car_sync.gd`).
- Lights and siren: the driver's T cycles lights, lights and wail, lights
  and yelp, off. Lenses flash and light the street; the siren is heard by
  everyone nearby.
- Four seats, so all three officers fit in one car. F at a door gets in,
  F again gets out at the nearest clear door, Ctrl moves to the next free
  seat. The officer in seat 0 drives; passengers hold aim to wind the
  window down, lean out and shoot (with extra spread).
- The boot: hold F behind the car for spare ammo and first aid.
- Injuries (added to the plan after 1.2): shots can wound the leg (limp, no
  sprint), the arm (shaky aim) or cause bleeding (health drains). Holding F
  treats one wound on yourself or a teammate from a pouch of 3; the boot
  fixes everything and refills the pouch.
- Menu change (beenster): Single Player goes straight into the city block,
  which now has two police cars. Online is host / join plus Start the game.
  The test scenes moved to Settings > Debug > Open a test scene, including
  "1.3 Patrol", a test lot with two police cars, civilian cars and ramps.
- Throwing things round or over cover is in a later phase (throwables).

![Parked](img/patrol_parked.png)
![Leaning out](img/patrol_leanout.png)
![Wrecked](img/patrol_wrecked.png)
![City block with police cars](img/block_overview_v0_2_4.png)

### v0.2.5: playtest fixes (beenster)

- Police car wheels stood flat; they now keep the model's turn and sit
  upright in the arches.
- Officers start with the gun holstered.
- Walk: Alt toggles walking pace (about 1.5 m/s, the walk clip); a light
  tilt of a controller stick walks too.
- Cutaway (`game/render/roof_fader.gd`): walls between the officer and the
  camera on their floor turn see-through instead of vanishing, so doorways
  show; anything over the officer's head or hiding them from the camera
  fades out, inside or out.
- The reticle looks through hidden ceilings, roofs and walls.
- Hold the middle mouse and drag to turn the camera; a click still pings.
- Corner peek: the feet stay at the wall's end (a small side step at most)
  and the body leans out round it (`OfficerProcedural._lean`).
- Steadier aim: the aim target is smoothed and the aim loop barely breathes.
- The support hand locks back onto the grip once the aim pose has blended
  in after a reload or draw.
- Settings sit in a centred panel 1100 px wide, and the UI scales with the
  window (stretch mode canvas items), so 4K is readable.

![Inside, v0.2.5](img/inside_v0_2_5.png)

## Phase 1.4: dispatch, suspects and arrests (v0.2.6)

- Dispatcher (`game/missions/dispatcher.gd`, host only, synced to
  everyone): the first call comes in after about 20 s, then one every
  25 to 50 s, at most two open at once. Three kinds for now: a shop
  robbery (two suspects inside), an armed person on the street, and a
  speeding car on the ring road. A call is lost after 5 minutes.
- Crime level (top of the screen): starts at 35, creeps up over time and
  faster with open calls; each suspect dealt with takes 5 off, a closed
  call 10, a lost call adds 8. Arrests and kills count the same.
- HUD (`game/ui/dispatch_hud.gd`): the crime meter, radio lines, the open
  calls with distances, and arrows at the screen edge to each call (and to
  the custody bay while anyone has a prisoner). Calls have a marker beam.
- Suspects (`game/actors/suspect.gd`): civilians in their own clothes
  (`suspect_look.gd`). They notice officers, run and hide in rooms, yards
  and upstairs (a navmesh baked from the block at load, `game/world/
  block_nav.gd`), and armed ones may shoot back instead. Aiming at one up
  close, a punch, or cornering them makes them give up: hands up, kneel.
- Arrests: hold F next to a kneeling suspect to cuff them; they follow
  you. F at a police car door seats them in the back. Drive to the
  CUSTODY bay (yellow box with a blue lamp) to book them.
- Traffic stop: get behind the speeding car with lights on and it pulls
  over; walk up and the driver gets out and gives up, or runs.
- New clips on the officer rig, reused by suspects: hands_up, cuffed,
  kneel.
- The host's J key calls in a job at once (for testing).

![A call](img/dispatch_call.png)
![Cuffed suspect following](img/dispatch_arrest.png)
![Custody bay](img/dispatch_bay.png)
