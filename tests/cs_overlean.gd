extends SceneTree
## Hold left on the opening straight and report when the cart tips and crashes (DS: +85 tip, +114 crash).
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.start_cart_surfer({})
	var cs = m.minigame
	var pressed := -1.0; var last := ""
	while m.minigame != null and cs.t < 300.0:
		await process_frame
		if pressed < 0 and cs.t >= 132.0 and cs.state == "IDLE": Input.action_press("ui_left"); pressed = cs.t
		if cs.state != last: print("ST ", int(cs.t), " ", cs.state, " (+", int(cs.t - pressed) if pressed >= 0 else 0, ")"); last = cs.state
	Input.action_release("ui_left")
	quit()
