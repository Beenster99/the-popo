class_name Scenes
extends RefCounted
## Where the game starts, and the Wave 0 / Wave 1 test scenes (reachable from
## Settings > Debug > Test scenes, not from the menus).

## The game: the city block with its police cars.
const GAME := "res://prototypes/p08_block/block.tscn"

const TESTS := [
	["0.1 Pipeline check (Blender asset with collision)", "res://prototypes/p01_pipeline/pipeline.tscn"],
	["0.2 Two players in one room", "res://prototypes/p02_netroom/netroom.tscn"],
	["0.3 Destruction spike", "res://prototypes/p03_destruction/destruction.tscn"],
	["0.3 Destruction stress test", "res://prototypes/p03_destruction/stress.tscn"],
	["0.4 Car spike", "res://prototypes/p04_car/car.tscn"],
	["0.5 Look spike (cel shading, camera, roofs)", "res://prototypes/p05_look/look.tscn"],
	["0.6 Movement and animation course", "res://prototypes/p06_movement/movement.tscn"],
	["1.6 Listening room (every gun, every material)", "res://prototypes/p07_sound/sound.tscn"],
	["1.1 City block (generated, breakable)", "res://prototypes/p08_block/block.tscn"],
	["1.2 Training yard (movement, cover, melee, revive)", "res://prototypes/p09_yard/yard.tscn"],
	["1.3 Patrol (police car, seats, lights and siren, injuries)", "res://prototypes/p10_patrol/patrol.tscn"],
]


## Loads a scene: for everyone when hosting, else just here.
static func load_scene(tree: SceneTree, path: String) -> void:
	tree.paused = false
	PlayerInput.blocked = false
	if Net.is_online():
		if Net.is_host():
			Net.load_scene_for_all(path)
	else:
		tree.change_scene_to_file(path)
