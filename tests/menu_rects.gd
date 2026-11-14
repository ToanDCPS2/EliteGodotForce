extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	print("F title=", m.title != null)
	m.title.start_pressed.emit(); await process_frame; await process_frame
	print("F menu=", m.menu != null, " screen=", m.menu.screen, " btns=", m.menu.btns.size())
	for scr in ["show_missions", "show_erase", "show_minigames", "show_multi", "show_credits", "show_main"]:
		m.menu.call(scr); await process_frame
		print("F ", m.menu.screen); for b in m.menu.btns: print("   ", b.rect, " c=", b.rect.get_center())
		m.menu.snapshot().save_png("../previews/menu_" + m.menu.screen + ".png")
	m.menu.show_missions(); await process_frame
	m.menu.btns[0].cb.call(); await process_frame; await process_frame
	print("F after campaign: menu=", m.menu, " objs=", m.objs.size())
	quit()
