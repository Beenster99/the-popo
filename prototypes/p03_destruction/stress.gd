extends Node3D
## Phase 0.3 stress test: rows of walls. Press B to blow them all at once (host).
## + and - change how many rows the next reset builds. R resets.
## The overlay shows awake synced chunks, bytes per snapshot, and bandwidth.

var sync: PawnSync
var cam: IsoCamera
var world: DestructionWorld
var rows := 4
var _hud: Label


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 140.0)
	cam = IsoCamera.new()
	cam.zoom = 40.0
	cam.zoom_max = 90.0
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := CapsuleOfficer.new()
		p.peer_id = id
		p.position = Vector3(0, 0.1, 20)
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	add_child(sync)
	_build()
	var overlay := NetOverlay.new()
	overlay.extra_lines = func():
		return "walls %d (%d chunks each)   synced awake %d   %d B/snapshot   chunks %d   physics %.1f ms\nB blow all (host)   R reset   +/- rows (%d)" % [
			world.pieces.size(), KitLibrary.get_piece("wall").chunks.size(), world.synced_awake, world.bytes_per_snapshot,
			world.chunk_count, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, rows]
	add_child(overlay)


func _build() -> void:
	if world:
		sync.extra_writers.clear()
		sync.extra_readers.clear()
		world.queue_free()
	world = DestructionWorld.new()
	world.sync = sync
	add_child(world)
	for r in rows:
		BuildingLayout.wall_row(world, Vector3(-20, 0, -r * 5.0), 10)
	world.finalize()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or not Net.is_host():
		return
	match (event as InputEventKey).physical_keycode:
		KEY_B:
			for p in world.pieces.values():
				world.damage_piece(p.id, 9999.0, p.aabb.get_center() + Vector3(0, 0, 1.5), 6.0)
		KEY_R:
			_build()
		KEY_EQUAL, KEY_KP_ADD:
			rows = min(rows + 1, 12)
		KEY_MINUS, KEY_KP_SUBTRACT:
			rows = max(rows - 1, 1)
