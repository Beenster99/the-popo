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
const LOWER_STATES := ["idle", "walk", "walk_ready", "run", "crouch_idle", "crouch_walk", "prone_idle", "crawl", "cover_idle",
	"peek", "slide", "roll", "mantle", "climb", "jump", "fall", "kick", "cover_low_idle", "limp", "sit", "kneel"]
const UPPER_STATES := ["none", "aim_hold", "ready_hold", "punch", "reload", "holster", "draw", "drive", "hands_up", "cuffed"]
var RUN_CLIP_SPEED := 3.3    # m/s of the run cycle (2.27 for the mocap run)
var WALK_CLIP_SPEED := 1.4   # m/s of the walk cycle (0.87 for the mocap walk)
## The tactical walk (gun out or aiming): four 100STYLE "SWAT" mocap loops in
## a 2D blend by the direction of travel against the facing. Their speeds
## (m/s, from tools/blender/mocap/walks.json) set the playback rate.
const TAC_WALKS := {"walk_ready": Vector2(0, 1), "walk_back": Vector2(0, -1), "walk_left": Vector2(-1, 0), "walk_right": Vector2(1, 0)}
const TAC_FWD_SPEED := 1.09
const TAC_BACK_SPEED := 0.54
const TAC_SIDE_SPEED := 0.58
## Upper-body crossfade time (seconds), see _build_tree.
const UPPER_BLEND := 0.2
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
var _spare_mag: Node3D
var _hit_t := 0.0
## Seconds since the body went down: the joints start stiff (a person
## topples rather than folds) and go slack over LIMP_TIME.
var _limp_t := 99.0
## Downed and dragged by the collar: the point the chest is pulled to.
var drag_point := Vector3.INF
var _smear_at := Vector3.INF
const LIMP_TIME := 1.2
var downed := false
var _aim_smooth := Vector3.INF
var _upper_t := 0.0          # seconds in the current upper-body state
## The mocap tactical walks are loaded (else the plain walk stands in).
var _tac_ok := false
var _tac_d := Vector2(0, 1)


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
	for n in ["idle", "walk", "walk_ready", "walk_back", "walk_left", "walk_right", "run", "crouch_idle", "crouch_walk", "prone_idle", "crawl", "cover_idle", "cover_low_idle", "fall", "aim_hold", "ready_hold", "peek", "limp", "sit", "drive", "kneel", "hands_up", "cuffed"]:
		if lib.has_animation(n):
			lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if "run" in OfficerClips.mocap_clips:
		RUN_CLIP_SPEED = 2.27
	if "walk" in OfficerClips.mocap_clips:
		WALK_CLIP_SPEED = 0.87
	_tac_ok = lib.has_animation("walk_ready")
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
		var an: AnimationNode = _tac_blend() if LOWER_STATES[i] == "walk_ready" and _tac_ok else AnimationNodeAnimation.new()
		if an is AnimationNodeAnimation:
			(an as AnimationNodeAnimation).animation = LOWER_STATES[i] if LOWER_STATES[i] != "walk_ready" or _tac_ok else "walk"
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
		upper.set_input_reset(i, UPPER_STATES[i] in ["punch", "reload", "holster", "draw"])
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


## The tactical walk: forward, back and sidestep loops blended by direction
## (x: right +, y: forward +).
func _tac_blend() -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	bs.sync = true
	for n in TAC_WALKS:
		var an := AnimationNodeAnimation.new()
		an.animation = n
		bs.add_blend_point(an, TAC_WALKS[n], -1, StringName(n))
	return bs


## Travel direction against the facing (x: right +, y: forward +), and the
## speed the blended tactical clip covers at normal playback.
static func tac_dir(o: Node3D, v: Vector3) -> Vector2:
	var local := o.global_transform.basis.inverse() * Vector3(v.x, 0, v.z)
	var d := Vector2(-local.x, local.z)
	return d.normalized() if d.length() > 0.05 else Vector2(0, 1)


static func tac_clip_speed(d: Vector2) -> float:
	var fwd := TAC_FWD_SPEED if d.y >= 0.0 else TAC_BACK_SPEED
	var w := absf(d.x) + absf(d.y)
	return (absf(d.y) * fwd + absf(d.x) * TAC_SIDE_SPEED) / maxf(w, 0.001)


