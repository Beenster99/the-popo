class_name Melee
## What a punch, kick or shoulder barge hits, and what it does to it. Host
## only: hooked to Officer.struck by each scene.

const REACH := {Officer.Strike.PUNCH: 1.0, Officer.Strike.KICK: 1.35, Officer.Strike.BARGE: 1.1}
const PIECE_DAMAGE := {Officer.Strike.PUNCH: 8.0, Officer.Strike.KICK: 45.0, Officer.Strike.BARGE: 60.0}
const OFFICER_DAMAGE := {Officer.Strike.PUNCH: 8.0, Officer.Strike.KICK: 12.0, Officer.Strike.BARGE: 10.0}
const SHOVE := {Officer.Strike.PUNCH: 2.5, Officer.Strike.KICK: 4.5, Officer.Strike.BARGE: 6.0}


## Friendly fire setting (the host's, since damage is decided on the host).
static func friendly_fire() -> bool:
	var ml := Engine.get_main_loop() as SceneTree
	var st: Node = ml.root.get_node_or_null("/root/Settings") if ml else null
	return st == null or bool(st.get("values").get("friendly_fire", true))


## A bullet's ray. With friendly fire off it passes through other officers.
static func bullet_ray(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, shooter: Officer, length := 60.0) -> Dictionary:
	var exclude := [shooter.get_rid()]
	if shooter.car != null:
		exclude.append(shooter.car.get_rid())   # shooting out of your own car
	var ff := friendly_fire()
	for i in 4:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + dir * length, 1 | 2 | 16, exclude))
		if hit and hit.collider is Officer and not ff:
			exclude.append((hit.collider as Officer).get_rid())
			continue
		return hit
	return {}


static func resolve(attacker: Officer, world: DestructionWorld, origin: Vector3, dir: Vector3, kind: Officer.Strike) -> void:
	var space := attacker.get_world_3d().direct_space_state
	var reach: float = REACH[kind]
	# A short fan of rays: dead ahead and a little either side.
	for a in [0.0, -0.35, 0.35]:
		var d := dir.rotated(Vector3.UP, a)
		var ex := [attacker.get_rid()]
		if not friendly_fire():
			for o in attacker.get_tree().get_nodes_in_group("officers"):
				ex.append((o as Officer).get_rid())
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * reach, 1 | 2 | 4 | 16, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var c: Object = hit.collider
		if GameSounds.current and GameSounds.current.sync:
			var body := c is Officer or c is Suspect
			var what := 0 if body else Sfx.SURFACES.find(Sfx.surface_of(c)) + 1
			GameSounds.current.sync.melee_hit(hit.position, maxi(what, 0), kind != Officer.Strike.PUNCH)
		if c is Officer:
			var o := c as Officer
			o.take_damage(OFFICER_DAMAGE[kind], d, "melee")
			o.shove(d * SHOVE[kind] + Vector3.UP * (1.5 if kind == Officer.Strike.BARGE else 0.0))
		elif c is Suspect:
			(c as Suspect).struck(d, OFFICER_DAMAGE[kind], SHOVE[kind])
		elif c is Node and (c as Node).has_meta("piece_id") and world:
			world.strike_piece((c as Node).get_meta("piece_id"), PIECE_DAMAGE[kind], hit.position, d)
		elif c is RigidBody3D:
			var rb := c as RigidBody3D
			rb.apply_impulse(d * minf(rb.mass, 120.0) * SHOVE[kind] * 0.5, hit.position - rb.global_position)
			if rb.has_meta("prop_id") and PropWorld.current:
				PropWorld.current.damage_prop(int(rb.get_meta("prop_id")), PIECE_DAMAGE[kind] * 0.6, hit.position, d)
		return
