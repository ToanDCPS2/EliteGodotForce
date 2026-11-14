extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	print("cursor kinds:", m.cursor_tex.keys(), " rom_cursor:", m.rom_cursor)
	for t in m.model_touch: print("hover robot:", m._hover_kind(t["rect"].get_center()))
	var kinds := {}
	for o in m.objs:
		if o["rt"] != null: kinds[m._hover_kind(o["node"].position + Vector2(o["dec"]["frames"][0]["image"].get_size()) * 0.5)] = true
	print("kinds seen over objects:", kinds.keys())
	quit()
