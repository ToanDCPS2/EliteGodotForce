extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.set_mission("0.00"); m.load_room("Town0")
	await create_timer(0.3).timeout
	if OS.get_environment("SHORT") != "": root.size = Vector2i(1400, 300); await create_timer(0.3).timeout
	m.dev.visible = true; m._layout(); await create_timer(0.2).timeout
	var shots := []
	for tab in 4:
		var tabs: TabContainer = m.dev.find_children("*", "TabContainer", true, false)[0]
		tabs.current_tab = tab; await create_timer(0.15).timeout
		var sc: ScrollContainer = tabs.get_tab_control(tab)
		if OS.get_environment("FILL") != "" and tab == 0:
			for k in 30: var l := Label.new(); l.text = "filler %d" % k; sc.get_child(0).add_child(l)
			await create_timer(0.2).timeout
		print("TAB ", tabs.get_tab_title(tab), " content h ", sc.get_child(0).size.y, " view h ", sc.size.y, " scrollbar ", sc.get_v_scroll_bar().visible)
		shots.append(root.get_texture().get_image())
	var w: int = shots[0].get_width() / 2; var h: int = shots[0].get_height() / 2
	var sheet := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for i in 4:
		var s: Image = shots[i]; s.resize(w, h); s.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(s, Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	sheet.save_png(OS.get_cmdline_user_args()[0]); quit()
