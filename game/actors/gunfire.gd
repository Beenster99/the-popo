class_name Gunfire
extends RefCounted
## What an officer's shot does (host only), shared by the scenes: bullets
## hurt officers and suspects (with a wound by where they hit), break windows and dent
## police cars, and chip the destructible world; slot 2's demolition charge
## blows up where it lands. Returns where the shot ended, for the tracer.

const BULLET_DAMAGE := 25.0


static func resolve(world: DestructionWorld, cars: CarSync, origin: Vector3, dir: Vector3, alt: bool, shooter: Officer, through := false) -> Vector3:
	var hit := Melee.bullet_ray(shooter.get_world_3d().direct_space_state, origin, dir, shooter)
	if Net.is_host() and not through:
		shooter.get_tree().call_group("alarm_listeners", "on_alarm", origin, 45.0)
	# v0.20.0: tyres hang below the car's collision box, so a shot can
	# pass right through one without touching a collider: check the path.
	if not alt and cars and Net.is_host():
		var ty := cars.tyre_on_path(origin, hit.position if hit else origin + dir * 60.0, shooter.car)
		if not ty.is_empty():
			cars.burst_tyre(ty.car, ty.wheel)
			_sound(origin, ty.point, "metal", 0, shooter)
			whizz(shooter.get_tree(), origin, ty.point, shooter)
			return ty.point
	if alt:
		# Phase 3.6: a breach charge or C4, stuck where you aimed (in reach).
		var at: Vector3 = hit.position if hit and (hit.position as Vector3).distance_to(origin) < 12.0 else origin + dir * 3.0
		Charge.place(shooter.get_tree(), shooter.get_parent(), world, cars, at, Armoury.charge_blast(shooter.kit), Armoury.gear_of(shooter.kit) == Armoury.Gear.C4)
	elif hit and hit.collider is Officer:
		var o := hit.collider as Officer
		o.take_damage(shooter.shot_damage(), dir, o.body_part_at(hit.position))
	elif hit and hit.collider is Suspect:
		var sp := hit.collider as Suspect
		# Tactical pass: a head shot drops them; a careful shot is rewarded.
		var head := (hit.position as Vector3).y - sp.global_position.y > 1.42
		sp.take_damage(shooter.shot_damage() * (3.0 if head else 1.0), dir)
	elif hit and hit.collider.has_method("on_bullet"):
		hit.collider.on_bullet(hit.position, shooter)   # a range target
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
	# Phase 3.5: armour-piercing rounds go on through a car, glass, a door or
	# a thin wall, and hit whatever's behind.
	if not alt and not through and hit and shooter.gun == EnemyGuns.NONE and Armoury.ammo_of(shooter.kit) == Armoury.Ammo.AP \
			and not (hit.collider is Officer or hit.collider is Suspect) \
			and (hit.collider is Car or Sfx.surface_of(hit.collider) in ["glass", "wood", "metal", "plaster"]):
		resolve(world, cars, (hit.position as Vector3) + dir * 0.45, dir, false, shooter, true)
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
