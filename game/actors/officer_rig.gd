class_name OfficerRig
extends Node3D
## The officer's look and animation: the Blender-made model, an AnimationTree
## with an upper/lower body split, procedural layers (foot placement, gun
## hand lock, head and aim tracking) and physics hit reactions.
##
## The rig only reads the officer's state; it never moves the body. That way
## it runs the same for your own officer and for other players' officers.

const MODEL := preload("res://assets/models/characters/officer.glb")
const UPPER_BONES := ["spine", "chest_2", "neck_2", "head_2", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"]
const LOWER_STATES := ["idle", "walk", "run", "crouch_idle", "crouch_walk", "prone_idle", "crawl", "cover_idle",
	"peek", "slide", "roll", "mantle", "climb", "jump", "fall", "kick"]
const UPPER_STATES := ["none", "aim_hold", "ready_hold", "punch"]
var RUN_CLIP_SPEED := 3.3    # m/s of the run cycle (2.27 for the mocap run)
const WALK_CLIP_SPEED := 1.4
const CROUCH_CLIP_SPEED := 1.0
const CRAWL_CLIP_SPEED := 0.45

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var procedural: OfficerProcedural
var physics: PhysicalBoneSimulator3D
var _lower := ""
var _upper := ""
var _hit_t := 0.0
var downed := false


func _ready() -> void:
	model = MODEL.instantiate()
	add_child(model)
	Cel.apply(model, true, 0.012)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	anim_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	# Mocap base plus hand-keyed clips, merged once and shared by every officer.
	var lib := OfficerClips.library(anim_player, skeleton)
	anim_player.remove_animation_library("")
	anim_player.add_animation_library("", lib)
	for n in ["idle", "walk", "run", "crouch_idle", "crouch_walk", "prone_idle", "crawl", "cover_idle", "fall", "aim_hold", "ready_hold", "peek"]:
		if lib.has_animation(n):
			lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if "run" in OfficerClips.mocap_clips:
		RUN_CLIP_SPEED = 2.27
	_build_tree()
	procedural = OfficerProcedural.new()
	skeleton.add_child(procedural)
	_build_ragdoll()


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.root_node = tree.get_path_to(model)
	var bt := AnimationNodeBlendTree.new()
	var lower := AnimationNodeTransition.new()
	lower.xfade_time = 0.15
	lower.input_count = LOWER_STATES.size()
	for i in LOWER_STATES.size():
		lower.set_input_name(i, LOWER_STATES[i])
		lower.set_input_reset(i, LOWER_STATES[i] in ["slide", "roll", "mantle", "climb", "jump", "kick"])
		var an := AnimationNodeAnimation.new()
		an.animation = LOWER_STATES[i]
		var ts := AnimationNodeTimeScale.new()
		bt.add_node("a_" + LOWER_STATES[i], an)
		bt.add_node("ts_" + LOWER_STATES[i], ts)
		bt.connect_node("ts_" + LOWER_STATES[i], 0, "a_" + LOWER_STATES[i])
	bt.add_node("lower", lower)
	for i in LOWER_STATES.size():
		bt.connect_node("lower", i, "ts_" + LOWER_STATES[i])
	var upper := AnimationNodeTransition.new()
	upper.xfade_time = 0.12
	upper.input_count = UPPER_STATES.size()
	for i in UPPER_STATES.size():
		upper.set_input_name(i, UPPER_STATES[i])
		upper.set_input_reset(i, UPPER_STATES[i] == "punch")
		var an := AnimationNodeAnimation.new()
		an.animation = "aim_hold" if UPPER_STATES[i] == "none" else UPPER_STATES[i]
		bt.add_node("u_" + UPPER_STATES[i], an)
	bt.add_node("upper", upper)
	for i in UPPER_STATES.size():
		bt.connect_node("upper", i, "u_" + UPPER_STATES[i])
	# Upper body layer: replaces spine, arms and head when blend > 0.
	var split := AnimationNodeBlend2.new()
	split.filter_enabled = true
	var skel_path := String(model.get_path_to(skeleton))
	for b in UPPER_BONES:
		split.set_filter_path(NodePath("%s:%s" % [skel_path, b]), true)
	bt.add_node("split", split)
	bt.connect_node("split", 0, "lower")
	bt.connect_node("split", 1, "upper")
	bt.connect_node("output", 0, "split")
	tree.tree_root = bt
	# The body is moved by the controller, so the root bone's travel in
	# roll, mantle, climb and slide is taken out of the pose here.
	tree.root_motion_track = NodePath("%s:root" % skel_path)
	tree.active = true


func _build_ragdoll() -> void:
	physics = PhysicalBoneSimulator3D.new()
	skeleton.add_child(physics)
	var radii := {"hips": 0.15, "spine": 0.14, "chest_2": 0.17, "neck_2": 0.06, "head_2": 0.12,
		"upper_arm.L": 0.06, "forearm.L": 0.05, "hand.L": 0.05, "upper_arm.R": 0.06, "forearm.R": 0.05, "hand.R": 0.05,
		"thigh.L": 0.08, "shin.L": 0.06, "foot.L": 0.06, "thigh.R": 0.08, "shin.R": 0.06, "foot.R": 0.06}
	for b in radii:
		var idx := skeleton.find_bone(b)
		if idx < 0:
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + b
		pb.bone_name = b
		var length := 0.2
		for c in skeleton.get_bone_children(idx):
			length = skeleton.get_bone_rest(c).origin.length()
		if b.begins_with("head"):
			length = 0.25
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radii[b]
		cap.height = max(length, radii[b] * 2.0 + 0.01)
		cs.shape = cap
		pb.add_child(cs)
		# Bones point along +Y; centre the capsule along the bone.
		pb.body_offset = Transform3D(Basis(), Vector3(0, -length * 0.5, 0))
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE if not (b.begins_with("shin") or b.begins_with("forearm")) else PhysicalBone3D.JOINT_TYPE_HINGE
		pb.mass = 4.0 if b in ["hips", "chest_2", "spine"] else 1.5
		pb.collision_layer = 0
		pb.collision_mask = 1 | 16
		pb.friction = 0.8
		physics.add_child(pb)
	physics.active = false


## Called every frame with the officer's current state.
func update_from(o: Officer, delta: float) -> void:
	if downed:
		return
	var lower := _lower_state(o)
	var upper := _upper_state(o)
	if lower != _lower:
		tree.set("parameters/lower/transition_request", lower)
		_lower = lower
	if upper != _upper:
		tree.set("parameters/upper/transition_request", upper)
		_upper = upper
	tree.set("parameters/split/blend_amount", 0.0 if upper == "none" else 1.0)
	var hs := Vector2(o.velocity.x, o.velocity.z).length()
	tree.set("parameters/ts_run/scale", clampf(hs / RUN_CLIP_SPEED, 0.6, 1.7))
	tree.set("parameters/ts_walk/scale", 0.9 if o.turning and hs < 0.2 else clampf(hs / WALK_CLIP_SPEED, 0.5, 1.6))
	tree.set("parameters/ts_crouch_walk/scale", clampf(hs / CROUCH_CLIP_SPEED, 0.5, 1.8))
	tree.set("parameters/ts_crawl/scale", clampf(hs / CRAWL_CLIP_SPEED, 0.5, 2.0))
	tree.set("parameters/ts_roll/scale", Officer.ROLL_PLAYBACK)
	tree.set("parameters/ts_mantle/scale", Officer.MANTLE_PLAYBACK)
	tree.set("parameters/ts_climb/scale", Officer.CLIMB_PLAYBACK)
	tree.set("parameters/ts_slide/scale", 1.2)
	procedural.aim_yaw_offset = angle_difference(o.rotation.y, o.aim_yaw) if o.is_aiming() and o.state != Officer.S.PRONE else 0.0
	# Line the barrel up with the aim point, but never fold the body over
	# to aim at the ground at the officer's feet: the target's pitch from
	# the chest is held within 50 degrees, and points closer than 1 m are ignored.
	var chest_p := o.global_position + Vector3(0, 0.4 if o.state == Officer.S.PRONE else 1.35, 0)
	var to := o.aim_point - chest_p
	var horiz := Vector2(to.x, to.z).length()
	procedural.aim_active = o.is_aiming() and o.aim_point != Vector3.ZERO and horiz > 1.0
	to.y = clampf(to.y, -horiz * 1.19, horiz * 1.19)
	procedural.aim_target = chest_p + to
	if not procedural.have_slide:
		var sl := model.find_child("gun_slide", true, false) as Node3D
		if sl and sl.get_parent() is BoneAttachment3D:
			procedural.slide_rel = (sl.get_parent() as Node3D).global_transform.affine_inverse() * sl.global_transform
			procedural.have_slide = true
	procedural.feet_enabled = o.state in [Officer.S.MOVE, Officer.S.CROUCH, Officer.S.COVER]
	procedural.hand_lock = o.is_aiming() and not o.is_reloading()
	procedural.recoil = o.recoil
	procedural.reload_k = 1.0 - o.reload_t / Officer.RELOAD_TIME if o.is_reloading() else 0.0
	procedural.ground_y = o.global_position.y
	# Climbing: hands on the real ledge until the body is up over it.
	if o.state == Officer.S.CLIMB:
		var fwd := Vector3(sin(o._move_yaw), 0, cos(o._move_yaw))
		var k := clampf(o.state_t * Officer.CLIMB_PLAYBACK / OfficerClips.move_length("climb"), 0.0, 1.0)
		var ledge: Vector3 = o._ledge
		if ledge == Vector3.ZERO or ledge.distance_to(o._move_start) > 3.5:
			ledge = o._move_start + fwd * 0.45 + Vector3(0, o._move_rise, 0)
		procedural.ledge_point = ledge
		procedural.ledge_right = fwd.cross(Vector3.UP).normalized()
		procedural.ledge_weight = 1.0 - smoothstep(0.7, 0.95, k)
	else:
		procedural.ledge_weight = 0.0
	if _hit_t > 0.0:
		_hit_t -= delta
		physics.influence = clampf(_hit_t / 0.5, 0.0, 1.0) * 0.55
		if _hit_t <= 0.0:
			physics.physical_bones_stop_simulation()
			physics.active = false


func _lower_state(o: Officer) -> String:
	var hs := Vector2(o.velocity.x, o.velocity.z).length()
	match o.state:
		Officer.S.ROLL: return "roll"
		Officer.S.SLIDE: return "slide"
		Officer.S.VAULT: return "mantle"
		Officer.S.CLIMB: return "climb"
		Officer.S.KICK: return "kick"
		Officer.S.AIR: return "jump" if o.velocity.y > 0.5 else "fall"
		Officer.S.PRONE: return "crawl" if hs > 0.1 else "prone_idle"
		Officer.S.CROUCH: return "crouch_walk" if hs > 0.2 else "crouch_idle"
		Officer.S.DOWNED: return "prone_idle"
		Officer.S.COVER:
			if o.is_aiming():
				return "walk" if hs > 0.2 else "idle"
			if o._cover_low:
				return "crouch_walk" if hs > 0.2 else "crouch_idle"
			return "crouch_walk" if hs > 0.2 else "cover_idle"
	if o.is_reviving():
		return "crouch_idle"
	if hs < 0.2:
		return "walk" if o.turning else "idle"
	return "walk" if hs < 2.2 else "run"


func _upper_state(o: Officer) -> String:
	if o.state in [Officer.S.ROLL, Officer.S.SLIDE, Officer.S.VAULT, Officer.S.CLIMB, Officer.S.PRONE, Officer.S.KICK, Officer.S.DOWNED] or o.is_reviving():
		return "none"
	if o.state == Officer.S.COVER and not o.is_aiming() and o.blind_t <= 0.0:
		return "none"
	if o.punch_t > 0.0:
		return "punch"
	if o.is_aiming() or o.blind_t > 0.0:
		return "aim_hold"
	if o.holstered:
		return "none"
	# Gun drawn but not aimed: low ready (and while reloading); sprinting
	# carries it down at the side.
	if o.is_reloading() or (o.buttons & PlayerInput.SPRINT) == 0:
		return "ready_hold"
	return "none"


## Partial ragdoll: the upper body takes the hit, then animation wins back.
func hit_reaction(world_dir: Vector3, strength := 6.0) -> void:
	if downed:
		return
	physics.active = true
	physics.physical_bones_start_simulation(["spine", "chest_2", "neck_2", "head_2", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"])
	physics.influence = 0.55
	_hit_t = 0.5
	var chest := physics.get_node_or_null("PB_chest_2") as PhysicalBone3D
	if chest:
		chest.apply_central_impulse(world_dir.normalized() * strength)


## Full ragdoll when downed; standing up again blends back to animation.
func set_downed(on: bool, push := Vector3.ZERO) -> void:
	downed = on
	physics.active = on
	if on:
		physics.influence = 1.0
		physics.physical_bones_start_simulation()
		var chest := physics.get_node_or_null("PB_chest_2") as PhysicalBone3D
		if chest:
			chest.apply_central_impulse(push)
	else:
		physics.physical_bones_stop_simulation()
		physics.influence = 0.0
