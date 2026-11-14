extends SceneTree
## Drive Cart Surfer: env BOT=lean leans through every turn, BOT=none does nothing. Saves shots.
var m
func _init() -> void:
	m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.player_color = OS.get_environment("COLOR") if OS.get_environment("COLOR") != "" else "lime"
	Engine.time_scale = 3.0
	m.start_cart_surfer()
	var cs = m.minigame
	var bot := OS.get_environment("BOT")
	var shots := []
	var times := [2.0, 6.0, 7.0, 13.5, 20.0]
	var held := ""
	var t0 := Time.get_ticks_msec()
	while m.minigame != null and (Time.get_ticks_msec() - t0) < 60000:
		await process_frame
		if m.minigame == null: break
		var want := ""
		if bot == "lean":
			var sg: Array = cs._segment()
			if sg[2] != null and sg[0] != "straight1" and sg[0] != "end": want = "ui_left" if sg[2]["type"] == "L" else "ui_right"
		if want != held:
			if held != "": Input.action_release(held)
			if want != "": Input.action_press(want)
			held = want
		var secs: float = cs.t / 60.0
		if not times.is_empty() and secs >= times[0]:
			times.pop_front(); var im: Image = root.get_texture().get_image(); im.resize(im.get_width() / 2, im.get_height() / 2); shots.append(im)
			print("T ", snappedf(secs, 0.1), " state ", cs.state, " lives ", cs.lives, " score ", cs.score, " seg ", cs._prev_seg)
	if shots.size() > 0:
		var w: int = shots[0].get_width(); var h: int = shots[0].get_height()
		var sheet := Image.create(w * shots.size(), h, false, Image.FORMAT_RGBA8)
		for i in shots.size():
			var s: Image = shots[i]; s.convert(Image.FORMAT_RGBA8); sheet.blit_rect(s, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
		sheet.save_png(OS.get_cmdline_user_args()[0])
	quit()
