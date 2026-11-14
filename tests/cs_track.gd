extends SceneTree
## Dump the port's track (segment, frame) for DS frames 0..N (t = i - 17), no input.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.start_cart_surfer({})
	var cs = m.minigame
	cs.set_process(false)
	var out := []
	for i in int(OS.get_cmdline_user_args()[0]):
		cs._process(1.0 / 60.0)
		var sg: Array = cs._segment()
		out.append([i, sg[0], sg[1]])
	var f := FileAccess.open("/tmp/claude-0/cmp/pt_track.json", FileAccess.WRITE); f.store_string(JSON.stringify(out)); f.close()
	quit()
