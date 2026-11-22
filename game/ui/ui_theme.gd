class_name UiTheme
extends RefCounted
## The look shared by the menus: dark navy panels, hi-vis yellow accents.

const BG := Color("121826")
const PANEL := Color("1b2230")
const ACCENT := Color("ffd23f")
const TEXT := Color("e8ecf2")
const DIM := Color("8a96a8")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color("263044"), "hover": Color("33405a"), "pressed": Color("3d4c6b"),
			"focus": Color("263044"), "disabled": Color("1e2533")}[state]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		if state == "focus":
			sb.draw_center = false
			sb.border_color = ACCENT
			sb.set_border_width_all(2)
		elif state == "hover":
			sb.border_color = ACCENT.darkened(0.3)
			sb.set_border_width_all(1)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", DIM)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", panel)
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = PANEL
	tab_sel.border_color = ACCENT
	tab_sel.border_width_bottom = 3
	tab_sel.set_content_margin_all(10)
	var tab_un := tab_sel.duplicate()
	tab_un.bg_color = BG
	tab_un.border_width_bottom = 0
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_un)
	var tc_panel := StyleBoxFlat.new()
	tc_panel.bg_color = PANEL
	tc_panel.set_content_margin_all(16)
	t.set_stylebox("panel", "TabContainer", tc_panel)
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_font_size("font_size", "TabContainer", 20)
	_theme = t
	return t


static func title(text: String, size := 30, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 58)
	b.add_theme_font_size_override("font_size", 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	return b
