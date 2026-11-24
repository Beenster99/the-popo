class_name SkidMarks
extends MultiMeshInstance3D
## v0.12.0 (beenster: "the cars need to leave skid marks"): dark rubber
## strips on the road wherever a tyre slides: locked under hard braking,
## the rear wheels on the handbrake, drifts, wheelspin and sideways skids
## after a crash.
##
## One of these per world (for_tree), drawing every car's marks as flat
## quads in one MultiMesh ring buffer: the oldest strip is reused when it
## runs out, so marks build up through a shift and the earliest fade away
## first. Each wheel lays a strip from where it last laid one to where it is
## now, so the marks follow the car's real path.
##
## Cars report each wheel with wheel(): the simulating machine passes its
## tyre physics (Car._integrate_forces), and a friend's machine, where the
## car is only following the host, estimates the slide from how the car
## moved (Car._estimate_skids).

## v0.13.2 (beenster: "remove skid marks after a period to manage fps"):
## far fewer kept, and each fades away LIFETIME seconds after it was laid
## instead of lasting the whole shift.
const MAX_STRIPS := 1500
const LIFETIME := 40.0        # s until a mark is gone
const FADE_TIME := 12.0       # s of fading at the end of that
const TICK := 0.25            # s between fade updates
const WIDTH := 0.2            # m, a tyre's tread
const MIN_STEP := 0.22        # m between strips (shorter would waste them)
const MAX_STEP := 2.5         # m: further means the wheel jumped; start a new mark
const LIFT := 0.012           # m above the road, so it never fights it
const FADE_STRIPS := 600      # the oldest this many fade out before reuse
const FADE_STEPS := 8
const NAME := "SkidMarks"

var _next := 0
var _count := 0
## wheel key -> last point a strip ended at (world), or absent when the tyre is gripping.
var _last := {}
var _alpha := PackedFloat32Array()
var _born := PackedFloat32Array()
var _clock := 0.0
var _tick_t := 0.0
## The oldest strip still showing (the ring's tail).
var _tail := 0


## The world's skid marks (made on first use).
static func for_tree(tree: SceneTree) -> SkidMarks:
	if tree == null:
		return null
	# (The test runner has no current scene: the root then.)
	var home: Node = tree.current_scene if tree.current_scene else tree.root
	var s := home.get_node_or_null(NAME) as SkidMarks
	if s == null:
		# (Made once even when several cars ask before it enters the tree.)
		var pending: Variant = _pending.get(home.get_instance_id())
		if pending != null and is_instance_valid(pending):
			return pending
		s = SkidMarks.new()
		s.name = NAME
		_pending[home.get_instance_id()] = s
		home.add_child.call_deferred(s)
	return s


static var _pending := {}


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.03)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	plane.material = mat
	mm.mesh = plane
	mm.instance_count = MAX_STRIPS
	mm.visible_instance_count = 0
	# Marks are laid all over the city: no culling box to keep recomputing.
	mm.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))
	multimesh = mm
	_alpha.resize(MAX_STRIPS)
	_born.resize(MAX_STRIPS)


## One wheel this physics tick. key: unique per wheel (car id and wheel
## index); ground: where the tyre touches the road (world); normal: the
## road's up; slide: 0 gripping .. 1 sliding flat out.
func wheel(key: int, ground: Vector3, normal: Vector3, slide: float) -> void:
	if slide < 0.05:
		_last.erase(key)
		return
	var from: Variant = _last.get(key)
	if from == null:
		_last[key] = ground
		return
	var a := from as Vector3
	var d := ground.distance_to(a)
	if d < MIN_STEP:
		return
	if d > MAX_STEP:
		_last[key] = ground
		return
	_lay(a, ground, normal, clampf(0.3 + slide * 0.45, 0.0, 0.75))
	_last[key] = ground


## The tyre left the road (or the car is gone): the next mark starts fresh.
func lift(key: int) -> void:
	_last.erase(key)


func strip_count() -> int:
	return _count


## Every strip laid since this world started (the ring reuses the oldest).
var laid := 0


## Transform of one strip from a to b: a flat quad WIDTH wide, lying on the
## road (normal up), slightly longer than the gap so strips join up.
static func strip_transform(a: Vector3, b: Vector3, normal: Vector3) -> Transform3D:
	var n := normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var along := b - a
	along -= n * along.dot(n)
	var length := along.length()
	var fwd := along / length if length > 0.0001 else Vector3.FORWARD
	var side := n.cross(fwd).normalized()
	var basis := Basis(side * WIDTH, n, fwd * (length + 0.04))
	return Transform3D(basis, (a + b) * 0.5 + n * LIFT)


func _lay(a: Vector3, b: Vector3, normal: Vector3, alpha: float) -> void:
	var mm := multimesh
	var i := _next
	mm.set_instance_transform(i, strip_transform(a, b, normal))
	_alpha[i] = alpha
	_born[i] = _clock
	mm.set_instance_color(i, Color(1, 1, 1, alpha))
	laid += 1
	_next = (_next + 1) % MAX_STRIPS
	if _count == MAX_STRIPS:
		_tail = _next     # the ring is full: the oldest was just written over
	else:
		_count += 1
	# Draw up to the furthest slot ever used; spent slots are collapsed.
	mm.visible_instance_count = maxi(mm.visible_instance_count, mini(laid, MAX_STRIPS))


## Marks fade out over their last FADE_TIME seconds and are then gone.
func _process(delta: float) -> void:
	_clock += delta
	_tick_t -= delta
	if _tick_t > 0.0 or _count == 0:
		return
	_tick_t = TICK
	var mm := multimesh
	var fade_from := LIFETIME - FADE_TIME
	var k := 0
	while k < _count:
		var j := (_tail + k) % MAX_STRIPS
		var age := _clock - _born[j]
		if age < fade_from:
			break     # strips are in age order: the rest are younger
		if age >= LIFETIME and k == 0:
			mm.set_instance_transform(j, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			_tail = (_tail + 1) % MAX_STRIPS
			_count -= 1
			continue
		var f := clampf(1.0 - (age - fade_from) / FADE_TIME, 0.0, 1.0)
		mm.set_instance_color(j, Color(1, 1, 1, _alpha[j] * f))
		k += 1