# Every physics tick, so the pull holds even when frames are slow.
func _physics_process(_delta: float) -> void:
	if not downed:
		return
	var o := _owner_officer()
	var d: Officer = o._dragger() if o else null
	# Being dragged: the collar is in the dragger's hand, just behind them.
	drag_point = Vector3.INF if d == null else d.global_position + (o.global_position - d.global_position).normalized() * 0.35 + Vector3(0, 0.6, 0)
	_drag_pull()
	# A smear of blood along the ground behind a dragged body.
	var hips := bone_body("hips")
	if d and hips and Gore.level() > 0:
		if _smear_at == Vector3.INF or hips.global_position.distance_to(_smear_at) > 0.35:
			_smear_at = hips.global_position
			Gore.splat(o.get_parent(), Vector3(_smear_at.x, o.global_position.y + 0.01, _smear_at.z), Vector3.UP, 0.35 + 0.1 * Gore.level(), true)
	elif d == null:
		_smear_at = Vector3.INF


func _owner_officer() -> Officer:
	var n := get_parent()
	while n and not n is Officer:
		n = n.get_parent()
	return n as Officer


func _drag_pull() -> void:
	if not downed or drag_point == Vector3.INF:
		return
	var chest := bone_body("chest_2")
	var neck := bone_body("neck_2")
	if chest == null:
		return
	# A body that has come to rest is asleep: wake it all, or it won't move.
	for c in physics.get_children():
		if c is PhysicalBone3D:
			PhysicsServer3D.body_set_state((c as PhysicalBone3D).get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
	var grip: Vector3 = neck.global_position if neck else chest.global_position
	var want := ((drag_point - grip) * 8.0).limit_length(5.0)
	chest.linear_velocity = chest.linear_velocity.lerp(want, 0.5)
	if neck:
		neck.linear_velocity = neck.linear_velocity.lerp(want, 0.5)


func _go_limp(delta: float) -> void:
	if not downed or _limp_t > LIMP_TIME:
		return
	_limp_t += delta
	var damp := lerpf(9.0, 1.5, clampf(_limp_t / LIMP_TIME, 0.0, 1.0))
	for c in physics.get_children():
		if c is PhysicalBone3D:
			(c as PhysicalBone3D).angular_damp = damp


## Ragdoll joint limits in degrees: cone joints (swing, twist), hinges
## (lower, upper).
const JOINT_LIMITS := {"hips": Vector2(10, 5), "spine": Vector2(20, 10), "chest_2": Vector2(20, 10),
	"neck_2": Vector2(30, 25), "head_2": Vector2(25, 20), "upper_arm": Vector2(75, 40), "hand": Vector2(40, 20),
	"thigh": Vector2(55, 15), "foot": Vector2(25, 10), "shin": Vector2(-120, 0), "forearm": Vector2(-130, 0)}


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
		pb.name = ("PB_" + b).validate_node_name()
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
		# Bones point along +Y: the body sits halfway along the bone and the
		# joint at the bone's root (relative to the body). Joints twist about
		# their X axis and hinges turn about Z, so both are turned to the bone.
		pb.body_offset = Transform3D(Basis(), Vector3(0, length * 0.5, 0))
		var hinge: bool = b.begins_with("shin") or b.begins_with("forearm")
		var jb := Basis(Vector3.UP, PI * 0.5) if hinge else Basis(Vector3.BACK, PI * 0.5)
		pb.joint_offset = Transform3D(jb, Vector3(0, -length * 0.5, 0))
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE if not (b.begins_with("shin") or b.begins_with("forearm")) else PhysicalBone3D.JOINT_TYPE_HINGE
		# Joints that only bend as far as a body does, so it can't fold
		# into a pile (beenster: "Players collapse in a heap").
		var lim: Vector2 = JOINT_LIMITS.get(b.trim_suffix(".L").trim_suffix(".R"), Vector2(40, 20))
		if pb.joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
			pb.set("joint_constraints/swing_span", lim.x)
			pb.set("joint_constraints/twist_span", lim.y)
		else:
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_lower", lim.x)
			pb.set("joint_constraints/angular_limit_upper", lim.y)
		pb.mass = 4.0 if b in ["hips", "chest_2", "spine"] else 1.5
		pb.collision_layer = 0
		pb.collision_mask = 1 | 4 | 16
		pb.friction = 0.8
		physics.add_child(pb)
	physics.active = false


## The ragdoll body of a skeleton bone ("thigh.L"), or null. Node names
## can't hold dots, so they are swapped for underscores.
func bone_body(bone: String) -> PhysicalBone3D:
	return physics.get_node_or_null(("PB_" + bone).validate_node_name()) as PhysicalBone3D


## A body on the floor can be shot (it jerks and bleeds): bullets look for
## Gore.RAGDOLL_LAYER. Standing, the capsule takes the hits instead.
func _set_ragdoll_layer(on: bool) -> void:
	for c in physics.get_children():
		if c is PhysicalBone3D:
			(c as PhysicalBone3D).collision_layer = Gore.RAGDOLL_LAYER if on else 0


## Called every frame with the officer's current state.
func update_from(o: Officer, delta: float) -> void:
	if downed:
		_go_limp(delta)
		return
	var lower := _lower_state(o)
	var upper := _upper_state(o)
	if lower != _lower:
		tree.set("parameters/lower/transition_request", lower)
		_lower = lower
	_upper_t += delta
	if upper != _upper:
		tree.set("parameters/upper/transition_request", upper)
		_upper = upper
		_upper_t = 0.0
	tree.set("parameters/split/blend_amount", 0.0 if upper == "none" else 1.0)
	var hs := Vector2(o.velocity.x, o.velocity.z).length()
	tree.set("parameters/ts_run/scale", clampf(hs / RUN_CLIP_SPEED, 0.6, 1.7))
	tree.set("parameters/ts_limp/scale", clampf(hs / WALK_CLIP_SPEED, 0.5, 1.6))
	tree.set("parameters/ts_walk/scale", 0.9 if o.turning and hs < 0.2 else clampf(hs / WALK_CLIP_SPEED, 0.5, 1.8))
	if _tac_ok:
		var d := tac_dir(o, o.velocity) if hs > 0.2 else Vector2(0, 1)
		_tac_d = _tac_d.lerp(d, 1.0 - exp(-10.0 * delta))
		tree.set("parameters/a_walk_ready/blend_position", _tac_d)
		var sc := 0.8 if hs < 0.2 else clampf(hs / tac_clip_speed(_tac_d), 0.5, 1.8)
		tree.set("parameters/ts_walk_ready/scale", sc)
	else:
		tree.set("parameters/ts_walk_ready/scale", 0.9 if o.turning and hs < 0.2 else clampf(hs / WALK_CLIP_SPEED, 0.5, 1.8))
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
	var chest_p := o.global_position + Vector3(0, 0.4 if o.state == Officer.S.PRONE else (0.95 if o.state == Officer.S.VEHICLE else 1.35), 0)
	var to := o.aim_point - chest_p
	var horiz := Vector2(to.x, to.z).length()
	procedural.aim_active = o.is_aiming() and o.aim_point != Vector3.ZERO and horiz > 1.0
	to.y = clampf(to.y, -horiz * 1.19, horiz * 1.19)
	if o.injuries & Officer.ARM:
		# A wounded arm can't hold the gun still.
		var tt := Time.get_ticks_msec() / 1000.0
		to += Vector3(sin(tt * 7.3) + sin(tt * 13.1) * 0.4, sin(tt * 5.1) * 0.6, cos(tt * 6.7)) * 0.035 * maxf(horiz, 1.0)
	# Smoothed, so the mouse sweeping over edges (the aim point jumping
	# between a near wall and the ground behind it) does not jolt the arms.
	var want_aim := chest_p + to
	if not procedural.aim_active or _aim_smooth == Vector3.INF:
		_aim_smooth = want_aim
	else:
		_aim_smooth = _aim_smooth.lerp(want_aim, 1.0 - exp(-12.0 * delta))
	procedural.aim_target = _aim_smooth
	if not procedural.aim_active:
		_aim_smooth = Vector3.INF
	if not procedural.have_slide:
		var sl := model.find_child("gun_slide", true, false) as Node3D
		if sl and sl.get_parent() is BoneAttachment3D:
			procedural.slide_rel = (sl.get_parent() as Node3D).global_transform.affine_inverse() * sl.global_transform
			procedural.have_slide = true
	# Peeking round a corner: lean the body out over planted feet.
	var lean_to := o.peek_dir()
	procedural.lean = procedural.lean.lerp(lean_to, 1.0 - exp(-10.0 * delta))
	procedural.feet_enabled = o.state in [Officer.S.MOVE, Officer.S.CROUCH, Officer.S.COVER]
	# The support hand locks onto the grip once the aim pose has fully blended
	# in (after a reload or draw too), so it locks where the clip puts it.
	procedural.hand_lock = o.is_aiming() and not o.is_reloading() and upper == "aim_hold" and _upper_t > UPPER_BLEND
	procedural.recoil = o.recoil
	# The reload is a hand-keyed clip now; the old procedural hand is off.
	procedural.reload_k = 0.0
	_update_spare_mag(o)
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
	# Dragging: the left hand reaches back into the teammate's collar.
	var dragged := o.drag_target()
	var neck: PhysicalBone3D = dragged.rig.bone_body("neck_2") if dragged and dragged.rig else null
	procedural.collar_weight = move_toward(procedural.collar_weight, 1.0 if neck else 0.0, delta * 5.0)
	if neck:
		procedural.collar_point = neck.global_position
	_go_limp(delta)
	if _hit_t > 0.0:
		_hit_t -= delta
		physics.influence = clampf(_hit_t / 0.5, 0.0, 1.0) * 0.55
		if _hit_t <= 0.0:
			physics.physical_bones_stop_simulation()
			physics.active = false


func _lower_state(o: Officer) -> String:
	var hs := Vector2(o.velocity.x, o.velocity.z).length()
	if o.state in [Officer.S.MOVE, Officer.S.CROUCH] and o.drag_target():
		return "crouch_walk" if hs > 0.3 else "crouch_idle"   # bent over, backing off
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
		Officer.S.VEHICLE: return "sit"
		Officer.S.COVER:
			if o.is_aiming():
				return "idle"   # feet planted; the body leans out (procedural)
			if o._cover_low:
				return "crouch_walk" if hs > 0.2 else "cover_low_idle"
			return "crouch_walk" if hs > 0.2 else "cover_idle"
	if o.is_reviving():
		return "crouch_idle"
	# Gun out or aiming: the tactical walk (knees soft, weight low, and it
	# backs off and sidesteps facing the aim). Holstered: a relaxed walk.
	var tac := o.is_aiming() or not o.holstered
	if hs < 0.2:
		return ("walk_ready" if tac else "walk") if o.turning else "idle"
	if o.injuries & Officer.LEG:
		return "limp"
	if hs < 2.2:
		return "walk_ready" if tac else "walk"
	return "run"


func _upper_state(o: Officer) -> String:
	if o.state in [Officer.S.ROLL, Officer.S.SLIDE, Officer.S.VAULT, Officer.S.CLIMB, Officer.S.PRONE, Officer.S.KICK, Officer.S.DOWNED] or o.is_reviving():
		return "none"
	if o.state == Officer.S.VEHICLE and o.seat == 0:
		return "drive"
	if o.punch_t > 0.0 or o.throw_t > 0.0:
		return "punch"   # the throwing arm comes over the same way
	if o.holster_t > 0.0 and not o.is_aiming():
		return "draw" if o.drawing else "holster"
	if o.is_reloading() and not o.holstered:
		return "reload"
	if o.state == Officer.S.COVER and not o.is_aiming() and o.blind_t <= 0.0:
		return "none"
	if o.is_aiming() or o.blind_t > 0.0:
		return "aim_hold"
	if o.holstered:
		return "none"
	# Gun drawn but not aimed: low ready; sprinting carries it down at the side.
	if (o.buttons & PlayerInput.SPRINT) == 0:
		return "ready_hold"
	return "none"


## Drives the rig straight from named states, for characters that are not
## officers (suspects): lower and upper clip names, ground speed, and an aim
## point while shooting (Vector3.ZERO for none).
func update_pose(lower: String, upper: String, hs: float, delta: float, aim_at := Vector3.ZERO) -> void:
	if downed:
		return
	if lower != _lower:
		tree.set("parameters/lower/transition_request", lower)
		_lower = lower
	if upper != _upper:
		tree.set("parameters/upper/transition_request", upper)
		_upper = upper
	tree.set("parameters/split/blend_amount", 0.0 if upper == "none" else 1.0)
	tree.set("parameters/ts_run/scale", clampf(hs / RUN_CLIP_SPEED, 0.6, 1.7))
	tree.set("parameters/ts_walk/scale", clampf(hs / WALK_CLIP_SPEED, 0.5, 1.8))
	tree.set("parameters/ts_crouch_walk/scale", clampf(hs / CROUCH_CLIP_SPEED, 0.5, 1.8))
	var root := get_parent() as Node3D
	procedural.aim_active = aim_at != Vector3.ZERO and root != null
	procedural.aim_yaw_offset = 0.0
	if procedural.aim_active:
		procedural.aim_target = aim_at
		if not procedural.have_slide:
			var sl := model.find_child("gun_slide", true, false) as Node3D
			if sl and sl.get_parent() is BoneAttachment3D:
				procedural.slide_rel = (sl.get_parent() as Node3D).global_transform.affine_inverse() * sl.global_transform
				procedural.have_slide = true
	procedural.feet_enabled = lower in ["idle", "walk", "walk_ready", "run", "crouch_idle", "crouch_walk"]
	procedural.hand_lock = false
	procedural.recoil = 0.0
	procedural.reload_k = 0.0
	procedural.lean = Vector3.ZERO
	if root:
		procedural.ground_y = root.global_position.y
	_go_limp(delta)
	if _hit_t > 0.0:
		_hit_t -= delta
		physics.influence = clampf(_hit_t / 0.5, 0.0, 1.0) * 0.55
		if _hit_t <= 0.0:
			physics.physical_bones_stop_simulation()
			physics.active = false


## The fresh magazine shows in the left hand from the belt pouch until it is
## seated in the grip (the middle of the reload clip).
func _update_spare_mag(o: Officer) -> void:
	if _spare_mag == null:
		_spare_mag = model.find_child("spare_mag", true, false) as Node3D
		if _spare_mag == null:
			return
	var k := 1.0 - o.reload_t / o.reload_time() if o.is_reloading() else 0.0
	_spare_mag.visible = k > 0.33 and k < 0.59


## Partial ragdoll: the upper body takes the hit, then animation wins back.
func hit_reaction(world_dir: Vector3, strength := 6.0) -> void:
	if downed:
		return
	physics.active = true
	physics.physical_bones_start_simulation(["spine", "chest_2", "neck_2", "head_2", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"])
	physics.influence = 0.55
	_hit_t = 0.5
	var chest := bone_body("chest_2")
	if chest:
		chest.apply_central_impulse(world_dir.normalized() * strength)


## Full ragdoll when downed; standing up again blends back to animation.
func set_downed(on: bool, push := Vector3.ZERO, carry := Vector3.ZERO) -> void:
	downed = on
	physics.active = on
	_set_ragdoll_layer(on)
	if on:
		physics.influence = 1.0
		physics.physical_bones_start_simulation()
		_limp_t = 0.0
		# The whole body keeps the way it was moving, so a runner falls
		# forward and a body goes down rather than dropping on the spot.
		for c in physics.get_children():
			if c is PhysicalBone3D:
				(c as PhysicalBone3D).linear_velocity = carry
		var chest := bone_body("chest_2")
		if chest:
			chest.apply_central_impulse(push)
			# The legs go too, so a body is thrown rather than folding up.
			for b in ["hips", "thigh.L", "thigh.R"]:
				var pb := bone_body(b)
				if pb:
					pb.apply_central_impulse(push * 0.5)
		Gore.downed(self)
	else:
		physics.physical_bones_stop_simulation()
		physics.influence = 0.0
