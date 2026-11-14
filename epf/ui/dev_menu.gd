class_name DevMenu
extends Control
## Enhancements / Dev menu overlay (F1). Everything not original to the game lives here (see docs/DEV_MENU_SPEC.md).
## Built at native window resolution (u = pixels per UI unit) so text stays sharp however the game view is scaled.
var main: Node
var rooms: Array = []
var sel_room := 0
var sel_event := 0
var sel_mission := 0
const MISSIONS := ["All missions (no filter)", "1.01", "1.02", "1.03", "2.01", "2.02", "2.03", "3.01", "3.02", "3.03", "3.04", "4.01", "4.02", "4.03", "4.04", "5.01", "0.00", "0.01", "0.02", "0.03", "0.04", "0.05", "0.06", "0.07", "0.08", "0.09", "0.10", "0.11", "0.12", "0.13", "0.14", "0.15"]
func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func setup(r: Array, m: Node) -> void:
	rooms = r; main = m

var sel_tab := 0
var _scroll_pos := {}                 # tab index -> scroll position, kept across rebuilds (window resizes)

## Sections as tabs; each tab scrolls when its content is taller than the window.
func build(u: float) -> void:
	if main == null: return
	for c in get_children(): c.queue_free()
	var fs := int(8 * u); var fs2 := int(7 * u)
	var win := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1152, 648)
	var p := PanelContainer.new(); p.position = Vector2(8, 8) * u
	p.size = Vector2(minf(190.0 * u, win.x - 16.0 * u), win.y - 16.0 * u)
	add_child(p)
	var outer := VBoxContainer.new(); p.add_child(outer)
	var t := Label.new(); t.text = "DEV MENU (F1)"; t.add_theme_font_size_override("font_size", fs); outer.add_child(t)
	var tabs := TabContainer.new(); tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", fs2)
	outer.add_child(tabs)
	var world := _section(tabs, "World", u)
	var gfx := _section(tabs, "Graphics", u)
	var aud := _section(tabs, "Audio", u)
	var ctl := _section(tabs, "Controls", u)

	# ---- World: where you are and what is spawned ----
	world.add_child(_head("Room", fs2))
	var ob := _opt(fs); for r in rooms: ob.add_item(str(r))
	ob.select(clampi(sel_room, 0, maxi(rooms.size() - 1, 0)))
	ob.item_selected.connect(func(i: int) -> void: sel_room = i; main.load_room(ob.get_item_text(i)))
	world.add_child(ob)
	world.add_child(_head("Mission", fs2))
	var ms := _opt(fs); for m2 in MISSIONS: ms.add_item(("Mission: " + m2) if m2[0].is_valid_int() else m2)
	ms.select(sel_mission)
	ms.item_selected.connect(func(i: int) -> void:
		sel_mission = i; main.set_mission("" if i == 0 else MISSIONS[i]))
	world.add_child(ms)
	world.add_child(_head("Seasonal event", fs2))
	var ev := _opt(fs); for s2 in ["No event", "Summer", "Halloween", "Christmas", "Show all"]: ev.add_item(s2)
	ev.select(sel_event)
	ev.item_selected.connect(func(i: int) -> void:
		sel_event = i; main.event_filter = [0, 2, 3, 4, -1][i]; main.load_room(main.room_prefix))
	world.add_child(ev)
	world.add_child(_head("Minigames", fs2))
	var cs := Button.new(); cs.text = "Play Cart Surfer (Normal)"; cs.add_theme_font_size_override("font_size", fs)
	cs.pressed.connect(func() -> void: main.start_cart_surfer())
	world.add_child(cs)
	world.add_child(_check("Strict interest gating (original rule)", main.strict_interest, fs, func(on: bool) -> void: main.strict_interest = on))
	world.add_child(_head("Saving", fs2))
	world.add_child(_check("Save after every change (not original)", main.save_every_change, fs, func(on: bool) -> void:
		main.save_every_change = on; main.settings["save_every_change"] = on; main._save_settings()))

	# ---- Graphics ----
	var vm := _opt(fs); vm.add_item("View: fit room (letterbox)"); vm.add_item("View: fill screen (zoom, scroll)")
	vm.select(main.view_mode)
	vm.item_selected.connect(func(i: int) -> void: main.view_mode = i; main.cam = Vector2.ZERO; main._layout())
	gfx.add_child(vm)
	var fl := _opt(fs); fl.add_item("Filter: nearest (sharp)"); fl.add_item("Filter: linear (smooth)")
	fl.select(0 if main.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST else 1)
	fl.item_selected.connect(func(i: int) -> void:
		main.set_filter(i == 1))
	gfx.add_child(fl)
	gfx.add_child(_check("White flash between menus", main.menu_flash, fs, func(on: bool) -> void: main.menu_flash = on))
	gfx.add_child(_head("3D objects", fs2))
	gfx.add_child(_check("High-res 3D objects (4x, smooth)", main.model_hires, fs, func(on: bool) -> void: main.model_hires = on; main.apply_model_tuning()))
	gfx.add_child(_slider("3D model scale", 0.2, 1.5, 0.05, main.model_scale, fs2, u, func(x: float) -> void: main.model_scale = x; main.apply_model_tuning()))
	gfx.add_child(_slider("3D model Y offset", -120.0, 120.0, 1.0, main.model_yoff, fs2, u, func(x: float) -> void: main.model_yoff = x; main.apply_model_tuning()))

	# ---- Audio ----
	if main.music:
		aud.add_child(_head("Music", fs2))
		aud.add_child(_slider("Music volume", 0.0, 1.0, 0.05, main.music.volume, fs2, u, func(x: float) -> void: main.music.volume = x))
		aud.add_child(_check("Mute music", main.music.muted, fs, func(on: bool) -> void: main.music.muted = on))
		aud.add_child(_check("Smooth music resampling (not original)", main.music.interp, fs, func(on: bool) -> void: main.music.interp = on))
	if main.sfx:
		aud.add_child(_head("Sound effects", fs2))
		aud.add_child(_slider("SFX volume", 0.0, 1.0, 0.05, main.sfx.volume, fs2, u, func(x: float) -> void: main.sfx.volume = x))
		aud.add_child(_check("Mute sound effects", main.sfx.muted, fs, func(on: bool) -> void: main.sfx.muted = on))

	# ---- Controls ----
	ctl.add_child(_check("Edge scrolling (fill mode)", main.edge_scroll, fs, func(on: bool) -> void: main.edge_scroll = on))
	ctl.add_child(_check("Original ROM cursor", main.rom_cursor, fs, func(on: bool) -> void: main.set_rom_cursor(on)))
	ctl.add_child(_slider("Cursor size", 0.5, 3.0, 0.1, main.cursor_mult, fs2, u, func(x: float) -> void: main.cursor_mult = x))
	var note := Label.new(); note.text = "Arrows / screen edges scroll in fill mode"; note.add_theme_font_size_override("font_size", fs2)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ctl.add_child(note)

	tabs.current_tab = clampi(sel_tab, 0, tabs.get_tab_count() - 1)
	tabs.tab_changed.connect(func(i: int) -> void: sel_tab = i)
	# restore each tab's scroll after layout
	for i in tabs.get_tab_count():
		var sc: ScrollContainer = tabs.get_tab_control(i)
		var idx := i
		sc.get_v_scroll_bar().value_changed.connect(func(v: float) -> void: _scroll_pos[idx] = v)
		if _scroll_pos.has(i): sc.set_deferred("scroll_vertical", int(_scroll_pos[i]))

