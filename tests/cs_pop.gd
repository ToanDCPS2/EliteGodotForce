extends SceneTree
## Lean through the first turn and record the points pop-up position/size each few frames after the exit.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.start_cart_surfer({})
	var cs = m.minigame
	cs.set_process(false)
	var held := ""; var shot := false
	for i in 560:
		var sg: Array = cs._segment()
		var want := ""
		if sg[2] != null and sg[0] != "straight1": want = "ui_left" if sg[2]["type"] == "L" else "ui_right"
		if want != held:
			if held != "": Input.action_release(held)
			if want != "": Input.action_press(want)
			held = want
		cs._process(1.0 / 60.0)
		if cs.pop.visible and int(cs.t) % 6 == 0:
			print("POP t=", int(cs.t), " pos ", ((cs.pop.position - cs.origin) / cs.u).round(), " size ", (cs.pop.size / cs.u).round())
			if not shot and int(cs.t) >= 450:
				await process_frame; await process_frame
				var im: Image = root.get_texture().get_image(); im.save_png(OS.get_cmdline_user_args()[0]); shot = true
	print("SCORE ", cs.score)
	quit()
