extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	for k in OS.get_cmdline_user_args():
		var d: Dictionary = m.world.sprite(k)
		if d.is_empty(): continue
		var im: Image = d["frames"][0]["image"]
		print("BTN ", k, " size ", im.get_size(), " used ", im.get_used_rect(), " center ", d.get("center"))
		im.save_png("/tmp/claude-0/btn_" + k.get_file() + ".png")
	quit()
