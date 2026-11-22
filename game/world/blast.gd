class_name Blast
extends RefCounted
## Host: one explosion, everything it does: the world shatters and is
## pushed (DestructionWorld.explode), people are hurt, cars are dented and
## damaged, and props near it break. Used by the demolition charge,
## barrels, gas bottles and cars going up.


static func go(tree: SceneTree, world: DestructionWorld, cars: CarSync, at: Vector3, radius := 3.5, damage := 200.0, strength := 9.0) -> void:
	if not Net.is_host():
		return
	if world:
		world.explode(at, radius, damage, strength)
	var reach := radius + 1.0
	for o in tree.get_nodes_in_group("officers"):
		var off := o as Officer
		var d: float = off.global_position.distance_to(at)
		if d < reach:
			off.take_damage(110.0 * (1.0 - d / reach), (off.global_position - at).normalized(), "blast")
	for s in tree.get_nodes_in_group("suspects"):
		var sp := s as Suspect
		var d2: float = sp.global_position.distance_to(at)
		if d2 < reach:
			sp.take_damage(110.0 * (1.0 - d2 / reach), (sp.global_position - at).normalized(), "blast")
	if cars:
		for c in cars.cars:
			var lp: Vector3 = (c as Car).global_transform.affine_inverse() * at
			if lp.length() < radius + 1.5:
				var ld: Vector3 = -lp.normalized()
				var k := 1.0 - lp.length() / (radius + 1.5)
				cars._local_dent_host(c, lp, ld, clampf(0.3 * k, 0.05, 0.3))
				cars.damage_car(c, 70.0 * k, at)
	if PropWorld.current:
		PropWorld.current.blast(at, radius + 0.5, damage * 0.6)
	Feel.blast_shake(tree, at, radius)
