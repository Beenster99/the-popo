extends Node
## Internet hosting messages (the router itself can't be tested here).
var t


func test_open_port_gives_friends_the_address() -> void:
	var s := PortOpener.describe("open", 27015, "81.2.3.4", "81.2.3.4")
	t.check(s.contains("81.2.3.4 : 27015"), s)
	t.check(not s.contains("CGNAT"), "no CGNAT warning when addresses match")


func test_detects_double_nat() -> void:
	var s := PortOpener.describe("open", 27015, "81.2.3.4", "100.64.0.9")
	t.check(s.contains("CGNAT"), s)


func test_manual_fallback_explains_what_to_do() -> void:
	var s := PortOpener.describe("manual", 27015, "81.2.3.4", "", "Your router did not answer.")
	t.check(s.contains("Forward UDP port 27015") and s.contains("81.2.3.4 : 27015"), s)


func test_hosting_starts_and_stopping_closes() -> void:
	t.check(Net.port_opener != null and Net.port_opener.get_parent() == Net, "port opener lives on Net")
	Net.leave()
	t.check(Net.port_opener.state == "idle", "idle after leaving")
