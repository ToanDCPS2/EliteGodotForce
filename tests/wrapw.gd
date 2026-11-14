extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var f = EpfFont.load_font(m.world.fs, "fonts/bigUI.fnt")
	for t in ["from the inventory panel below and then", "from the inventory panel below and then touch", "To give the postcard, select it from"]:
		print("W ", f.line_width(t), " ", t)
	quit()
