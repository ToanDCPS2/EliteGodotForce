extends SceneTree
## Port side of the DS door map: in every room (mission EPF_MISSION, default 0.00) tap the centre of each visible
## door's DS hit box once (as a player would), then report where the port ends up. Output: DOOR <room> <door> -> <dest|STAYED|...>
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	var mis: String = OS.get_environment("EPF_MISSION")
	if mis == "": mis = "0.00"
	m._set_lang("en"); m.set_mission(mis)
	var only: PackedStringArray = OS.get_cmdline_user_args()
	var rooms: Array = []
	for p in m.world.room_prefixes():
		var ps := str(p)
		if ps.begins_with("Jetpack") or ps.begins_with("SnowCat") or ps.begins_with("Catalog") or ps.begins_with("LevelSelect") or ps.contains("Test"): continue
		if only.size() > 0 and not ps in only: continue
		rooms.append(ps)
	for r in rooms:
		m.load_room(r); await process_frame
		var names := []
		for o in m.objs:
			if RomWorld.is_door(o["data"]) and o["node"].visible: names.append(str(o["data"]["name"]))
		for dn in names:
			m.load_room(r); await process_frame
			if m.conv != null: m.conv = null
			m.dialog.visible = false
			var t = null
			for o in m.objs:
				if str(o["data"]["name"]) == dn and o["node"].visible: t = o
			if t == null: print("DOOR ", r, " ", dn, " -> HIDDEN"); continue
			var img: Image = t["dec"]["frames"][t["frame"]]["image"]
			var ur := img.get_used_rect()
			var sz := Vector2(img.get_size())
			if ur.size.x <= 2 or ur.size.y <= 2: sz = Vector2(64, 64)
			var pt: Vector2 = t["node"].position + sz * 0.5
			if m.loop_x: pt.x = fposmod(pt.x, m.room_size.x)
			m._touch_at(pt)
			var res := "STAYED"
			for i in 300:
				await process_frame
				if m.room_prefix != r: res = m.room_prefix; break
			if res == "STAYED":
				var said := ""
				if m.dialog.visible: said = " (says something)"
				res += said
			print("DOOR ", r, " ", dn, " -> ", res)
	print("DONE")
	quit()
