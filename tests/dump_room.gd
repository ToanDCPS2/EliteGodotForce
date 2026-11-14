extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.set_mission("0.00")
	for rn in OS.get_cmdline_user_args():
		m.load_room(rn); await process_frame
		print("== ", rn)
		for o in m.objs:
			var d: Dictionary = o["data"]
			var fr: Array = o["dec"]["frames"]
			var sizes := []; var full := []
			for f in fr: sizes.append((f["image"] as Image).get_used_rect().size); full.append((f["image"] as Image).get_size())
			print("  ", d["name"], " dest=", d.get("dest"), " spr=", d.get("sprite"), " pos=", o["node"].position, " vis=", o["node"].visible, " frame=", o["frame"], " n=", fr.size(), " sz=", sizes.slice(0,6), " full=", full.slice(0,3), " sdir=", d.get("sprite_dir"), " fr=", d.get("frames"), " flags=", d.get("flags"), " unk=", d.get("unk"), " ns=", d.get("nstates"), " xy=", d.get("x"), ",", d.get("y"), " script=", d.get("script"), " ev=", d.get("event"), " w8=", d.get("w8"))
	quit()
