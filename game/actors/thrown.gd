class_name Thrown
extends RefCounted
## Phase 1.5: something thrown at the police (a bottle, a chair, a bin).
## While it is flying fast it hurts whoever it hits; it stops counting
## once it slows down or after a few seconds.

const LIVE_TIME := 3.0
const HURT_SPEED := 4.0


## Velocity that lobs a body from a to b at about this speed (the flatter of
## the two arcs; a 45 degree lob if b is out of reach).
static func launch_velocity(a: Vector3, b: Vector3, speed: float) -> Vector3:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var d := flat.length()
	if d < 0.05:
		return Vector3.UP * speed
	var h := b.y - a.y
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * d * d + 2.0 * h * v2)
	var ang := PI * 0.25
	if disc >= 0.0:
		ang = atan((v2 - sqrt(disc)) / (g * d))
	else:
		# Out of reach: throw harder, at 45 degrees.
		speed = sqrt(g * d * d / maxf(0.1, d - h))
	return flat.normalized() * cos(ang) * speed + Vector3.UP * sin(ang) * speed


## Host: arms a body that was just thrown by who.
static func arm(rb: RigidBody3D, who: Node) -> void:
	rb.set_meta("thrown_t", Time.get_ticks_msec())
	rb.set_meta("thrown_by", who.get_instance_id())
	rb.contact_monitor = true
	rb.max_contacts_reported = maxi(rb.max_contacts_reported, 4)
	if not rb.body_entered.is_connected(_on_hit):
		rb.body_entered.connect(_on_hit.bind(rb))


static func _on_hit(other: Node, rb: RigidBody3D) -> void:
	if not rb.has_meta("thrown_t") or not Net.is_host():
		return
	var age := (Time.get_ticks_msec() - int(rb.get_meta("thrown_t"))) / 1000.0
	var v := rb.linear_velocity.length()
	if age > LIVE_TIME:
		rb.remove_meta("thrown_t")
		return
	if other.get_instance_id() == int(rb.get_meta("thrown_by", 0)):
		return
	if v < HURT_SPEED and not (other is Officer):
		return
	if other is Officer:
		var dmg := clampf(rb.mass * maxf(v, HURT_SPEED) * 0.6, 6.0, 30.0)
		(other as Officer).take_damage(dmg, rb.linear_velocity.normalized(), "torso")
		rb.remove_meta("thrown_t")
	elif other is Suspect:
		(other as Suspect).take_damage(clampf(rb.mass * v * 0.6, 4.0, 25.0), rb.linear_velocity.normalized())
		rb.remove_meta("thrown_t")
	else:
		# Hit the world: it is just junk now.
		rb.remove_meta("thrown_t")
	if rb.has_meta("on_thrown_hit"):
		(rb.get_meta("on_thrown_hit") as Callable).call(other, v)
