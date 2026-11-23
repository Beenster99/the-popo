class_name PedSystem
extends Node
## Wave 2, Phase 2.3: people out walking. The host keeps a couple of dozen
## civilians on the pavements round the officers: each walks a loop round
## its block, a little way in from the kerb. They're Suspects with the
## civilian flag (so they sync, can be hurt, run over, made to put their
## hands up, cuffed), and they react to trouble (Suspect.on_alarm): run
## from gunfire, blasts and falling buildings, crouch and cover their heads,
## then carry on when it's been quiet a while.
##
## People far from every officer are taken away and new ones appear in the
## blocks officers are near, out of their way.

const TARGET := 22
const SPAWN_R := 85.0       # m: blocks this close to an officer get people
const DESPAWN_R := 130.0
const MIN_SPAWN_GAP := 22.0 # m: never pops up right next to an officer

static var current: PedSystem

var gen: CityGenerator
var dispatch: Dispatcher
var nav: CityNav
var peds: Array = []
var target := TARGET
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	current = self
	_rng.seed = 4711


func _exit_tree() -> void:
	if current == self:
		current = null


## A walk round the block nearest p: the lot's edge, 2.4 m in from the
## kerb, a point every 8 m or so, either way round.
static func route_near(g: CityGenerator, p: Vector3, rng: RandomNumberGenerator) -> Array:
	var c := CityGenerator.block_at(p)
	if c.x < 0:
		c = Vector2i(clampi(int(p.x / CityGenerator.PITCH), 0, CityGenerator.GRID - 1), clampi(int(p.z / CityGenerator.PITCH), 0, CityGenerator.GRID - 1))
	return route_for(g, g.block_index(c.x, c.y), rng)


static func route_for(g: CityGenerator, k: int, rng: RandomNumberGenerator) -> Array:
	var r: Rect2 = (g.blocks[k].rect as Rect2).grow(-2.4)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	if rng.randf() < 0.5:
		corners.reverse()
	var out: Array = []
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var n := maxi(1, int(a.distance_to(b) / 8.0))
		for s in n:
			var q := a.lerp(b, float(s) / n)
			out.append(Vector3(q.x, BlockGenerator.BASE_Y, q.y))
	return out


## Someone who got out of a car joins the people out walking.
func adopt(s: Suspect) -> void:
	if not peds.has(s):
		peds.append(s)


func _physics_process(delta: float) -> void:
	if not Net.is_host() or gen == null or dispatch == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var eyes: Array = []
	for o in get_tree().get_nodes_in_group("officers"):
		eyes.append((o as Node3D).global_position)
	if eyes.is_empty():
		return
	for s in peds.duplicate():
		if not is_instance_valid(s):
			peds.erase(s)
			continue
		var ps := s as Suspect
		if not ps.civilian or ps.state in [Suspect.S.CUFFED, Suspect.S.IN_CAR, Suspect.S.BOOKED]:
			peds.erase(s)   # in custody now: the call system has them
			continue
		if _nearest(eyes, ps.global_position) > DESPAWN_R:
			_remove(ps)
	if _alive() >= target or peds.size() >= target * 2:
		return
	# One new person a go, in a block near someone, out of the way.
	var blocks: Array = []
	for k in gen.blocks.size():
		var b: Dictionary = gen.blocks[k]
		if nav and not nav.block_ready(k):
			continue
		var r: Rect2 = b.rect
		if _nearest(eyes, Vector3(r.get_center().x, 0, r.get_center().y)) < SPAWN_R + 24.0:
			blocks.append(k)
	if blocks.is_empty():
		return
	for tries in 6:
		var k: int = blocks[_rng.randi_range(0, blocks.size() - 1)]
		var route := route_for(gen, k, _rng)
		var i := _rng.randi_range(0, route.size() - 1)
		var p: Vector3 = route[i]
		var d := _nearest(eyes, p)
		if d < MIN_SPAWN_GAP or d > SPAWN_R:
			continue
		var s := dispatch.spawn_suspect(p, Suspect.S.WANDER, false)
		s.civilian = true
		s.route = route
		s._route_i = i
		s._pace = _rng.randf_range(0.8, 1.25)
		peds.append(s)
		return


func _alive() -> int:
	var n := 0
	for s in peds:
		if is_instance_valid(s) and (s as Suspect).state != Suspect.S.DOWN:
			n += 1
	return n


func _remove(s: Suspect) -> void:
	peds.erase(s)
	dispatch.suspects.erase(s.net_id)
	s.queue_free()


static func _nearest(eyes: Array, p: Vector3) -> float:
	var best := INF
	for e in eyes:
		best = minf(best, (e as Vector3).distance_to(p))
	return best
