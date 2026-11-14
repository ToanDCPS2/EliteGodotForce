extends SceneTree
## Port twin of /tmp/emu/trickscore.py: keyscript in DS frames (KEY:from:to ...), prints states and score at 360.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.start_cart_surfer({})
	var cs = m.minigame
	cs.set_process(false)
	var act := {"LEFT": "ui_left", "RIGHT": "ui_right", "UP": "ui_up", "DOWN": "ui_down", "A": "ui_accept"}
	var holds := []
	for a in OS.get_cmdline_user_args():
		var p := a.split(":"); holds.append([p[0], int(p[1]), int(p[2])])
	var last := ""; var log := []
	for i in int(OS.get_environment("N")) if OS.get_environment("N") != "" else 360:
		for h in holds:
			if i == h[1]: Input.action_press(act[h[0]])
			if i == h[2]: Input.action_release(act[h[0]])
		cs._process(1.0 / 60.0)
		if cs.state != last: log.append("%d:%s" % [i, cs.state]); last = cs.state
		# let Input see the press for exactly one frame as "just pressed"
		Input.flush_buffered_events()
		await process_frame
	print("STATES ", " ".join(log))
	print("SCORE ", cs.score)
	quit()
