extends Node
## Wave 5, Phase 5.2: the police radio and the music.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_radio_and_music() -> void:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	await _frames(20)
	t.check(AudioServer.get_bus_index(Sfx.BUS_MUSIC) >= 0 and AudioServer.get_bus_index(Sfx.BUS_RADIO) >= 0, "music and radio buses")
	var radio: PoliceRadio = s.get_node("Radio")
	var music: MusicDirector = s.get_node("Music")
	var n0 := radio.lines
	s.dispatch.say("DISPATCH: test line, all units.")
	await _frames(2)
	t.check(radio.lines == n0 + 1 and radio.player.playing, "a radio line keys the radio")
	t.check(String(radio.player.stream.resource_path).contains("radio_key"), "it starts with the key-up click")
	t.check(music.patrol.playing and music.patrol.stream.loop and music.heat < 0.05, "a quiet patrol bed under the game")
	Sfx.shot(s, s.sync.my_pawn().global_position + Vector3(10, 0, 0))
	for i in 180:
		await get_tree().process_frame
	print("    heat after a shot: %.2f, action %.1f dB, patrol %.1f dB" % [music.heat, music.action.volume_db, music.patrol.volume_db])
	t.check(music.heat > 0.5 and music.action.volume_db > music.patrol.volume_db, "a gunshot brings in the action music")
	Sfx.last_shot_ms = -100000
	s.queue_free()
	await _frames(2)
	var menu: Node = load("res://game/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(2)
	var players := menu.find_children("*", "AudioStreamPlayer", false, false)
	t.check(players.size() == 1 and (players[0] as AudioStreamPlayer).playing, "the title theme on the menu")
	menu.queue_free()
	await _frames(2)
