extends Node
## Help, Key binds, tooltips and in-game tips.
var t


func test_help_topics_fill_every_key() -> void:
	for tp in HelpScreen.TOPICS:
		var body: String = HelpScreen.controls_text() if tp[2] == "@controls" else HelpScreen.fill(tp[2])
		t.check(not body.contains("{"), "every {key} filled in: " + tp[0])
		t.check(String(tp[1]) != "", "topic has a tooltip: " + tp[0])


func test_help_screen_opens() -> void:
	var h := HelpScreen.new()
	add_child(h)
	await get_tree().process_frame
	for i in HelpScreen.TOPICS.size():
		h.call("_show", i)
	t.check(h.get("_text").get_parsed_text().length() > 100, "a page of text")
	h.close()


func test_key_binds_screen_lists_everything() -> void:
	var k := KeyBindsScreen.new()
	add_child(k)
	await get_tree().process_frame
	var rows: Array = k.get("_rows")
	t.check(rows[0].size() == Controls.REBINDABLE.size(), "every action on the keyboard tab")
	t.check(rows[1].size() == Controls.REBINDABLE.size() - 4, "every action but the stick on the controller tab")
	t.check((rows[0]["jump"].bind as Button).text == "Space", "jump shows Space")
	t.check((rows[1]["jump"].bind as Button).text == "A (Cross)", "jump shows A (Cross)")
	# Rebind through the screen: start waiting, then a key arrives.
	k.call("_start_wait", "kick", false)
	k.set("_wait_from", -1000)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	k.call("_input", ev)
	t.check(Controls.describe(Controls.pc_event("kick")) == "J", "kick moved to J")
	t.check((rows[0]["kick"].bind as Button).text == "J", "button shows J")
	Controls.reset_to_defaults()
	k.close()


func test_every_setting_has_a_tooltip() -> void:
	for e in Settings.SCHEMA:
		if e[3] == "head":
			continue
		t.check(SettingsScreen._tip(e) != "", "tooltip for " + e[1])


func test_tips_fill_and_show_once() -> void:
	for id in GameTips.TIPS:
		t.check(not GameTips.fill(GameTips.TIPS[id]).contains("{"), "tip keys filled: " + id)
	GameTips.reset()
	t.check(not GameTips.seen("gun"), "not seen after reset")
	GameTips._mark("gun")
	GameTips._loaded = false
	GameTips._seen.clear()
	t.check(GameTips.seen("gun"), "remembered from the file")
	GameTips.reset()
