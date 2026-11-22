class_name Melee
## What a punch, kick or shoulder barge hits, and what it does to it. Host
## only: hooked to Officer.struck by each scene.

const REACH := {Officer.Strike.PUNCH: 1.0, Officer.Strike.KICK: 1.35, Officer.Strike.BARGE: 1.1}
const PIECE_DAMAGE := {Officer.Strike.PUNCH: 8.0, Officer.Strike.KICK: 45.0, Officer.Strike.BARGE: 60.0}
const OFFICER_DAMAGE := {Officer.Strike.PUNCH: 8.0, Officer.Strike.KICK: 12.0, Officer.Strike.BARGE: 10.0}
const SHOVE := {Officer.Strike.PUNCH: 2.5, Officer.Strike.KICK: 4.5, Officer.Strike.BARGE: 6.0}


static func resolve(attacker: Officer, world: DestructionWorld, origin: Vector3, dir: Vector3, kind: Officer.Strike) -> void:
	var space := attacker.get_world_3d().direct_space_state
	var reach: float = REACH[kind]
	# A short fan of rays: dead ahead and a little either side.
	for a in [0.0, -0.35, 0.35]:
		var d := dir.rotated(Vector3.UP, a)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * reach, 1 | 2 | 4 | 16, [attacker.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var c: Object = hit.collider
		if c is Officer:
			var o := c as Officer
			o.take_damage(OFFICER_DAMAGE[kind], d)
			o.shove(d * SHOVE[kind] + Vector3.UP * (1.5 if kind == Officer.Strike.BARGE else 0.0))
		elif c is Node and (c as Node).has_meta("piece_id") and world:
			world.strike_piece((c as Node).get_meta("piece_id"), PIECE_DAMAGE[kind], hit.position, d)
		elif c is RigidBody3D:
			var rb := c as RigidBody3D
			rb.apply_impulse(d * minf(rb.mass, 120.0) * SHOVE[kind] * 0.5, hit.position - rb.global_position)
		return
