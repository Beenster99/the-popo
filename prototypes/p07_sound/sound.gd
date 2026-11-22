extends Node3D
## Phase 0.7 sound spike. A street with a shop you can walk into and a thick
## wall to hide behind. Three test guns fire in turn: one in the street, one
## inside the shop and one behind the wall. Walk around and listen:
##   street   dry crack and body, then the slapback echo off the facades
##   inside   no echo tail, a tight bright room reverb instead
##   walls    each wall between the shot and your ears muffles and quietens it
## Shoot the targets to hear impacts on wood, glass, concrete and metal.
## F4 pauses the test guns. Glass panes break and come back after 3 s.

const ROOM := Vector3(6, 0, -6)       # centre of the shop floor
const ROOM_SIZE := Vector3(8, 3.2, 6)
const TEST_GUNS := [
	["street", Vector3(-8, 1.3, 4)],
	["inside the shop", Vector3(6, 1.3, -7)],
	["behind the wall", Vector3(-8, 1.3, -12)],
]
const GUN_EVERY := 1.6

var cam: IsoCamera
var sync: PawnSync
var sfx: SfxSync
var auto_fire := true
var _next_gun := 0
var _timer := 0.8
var _last_test := ""


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 120.0, Color("3d4045"))
	sfx = SfxSync.new()
	add_child(sfx)
	var conc := Color("a9a49a")
	var brick := Color("8a4a36")
	# A tall facade at the back of the block (the outdoor echo is tuned to one
	# about 19 m away). Kept behind everything so the iso camera sees the street.
	ProtoWorld.block(self, Vector3(40, 9, 1), Vector3(0, 4.5, -20), Color("7d6f63"), "FacadeBack")
	# The shop: four walls with a door gap on the street side, and a roof.
	var c := ROOM
	var h := ROOM_SIZE.y
	ProtoWorld.block(self, Vector3(ROOM_SIZE.x, h, 0.3), c + Vector3(0, h * 0.5, -ROOM_SIZE.z * 0.5), brick, "ShopBack")
	ProtoWorld.block(self, Vector3(0.3, h, ROOM_SIZE.z), c + Vector3(-ROOM_SIZE.x * 0.5, h * 0.5, 0), brick, "ShopLeft")
	ProtoWorld.block(self, Vector3(0.3, h, ROOM_SIZE.z), c + Vector3(ROOM_SIZE.x * 0.5, h * 0.5, 0), brick, "ShopRight")
	ProtoWorld.block(self, Vector3(3.0, h, 0.3), c + Vector3(-2.5, h * 0.5, ROOM_SIZE.z * 0.5), brick, "ShopFrontL")
	ProtoWorld.block(self, Vector3(3.0, h, 0.3), c + Vector3(2.5, h * 0.5, ROOM_SIZE.z * 0.5), brick, "ShopFrontR")
	ProtoWorld.block(self, Vector3(2.0, 0.9, 0.3), c + Vector3(0, h - 0.45, ROOM_SIZE.z * 0.5), brick, "ShopLintel")
	var roof := ProtoWorld.block(self, Vector3(ROOM_SIZE.x + 0.4, 0.25, ROOM_SIZE.z + 0.4), c + Vector3(0, h + 0.12, 0), Color("4b4e55"), "ShopRoof")
	roof.visible = false  # left off so the iso camera sees in; it still blocks sound
	var zone := SoundZone.new()
	zone.size = ROOM_SIZE - Vector3(0.3, 0, 0.3)
	zone.position = c + Vector3(0, h * 0.5, 0)
	add_child(zone)
	# A thick freestanding wall between the street and the third test gun.
	ProtoWorld.block(self, Vector3(8, 3.5, 0.6), Vector3(-8, 1.75, -9), conc, "ThickWall")
	# Surface targets along the street.
	_target("wood", Vector3(-4, 0.6, 9), Vector3(1.2, 1.2, 1.2), Color("9b6a3c"), true)
	_target("wood", Vector3(-2.6, 0.45, 9.2), Vector3(0.9, 0.9, 0.9), Color("8d5e33"), true)
	for i in 3:
		_target("glass", Vector3(0.2 + i * 1.3, 1.4, 10), Vector3(1.2, 1.6, 0.06), Color(0.7, 0.85, 0.95), false)
	_target("concrete", Vector3(5.5, 1.5, 10), Vector3(0.8, 3.0, 0.8), conc, false)
	_target("metal", Vector3(8, 0.7, 9.5), Vector3(1.0, 1.4, 0.7), Color("5c6a75"), true)
	_target("metal", Vector3(9.4, 1.2, 10.3), Vector3(1.4, 0.9, 0.05), Color("c9cfd4"), false)
	for g in TEST_GUNS:
		_gun_marker(g[1], g[0])

	cam = IsoCamera.new()
	cam.zoom = 16.0
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := Officer.new()
		p.peer_id = id
		p.position = Vector3(-1 + Net.player_ids().find(id) * 1.5, 0.05, 4)
		if Net.is_host():
			p.fired.connect(_on_fired)
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p):
		if id == Net.my_id():
			cam.target = p
			Sfx.attach_listener(p))
	add_child(sync)
	var overlay := NetOverlay.new()
	overlay.extra_lines = _hud_text
	add_child(overlay)


