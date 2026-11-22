class_name Gunfire
extends RefCounted
## What an officer's shot does (host only), shared by the scenes: bullets
## hurt officers (with a wound by where they hit), break windows and dent
## police cars, and chip the destructible world; slot 2's demolition charge
## blows up where it lands. Returns where the shot ended, for the tracer.

const BULLET_DAMAGE := 25.0


static func resolve(world: DestructionWorld, cars: CarSync, origin: Vector3, dir: Vector3, alt: bool, shooter: Officer) -> Vector3:
	var hit := Melee.bullet_ray(shooter.get_world_3d().direct_space_state, origin, dir, shooter)
	if alt:
		var at: Vector3 = hit.position if hit else origin + dir * 8.0
		if world:
			world.explode(at, 3.5, 200.0, 9.0)
		for o in shooter.get_tree().get_nodes_in_group("officers"):
			var off := o as Officer
			var d: float = off.global_position.distance_to(at)
			if d < 4.5:
				off.take_damage(110.0 * (1.0 - d / 4.5), (off.global_position - at).normalized(), "blast")
		if cars:
			for c in cars.cars:
				var lp: Vector3 = (c as Car).global_transform.affine_inverse() * at
				if lp.length() < 5.0:
					var ld: Vector3 = -lp.normalized()
					cars._local_dent_host(c, lp, ld, clampf(0.3 * (1.0 - lp.length() / 5.0), 0.05, 0.3))
	elif hit and hit.collider is Officer:
		var o := hit.collider as Officer
		o.take_damage(BULLET_DAMAGE, dir, o.body_part_at(hit.position))
	elif hit and hit.collider is Car and cars:
		var surface := cars.bullet_hit(hit.collider, hit.position, dir)
		if world:
			world.bullet_hit(null, hit.position, hit.normal, dir)
		Sfx.impact(shooter.get_parent(), hit.position, surface, 0.8)
	elif hit and world:
		world.bullet_hit(hit.collider, hit.position, hit.normal, dir)
	return hit.position if hit else origin + dir * 60.0
