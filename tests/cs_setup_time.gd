extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	var t0 := Time.get_ticks_msec()
	m.start_cart_surfer({})
	print("SETUP_MS ", Time.get_ticks_msec() - t0)
	for i in 30: await process_frame
	print("FRAMES_OK t=", m.minigame.t if m.minigame else -1)
	quit()
