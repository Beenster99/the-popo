extends Node3D
## Phase 0.2: up to three officers in one room, host-authoritative movement
## with prediction for yourself and interpolation for everyone else. F3 shows
## the network overlay with fake latency and packet loss.

const COLORS := [Color("2c4a8c"), Color("8c2c3c"), Color("2c8c5a")]

var sync: PawnSync
var cam: IsoCamera


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 30.0, Color("8a8478"))
	# A room: four walls with a doorway, plus a few crates and a ramp.
	var wall := Color("c9c1b0")
	ProtoWorld.block(self, Vector3(16, 2.5, 0.3), Vector3(0, 1.25, -8), wall)
	ProtoWorld.block(self, Vector3(0.3, 2.5, 16), Vector3(-8, 1.25, 0), wall)
	ProtoWorld.block(self, Vector3(0.3, 2.5, 16), Vector3(8, 1.25, 0), wall)
	ProtoWorld.block(self, Vector3(6.5, 2.5, 0.3), Vector3(-4.75, 1.25, 8), wall)
	ProtoWorld.block(self, Vector3(6.5, 2.5, 0.3), Vector3(4.75, 1.25, 8), wall)
	ProtoWorld.block(self, Vector3(1.2, 0.9, 1.2), Vector3(-3, 0.45, -2), Color("a0703a"))
	ProtoWorld.block(self, Vector3(1.2, 0.9, 1.2), Vector3(3, 0.45, 3), Color("a0703a"))
	var ramp := ProtoWorld.block(self, Vector3(3, 0.3, 5), Vector3(4, 0.6, -4), Color("7a7a86"))
	ramp.rotation_degrees.x = 15

	cam = IsoCamera.new()
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := CapsuleOfficer.new()
		p.peer_id = id
		p.color = COLORS[Net.player_ids().find(id) % COLORS.size()] if Net.player_ids().has(id) else COLORS[0]
		p.position = Vector3(randf_range(-3, 3), 0.1, randf_range(-3, 3))
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p): if id == Net.my_id(): cam.target = p)
	add_child(sync)

	var overlay := NetOverlay.new()
	overlay.extra_lines = func(): return "prediction corrections %d (last %.2f m)" % [sync.prediction_errors, sync.last_correction]
	add_child(overlay)
