class_name PortOpener
extends Node
## Gets the host reachable from the internet.
## 1. Asks the router to forward the game port (UPnP), on a background thread
##    because router discovery takes a few seconds.
## 2. Looks up the public IP address friends should type in, and checks it
##    against the router's own external address: if they differ, the
##    connection is behind a second router or the internet provider's
##    shared address (CGNAT), and port forwarding alone cannot work.
## The mapping is removed again when hosting stops or the game closes.

signal status_changed(text: String)

const LEASE_SECONDS := 0  # 0 = until removed (some routers cap it anyway)
const IP_LOOKUP := "https://api.ipify.org"

var port := 0
var public_ip := ""
var router_ip := ""
var upnp_ok := false
var state := "idle"   # idle, working, open, manual
var _upnp: UPNP
var _thread: Thread
var _http: HTTPRequest


func open(game_port: int) -> void:
	close()
	port = game_port
	state = "working"
	status_changed.emit("Opening port %d on your router..." % port)
	_thread = Thread.new()
	_thread.start(_upnp_work.bind(game_port))
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_ip)
	_http.request(IP_LOOKUP)


func close() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _upnp and upnp_ok:
		_upnp.delete_port_mapping(port, "UDP")
	upnp_ok = false
	_upnp = null
	if _http:
		_http.queue_free()
		_http = null
	state = "idle"


func _exit_tree() -> void:
	close()


func _upnp_work(game_port: int) -> void:
	var u := UPNP.new()
	var result := {"ok": false, "router_ip": "", "why": ""}
	var err := u.discover(2000, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		result.why = "Your router did not answer (UPnP may be switched off)."
	else:
		var m := u.add_port_mapping(game_port, game_port, "The Popo", "UDP", LEASE_SECONDS)
		if m == UPNP.UPNP_RESULT_SUCCESS:
			result.ok = true
			result.router_ip = u.query_external_address()
		else:
			result.why = "Your router refused to open the port (error %d)." % m
	_finish_upnp.call_deferred(u, result)


func _finish_upnp(u: UPNP, result: Dictionary) -> void:
	_upnp = u
	upnp_ok = result.ok
	router_ip = result.router_ip
	state = "open" if upnp_ok else "manual"
	_report(result.why)


func _on_ip(res: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if res == HTTPRequest.RESULT_SUCCESS and code == 200:
		public_ip = body.get_string_from_utf8().strip_edges()
	_report("")


func _report(why: String) -> void:
	status_changed.emit(describe(state, port, public_ip, router_ip, why))


## The text shown to the host. Static so it can be tested without a router.
static func describe(st: String, p: int, pub: String, rtr: String, why := "") -> String:
	var addr := ("%s : %d" % [pub, p]) if pub != "" else "(finding your address...)"
	match st:
		"working":
			return "Opening port %d on your router... Friends will join with %s" % [p, addr]
		"open":
			if pub != "" and rtr != "" and pub != rtr:
				return ("Port %d is open on your router, but your router's address (%s) is not your internet address (%s). " +
					"That usually means a second router or your provider's shared address (CGNAT), so friends outside cannot reach you yet. " +
					"See \"Playing over the internet\" in How to play.txt.") % [p, rtr, pub]
			return "Ready for friends over the internet. Give them:  %s\n(Port %d was opened on your router automatically. If Windows asks, allow The Popo through the firewall.)" % [addr, p]
		"manual":
			return ("%s Forward UDP port %d to this PC on your router yourself (steps in How to play.txt), then friends join with:  %s") % [why, p, addr]
	return ""
