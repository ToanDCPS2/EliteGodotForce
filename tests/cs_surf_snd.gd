extends SceneTree
## Same inputs as the DeSmuME surf check (DS frames from the game start): up 130, left 180-220, right 250-290, up 300.
## Prints state changes and SFX so they can be lined up with the DS log.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.start_cart_surfer({})
	var cs = m.minigame
	cs.set_process(false)
	var plan := [[130, 134, "ui_up"], [180, 220, "ui_left"], [250, 290, "ui_right"], [300, 304, "ui_up"]]
	var last := ""
	for i in 400:
		await process_frame
		var f := int(cs.t) + 33
		for p in plan:
			var on: bool = f >= p[0] and f < p[1]
			if on and not Input.is_action_pressed(p[2]): Input.action_press(p[2])
			if not on and f >= p[1] and f < p[1] + 3 and Input.is_action_pressed(p[2]): Input.action_release(p[2])
		cs._process(1.0 / 60.0)
		if cs.state != last: print("F ", f, " ST ", cs.state); last = cs.state
	quit()
