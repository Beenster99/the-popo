extends Node
## Runs the city's traffic for a few minutes and reports each car that sat
## still for 10 s or more while it wasn't waiting at a red light, with what
## was in front of it, and how far the traffic got in all.

var minutes := 4.0
var seed_v := 4242


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		minutes = float(args[0])
	if args.size() > 1:
		seed_v = int(args[1])
	City.next_seed = seed_v
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	for i in 30:
		await get_tree().physics_frame
	var tr: TrafficSystem = s.traffic
	# Park the officers well out of the way (they'd make drivers stop for them).
	var o: Officer = s.sync.my_pawn()
	var still := {}
	var episodes: Array = []
	var dist := 0.0
	var last := {}
	var frames := int(minutes * 60.0 * 60.0)
	for f in frames:
		await get_tree().physics_frame
		if f % 30 != 0:
			continue
		for dr in tr.drivers:
			var car: Car = dr.car
			if not is_instance_valid(car):
				continue
			var p := car.global_position
			if last.has(dr.idx):
				dist += Vector2(p.x - last[dr.idx].x, p.z - last[dr.idx].z).length()
			last[dr.idx] = p
			if dr.mode not in ["drive", "flee", "getaway"]:
				still.erase(dr.idx)
				continue
			var at_red := false
			var pts: Array = dr.pts
			for i in range(dr.wi, mini(pts.size(), dr.wi + 3)):
				if pts[i][1] == 1 and tr.light(pts[i][2], pts[i][3]) != TrafficSystem.L.GO and p.distance_to(pts[i][0]) < 30.0:
					at_red = true
			if car.linear_velocity.length() < 0.5 and not at_red:
				if not still.has(dr.idx):
					still[dr.idx] = {"t": f / 60.0, "p": p}
				var e: Dictionary = still[dr.idx]
				if not e.has("logged") and f / 60.0 - e.t > 10.0:
					e.logged = true
					tr._gap_ahead(car, 0.0)
					var b = tr.last_blocker
					var why := "nothing seen ahead (physical: prop/debris/kerb/wall?)"
					if b is CivilianVehicle:
						var bd = _driver_of(tr, b)
						why = "%s %s %.1fm ahead, side %.2f" % [(b as CivilianVehicle).kind, "parked" if bd.is_empty() else bd.mode, car.global_position.distance_to(b.global_position), (car.global_transform.affine_inverse() * (b as Node3D).global_position).x]
					elif b is Car:
						why = "%s" % b.name
					elif b != null:
						why = "person %s" % b.name
					var ray := _ray_hit(car)
					var g3 := tr._gap_ahead(car, 0.0, 2.0 * TrafficSystem.LANE)
					why += " [wait %.1f tries %d off %.1f/%.1f to_stop %.0f opp %.0f %s eye %s]" % [dr.wait, dr.tries, dr.off, dr.off_want, tr.dist_to_stop(dr, p), g3, tr.last_blocker.name if tr.last_blocker else "-", not tr._out_of_sight(p, 70.0)]
					episodes.append("%6.1fs %-11s at (%.0f,%.0f) %s | ray: %s" % [e.t, (car as CivilianVehicle).kind, p.x, p.z, why, ray])
			else:
				still.erase(dr.idx)
	var stuck_now := 0
	for k in still:
		if still[k].has("logged"):
			stuck_now += 1
	print("\n".join(episodes))
	print("TRAFFIC %d min seed %d: %d stuck episodes, %d still stuck at the end, %.0f m driven (%.0f m per car-minute)" % [minutes, seed_v, episodes.size(), stuck_now, dist, dist / (TrafficSystem.MOVING * minutes)])
	get_tree().quit()


func _driver_of(tr: TrafficSystem, c: Object) -> Dictionary:
	for dr in tr.drivers:
		if dr.car == c:
			return dr
	return {}


func _ray_hit(car: Car) -> String:
	var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3(0, 0.2, 0), car.global_position + Vector3(0, 0.2, 0) + car.global_transform.basis.z * (car.size.z * 0.5 + 2.5))
	q.exclude = [car.get_rid()]
	var h := car.get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty():
		return "clear"
	var n: Node = h.collider
	return "%s (%s)" % [n.name, n.get_parent().name if n.get_parent() else ""]
