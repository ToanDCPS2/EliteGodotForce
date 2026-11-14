extends SceneTree
## Real-time path: game _process runs normally; hold the Left arrow as a real key event on the opening straight.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.start_cart_surfer({})
	var cs = m.minigame
	var last := ""; var pressed := false
	var t0 := Time.get_ticks_msec()
	while m.minigame != null and Time.get_ticks_msec() - t0 < 9000:
		await process_frame
		if not pressed and cs.t >= 140.0:
			var ev := InputEventKey.new(); ev.keycode = KEY_LEFT; ev.physical_keycode = KEY_LEFT; ev.pressed = true
			Input.parse_input_event(ev); pressed = true; print("PRESS at t=", int(cs.t))
		if cs.state != last: print("ST ", int(cs.t), " ", cs.state, " lean_t ", int(cs.lean_t), " seg ", cs._prev_seg); last = cs.state
		if cs.t > 330.0: break
	quit()
