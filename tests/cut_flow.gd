extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	print("title cut=", m.cutscene != null)
	m.title.start_pressed.emit(); await process_frame; await process_frame
	print("after title start: menu=", m.menu != null, " cut=", m.cutscene != null, " screen=", m.menu.screen if m.menu else "")
	await create_timer(0.3).timeout; m.cutscene._end(); await process_frame; await process_frame; print("menu after movie=", m.menu != null); m.menu.show_missions(); await process_frame
	m.menu.btns[0].cb.call(); await process_frame; await process_frame
	print("after Start btn: menu=", m.menu != null, " cut=", m.cutscene != null, " fin=", m.cutscene.fin if m.cutscene else "-", " frame=", m.cutscene.flc.frame_no if m.cutscene else -1)
	await create_timer(1.0).timeout
	print("1s later: cut=", m.cutscene != null, " frame=", m.cutscene.flc.frame_no if m.cutscene else -1)
	quit()
