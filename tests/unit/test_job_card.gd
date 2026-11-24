extends Node
## 2026-11-24: the job card (beenster: "a little more information as well
## as the radio call"): the kind, pay, street, distance and heading, the
## dispatch text, the crooks (armed, shotguns, dealt with) and what to do.
var t


func test_job_card_says_what_where_and_who() -> void:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	s.dispatch.missions.enabled = false
	s.dispatch.stories.enabled = false
	for i in 60 * 12:
		await get_tree().physics_frame
	var d := s.dispatch
	var id := d.start_call(Dispatcher.Kind.GANG)
	t.check(id > 0, "a shots fired call")
	if id <= 0:
		s.queue_free()
		return
	var c: Dictionary = d.calls[id]
	var br := d.brief(c)
	t.check(br.total >= 3 and br.armed >= 3 and br.shotguns >= 1 and br.done == 0, "the brief counts the gang: %s" % br)
	var hud := s.find_children("*", "DispatchHud", true, false)[0] as DispatchHud
	var from: Vector3 = c.marker + Vector3(0, 0, 120)   # 120 m south of it
	var card := hud.card_text(c, from)
	print("    ", card.replace("\n", " | "))
	t.check(card.contains("SHOTS FIRED") and card.contains("£450"), "kind and pay")
	t.check(card.contains(CityGenerator.street_at(c.marker).get_slice(" near ", 0)), "the street")
	t.check(card.contains("120 m north"), "how far and which way")
	t.check(card.contains(String(c.text)), "the dispatch text")
	t.check(card.contains("armed") and card.contains("shotgun"), "who's armed")
	t.check(card.contains("cover"), "what to do")
	# One down: the card keeps count.
	(d.suspects[c.suspects[0]] as Suspect).set_state(Suspect.S.SURRENDER)
	t.check(hud.card_text(c, from).contains("1 dealt with"), "dealt with so far")
	for i in 3:
		await get_tree().process_frame
	t.check(hud._card_box.visible, "the card is on screen")
	s.queue_free()
	await get_tree().process_frame