## a tab page: a vertical scroll area holding a VBox (returned)
func _section(tabs: TabContainer, title: String, u: float) -> VBoxContainer:
	var sc := ScrollContainer.new(); sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", int(3 * u))
	sc.add_child(v); tabs.add_child(sc)
	return v

func _head(text: String, fs2: int) -> Label:
	var l := Label.new(); l.text = text.to_upper(); l.add_theme_font_size_override("font_size", fs2)
	l.modulate = Color(0.65, 0.8, 1.0)
	return l

func _check(text: String, on: bool, fs: int, cb: Callable) -> CheckBox:
	var c := CheckBox.new(); c.text = text; c.button_pressed = on
	c.add_theme_font_size_override("font_size", fs)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.toggled.connect(cb)
	return c

func _opt(fs: int) -> OptionButton:
	var o := OptionButton.new(); o.add_theme_font_size_override("font_size", fs)
	o.get_popup().add_theme_font_size_override("font_size", fs)
	return o

func _slider(label: String, lo: float, hi: float, step: float, val: float, fs2: int, u: float, cb: Callable) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new(); l.add_theme_font_size_override("font_size", fs2); l.text = "%s: %s" % [label, str(val)]; box.add_child(l)
	var sl := HSlider.new(); sl.min_value = lo; sl.max_value = hi; sl.step = step; sl.value = val; sl.custom_minimum_size = Vector2(150 * u, 8 * u)
	sl.value_changed.connect(func(x: float) -> void:
		l.text = "%s: %s" % [label, str(snappedf(x, step))]; cb.call(x))
	box.add_child(sl)
	return box

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F1:
		visible = not visible; mouse_filter = Control.MOUSE_FILTER_PASS if visible else Control.MOUSE_FILTER_IGNORE