func _hud_text() -> String:
	var last := "none yet"
	if not Sfx.history.is_empty():
		var s: Dictionary = Sfx.history[-1]
		last = "%s on %s bus, %d wall(s) to your ears, low-pass %d Hz" % [s.stem, s.bus, s.walls, int(s.cutoff)]
	return "Test guns %s (F4)  last test shot: %s\nLast sound: %s\nLMB fire at the wood, glass, concrete and metal targets. Walk into the shop and behind the wall." % [
		"firing" if auto_fire else "paused", _last_test, last]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F4:
		auto_fire = not auto_fire


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not auto_fire:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = GUN_EVERY
	var g: Array = TEST_GUNS[_next_gun]
	_next_gun = (_next_gun + 1) % TEST_GUNS.size()
	_last_test = g[0]
	sfx.gunshot(g[1])


func _on_fired(origin: Vector3, dir: Vector3, _alt: bool) -> void:
	sfx.gunshot(origin)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0, 1 | 16))
	if hit.is_empty():
		return
	var surface := Sfx.surface_of(hit.collider)
	sfx.impact(hit.position, surface, 1.0)
	if hit.collider is RigidBody3D:
		(hit.collider as RigidBody3D).apply_impulse(dir * 5.0, hit.position - hit.collider.global_position)
	elif surface == "glass":
		_break_glass(hit.collider)


func _break_glass(pane: Node3D) -> void:
	# Placeholder shatter: hide the pane and its collision, bring it back later.
	pane.visible = false
	var body := pane as CollisionObject3D
	body.collision_layer = 0
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(body):
			body.visible = true
			body.collision_layer = 1)


func _target(surface: String, pos: Vector3, size: Vector3, color: Color, loose: bool) -> Node3D:
	var n: Node3D
	if loose:
		n = ProtoWorld.rigid_box(self, size, pos, color, 8.0 if surface == "wood" else 25.0)
		(n as RigidBody3D).contact_monitor = true
		(n as RigidBody3D).max_contacts_reported = 2
		(n as RigidBody3D).body_entered.connect(_on_loose_hit.bind(n))
	else:
		n = ProtoWorld.block(self, size, pos, color, surface.capitalize())
	n.set_meta("surface", surface)
	return n


func _on_loose_hit(_other: Node, body: RigidBody3D) -> void:
	# Knocked-over props clatter on the ground with their own surface sound.
	if not Net.is_host():
		return
	var speed := body.linear_velocity.length()
	if speed > 1.5 and Time.get_ticks_msec() - int(body.get_meta("last_clack", 0)) > 150:
		body.set_meta("last_clack", Time.get_ticks_msec())
		sfx.impact(body.global_position, body.get_meta("surface"), clampf(speed / 6.0, 0.15, 1.0))


func _gun_marker(at: Vector3, label: String) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.25
	cyl.height = 0.5
	m.mesh = cyl
	m.material_override = Cel.material(Color("ffcc33"))
	m.position = Vector3(at.x, 0.25, at.z)
	add_child(m)
	var l := Label3D.new()
	l.text = "TEST GUN: " + label.to_upper()
	l.position = Vector3(at.x, 0.03, at.z + 0.8)
	l.rotation_degrees.x = -90
	l.font_size = 72
	l.outline_size = 14
	l.modulate = Color("fff6d0")
	add_child(l)
