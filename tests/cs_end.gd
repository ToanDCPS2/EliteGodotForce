extends SceneTree
## Lean through the whole course, then check the light at the end and the results screen.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m._show_menu(); await create_timer(0.3).timeout
	m.menu.start_minigame.emit("cartsurfer", {"mode": "normal", "controls": "pad"})
	await create_timer(0.3).timeout
	var cs = m.minigame
	cs.set_process(false)
	var held := ""; var shots := []
	var end_start: int = cs.timeline[-1]["start"]
	for i in 6000:
		var sg: Array = cs._segment()
		var want := ""
		if sg[2] != null and sg[0] != "straight1" and sg[0] != "end": want = "ui_left" if sg[2]["type"] == "L" else "ui_right"
		if want != held:
			if held != "": Input.action_release(held)
			if want != "": Input.action_press(want)
			held = want
		if cs.done: break
		cs._process(1.0 / 60.0)
		var rel := int(cs.t) - end_start
		if rel in [36, 72, 90, 110, 120]:
			print("END +", rel, " frame ", sg[1], " track white ", snappedf(cs.white_track.color.a, 0.01), " all white ", snappedf(cs.white_all.color.a, 0.01))
			await process_frame
			var im: Image = root.get_texture().get_image(); im.resize(im.get_width() / 2, im.get_height() / 2); shots.append(im)
	await create_timer(0.6).timeout
	print("SCREEN ", m.menu.screen if m.menu else "none", " minigame ", m.minigame != null, " save coins ", m.menu.read_save().get("coins", -1) if m.menu else -1)
	var im2: Image = root.get_texture().get_image(); im2.resize(im2.get_width() / 2, im2.get_height() / 2); shots.append(im2)
	var w: int = shots[0].get_width(); var h: int = shots[0].get_height()
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for k in shots.size():
		var s: Image = shots[k]; s.convert(Image.FORMAT_RGBA8); sheet.blit_rect(s, Rect2i(0, 0, w, h), Vector2i((k % 3) * w, (k / 3) * h))
	sheet.save_png(OS.get_cmdline_user_args()[0]); quit()
