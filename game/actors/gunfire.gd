class_name Gunfire
extends RefCounted
## What an officer's shot does (host only), shared by the scenes: bullets
## hurt officers and suspects (with a wound by where they hit), break windows and dent
## police cars, and chip the destructible world; slot 2's demolition charge
## blows up where it lands. Returns where the shot ended, for the tracer.

const BULLET_DAMAGE := 25.0


static func resolve(world: DestructionWorld, cars: CarSync, origin: Vector3, dir: Vector3, alt: bool, shooter: Officer) -> Vector3:
	var hit := Melee.bullet_ray(shooter.get_world_3d().direct_space_state, origin, dir, shooter)
	if alt:
		var at: Vector3 = hit.position if hit else origin + dir * 8.0
		Blast.go(shooter.get_tree(), world, cars, at, 3.5, 200.0, 9.0)
	elif hit and hit.collider is Officer:
		var o := hit.collider as Officer
		o.take_damage(shooter.shot_damage(), dir, o.body_part_at(hit.position))
	elif hit and hit.collider is Suspect:
		var sp := hit.collider as Suspect
		sp.take_damage(shooter.shot_damage(), dir)
	elif hit and hit.collider is Car and cars:
		var surface := cars.bullet_hit(hit.collider, hit.position, dir)
		if world:
			world.bullet_hit(null, hit.position, hit.normal, dir)
		_sound(origin, hit.position, surface, 0, shooter)
	elif hit and world:
		world.bullet_hit(hit.collider, hit.position, hit.normal, dir)
	var end: Vector3 = hit.position if hit else origin + dir * 60.0
	if not alt and not (hit and hit.collider is Car):
		var what := 2 if not hit else (1 if (hit.collider is Officer or hit.collider is Suspect or hit.collider is PhysicalBone3D) else 0)
		_sound(origin, end, Sfx.surface_of(hit.collider) if hit else "concrete", what, shooter)
	if not alt:
		whizz(shooter.get_tree(), origin, end, shooter)
	return end


## Bullets passing close keep suspects' heads down (Phase 1.5).
static func whizz(tree: SceneTree, a: Vector3, b: Vector3, shooter: Node) -> void:
	for n in tree.get_nodes_in_group("suspects"):
		var s := n as Suspect
		if s == shooter or not s.is_free():
			continue
		var c := s.global_position + Vector3(0, 1.0, 0)
		var p := Geometry3D.get_closest_point_to_segment(c, a, b)
		if p.distance_to(c) < 1.8 and p.distance_to(a) > 1.0:
			s.suppress()


## Everyone hears where the bullet went (Phase 1.6).
static func _sound(a: Vector3, b: Vector3, surface: String, what: int, shooter: Officer) -> void:
	if GameSounds.current and GameSounds.current.sync:
		GameSounds.current.sync.bullet(a, b, surface, what, shooter.peer_id if shooter else 0)
	elif shooter:
		Sfx.impact(shooter.get_parent(), b, surface, 0.8)
