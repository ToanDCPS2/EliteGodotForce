extends SceneTree
## Loads every story room under mission 1.01, lists its doors, then walks through each exit door and checks the room changed.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	var mis: String = OS.get_environment("EPF_MISSION")
	m.set_mission(mis)
	var rooms0 := ["Town0","CoffeeShop0","BookRoom0","NightClub0","Lounge0","GiftShop0","GiftOffice0","Dock0","Beach0","Lighthouse0","Beacon0","SkiVillage0","Lodge0","Attic0","SnowForts0","Plaza0","PizzaParlor0","PetShop0","Stage0","Pool0","BoilerRoom0","SkiHill0","SportShop0","IceRink0","Forest0","Dojo0","MineExterior0","CaveInterior0","WildernessClearing0","Iceberg0"]
	var rooms: Array = []
	for p in m.world.room_prefixes():
		var ps := str(p)
		if ps.begins_with("Jetpack") or ps.begins_with("SnowCat") or ps.begins_with("Catalog") or ps.begins_with("LevelSelect") or ps.contains("Test"): continue
		rooms.append(ps)
	var fails := 0; var okc := 0
	for r in rooms:
		m.load_room(r); await create_timer(0.1).timeout
		if m.room_prefix != r: print("NOROOM ", r); continue
		var doors := []
		for o in m.objs:
			if RomWorld.is_door(o["data"]): doors.append([o["data"]["name"], str(o["data"]["dest"]), o.has("door"), o["rt"] != null, o["node"].visible])
		var nost := 0
		for d in doors:
			if not d[2]: nost += 1
		print(r, " doors=", doors.size(), " nostates=", nost)
		for d in doors:
			if d[1].to_lower() == "none": print("   ", d[0], " -> none (script only)"); continue
			m.load_room(r); await create_timer(0.05).timeout
			var target = null
			for o in m.objs:
				if o["data"]["name"] == d[0] and o["node"].visible: target = o
			if target == null: print("   ", d[0], " HIDDEN"); continue
			m.dialog.visible = false
			var img: Image = target["dec"]["frames"][target["frame"]]["image"]
			var used := img.get_used_rect()
			var pt: Vector2 = target["node"].position + Vector2(used.get_center())
			var found := false
			for yy in range(used.position.y, used.end.y, 3):
				for xx in range(used.position.x, used.end.x, 3):
					if img.get_pixel(xx, yy).a > 0.5: pt = target["node"].position + Vector2(xx, yy); found = true; break
				if found: break
			m._touch_at(pt)
			for k in 20:
				await create_timer(0.06).timeout
				if m.room_prefix != r: break
			var res := "OK" if m.room_prefix.to_lower() == d[1].to_lower() else ("STAY dlg=" + str(m.dialog.visible) + " " + str(m.dialog.lines))
			if res == "OK": okc += 1
			else: fails += 1
			print("   ", d[0], " -> ", d[1], " states=", d[2], " script=", d[3], " : ", res)
	print("DONE ok=", okc, " fail=", fails)
	quit()
