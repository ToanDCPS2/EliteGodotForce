extends SceneTree
## First boot: with no .epf anywhere, the setup screen shows; EPF_SETUP_ROM drives it; then the title must appear.
func _init() -> void:
	root.size = Vector2i(1152, 648)
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png("/tmp/claude-0/setup_0.png")
	var t0 := Time.get_ticks_msec()
	while m.world == null and Time.get_ticks_msec() - t0 < 120000: await create_timer(0.5).timeout
	print("BOOTED ", m.world != null, " in ", Time.get_ticks_msec() - t0, " ms; rooms ", m.world.rooms.size() if m.world else 0)
	await create_timer(2.0).timeout
	root.get_texture().get_image().save_png("/tmp/claude-0/setup_1.png")
	quit()
