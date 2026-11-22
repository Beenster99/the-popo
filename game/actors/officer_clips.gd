class_name OfficerClips
extends RefCounted
## The officer's animation library: the hand-keyed clips from officer.glb,
## with the mocap clips (officer_mocap.glb, exported from the capture work on
## beenster's PC) replacing the same moves. Mocap is the base, hand keys fill
## the moves mocap does not have yet. Also samples the root bone's travel so
## the controller can move the body along a move's path the same way on
## every machine (root motion without depending on playback).

const MOCAP_PATH := "res://assets/models/characters/mocap/officer_mocap.glb"
const ROOT_MOTION_CLIPS := ["roll", "mantle", "climb", "slide"]

static var _library: AnimationLibrary
static var _curves := {}       # clip -> {length, points: PackedVector3Array at 30 Hz (model space, metres)}
static var mocap_clips: Array = []


## Returns the merged library (cached). skeleton_path is the track prefix.
static func library(template: AnimationPlayer, skeleton: Skeleton3D) -> AnimationLibrary:
	if _library:
		return _library
	var base: AnimationLibrary = template.get_animation_library("")
	_library = AnimationLibrary.new()
	for n in base.get_animation_list():
		_library.add_animation(n, base.get_animation(n))
	if ResourceLoader.exists(MOCAP_PATH):
		var moc: Node = (load(MOCAP_PATH) as PackedScene).instantiate()
		var ap: AnimationPlayer = moc.find_children("*", "AnimationPlayer", true, false)[0]
		for n in ap.get_animation_list():
			var a: Animation = ap.get_animation(n).duplicate(true)
			# Drop tracks for bones our model does not have (IK controls, gun, flash).
			for i in range(a.get_track_count() - 1, -1, -1):
				var bone := String(a.track_get_path(i).get_concatenated_subnames())
				if skeleton.find_bone(bone) < 0:
					a.remove_track(i)
			if _library.has_animation(n):
				_library.add_animation("hk_" + n, _library.get_animation(n))
				_library.remove_animation(n)
			_library.add_animation(n, a)
			mocap_clips.append(n)
		moc.free()
		# The mocap aim holds a steady sight picture from about 2.0 s to 4.0 s:
		# that slice becomes the upper-body aim loop.
		if _library.has_animation("aim"):
			if _library.has_animation("aim_hold"):
				_library.add_animation("hk_aim_hold", _library.get_animation("aim_hold"))
				_library.remove_animation("aim_hold")
			_library.add_animation("aim_hold", slice(_library.get_animation("aim"), 2.05, 3.95))
	return _library


## A looping copy of part of a clip, keys shifted to start at zero.
static func slice(src: Animation, t0: float, t1: float) -> Animation:
	var a := Animation.new()
	a.length = t1 - t0
	a.loop_mode = Animation.LOOP_LINEAR
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		if ty not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var j := a.add_track(ty)
		a.track_set_path(j, src.track_get_path(i))
		var step := 1.0 / 30.0
		var t := t0
		while t <= t1 + 0.0001:
			var tt := minf(t, t1)
			match ty:
				Animation.TYPE_POSITION_3D: a.position_track_insert_key(j, tt - t0, src.position_track_interpolate(i, tt))
				Animation.TYPE_ROTATION_3D: a.rotation_track_insert_key(j, tt - t0, src.rotation_track_interpolate(i, tt))
				Animation.TYPE_SCALE_3D: a.scale_track_insert_key(j, tt - t0, src.scale_track_interpolate(i, tt))
			t += step
	return a


## Root travel of a clip at time t (seconds), in the model's space, from the
## start of the clip. Needs library() to have run once.
static func root_offset(clip: String, t: float) -> Vector3:
	if not _curves.has(clip):
		_sample(clip)
	var c: Dictionary = _curves[clip]
	var pts: PackedVector3Array = c.points
	if pts.is_empty():
		return Vector3.ZERO
	var f := clampf(t * 30.0, 0.0, pts.size() - 1.001)
	var i := int(f)
	return pts[i].lerp(pts[min(i + 1, pts.size() - 1)], f - i)


static func clip_length(clip: String) -> float:
	if not _curves.has(clip):
		_sample(clip)
	return _curves[clip].length


static func _sample(clip: String) -> void:
	var pts := PackedVector3Array()
	var length := 1.0
	if _library == null:
		_ensure_loaded()
	if _library and _library.has_animation(clip):
		var a := _library.get_animation(clip)
		length = a.length
		var tr := -1
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D and String(a.track_get_path(i).get_concatenated_subnames()) == "root":
				tr = i
		if tr >= 0:
			var p0 := a.position_track_interpolate(tr, 0.0)
			# The glTF rig's skeleton is Y up, character facing +Z; the root
			# bone has an identity rest, so track values are model space.
			for k in int(length * 30.0) + 1:
				var p := a.position_track_interpolate(tr, k / 30.0) - p0
				pts.append(Vector3(p.x, 0.0, p.z))
	_curves[clip] = {"length": length, "points": pts}


## Loads the model once without a scene, for headless hosts and tests.
static func _ensure_loaded() -> void:
	var m: Node = OfficerRig.MODEL.instantiate()
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	library(ap, sk)
	m.free()
