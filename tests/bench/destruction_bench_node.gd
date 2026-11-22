extends Node

const COUNTS := [5, 10, 20, 40, 60]


func _ready() -> void:
	var lines := ["| Walls | Chunks | Peak awake synced bodies | Peak snapshot | Peak bandwidth per client | Avg physics step | Worst physics step |", "|---|---|---|---|---|---|---|"]
	for n in COUNTS:
		var r: Dictionary = await _run(n)
		lines.append("| %d | %d | %d | %.1f KB | %.0f kbps | %.2f ms | %.2f ms |" % [n, r.chunks, r.awake, r.bytes / 1024.0, r.bytes * 8.0 * 20.0 / 1000.0, r.avg_ms, r.worst_ms])
		print(lines[-1])
	print("\n".join(lines))
	var f := FileAccess.open("user://destruction_bench.md", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	get_tree().quit()


func _run(n: int) -> Dictionary:
	var holder := Node3D.new()
	add_child(holder)
	ProtoWorld.ground(holder, 400.0)
	var w := DestructionWorld.new()
	holder.add_child(w)
	var per_row := 10
	for r in ceili(n / float(per_row)):
		BuildingLayout.wall_row(w, Vector3(-22, 0, -r * 5.0), min(per_row, n - r * per_row))
	w.finalize()
	await get_tree().physics_frame
	for p in w.pieces.values():
		w.damage_piece(p.id, 9999.0, p.aabb.get_center() + Vector3(0, 0, 1.5), 6.0)
	var worst := 0.0
	var total := 0.0
	var frames := 0
	var peak_awake := 0
	var peak_bytes := 0
	for i in 240:
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = max(worst, ms)
		total += ms
		frames += 1
		if i % 3 == 0:
			var b := StreamPeerBuffer.new()
			w._write_snapshot(b)
			peak_awake = max(peak_awake, w.awake_total)
			peak_bytes = max(peak_bytes, b.data_array.size() + 40)
	var chunks := w.chunk_count
	holder.queue_free()
	await get_tree().physics_frame
	return {"chunks": chunks, "awake": peak_awake, "bytes": peak_bytes, "avg_ms": total / frames, "worst_ms": worst}
