extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var w = m.world
	var prefixes: Array = w.room_prefixes()
	var lower := {}
	for p in prefixes: lower[str(p).to_lower()] = p
	var tot := 0; var bad := 0
	for p in prefixes:
		var ov := -1
		for r in w.rooms:
			if str(r["map"]).begins_with(str(p) + "_map_"): ov = int(r["overlay"]); break
		var objs: Array = w.objects.get(ov, w.objects.get(str(ov), []))
		for o in objs:
			var d = o.get("dest")
			if d == null: continue
			tot += 1
			var issues := []
			if str(d).to_lower() == "none": issues.append("dest=none")
			elif not lower.has(str(d).to_lower()): issues.append("dest?" + str(d))
			if not RomWorld.visible(o, 0): issues.append("eventfilt(%d)" % int(o["event"]))
			if not RomWorld.mission_ok(o, "1.01"): issues.append("notin1.01")
			var k: String = w._key_for(o)
			if k == "": issues.append("nosprite")
			if o["script"] == null: issues.append("noscript")
			print("%s %s#%d -> %s  key=%s  frames=%s  %s" % [p, o["name"], int(o["id"]), str(d), k, str(o["frames"]), ",".join(issues)])
	print("TOTAL doors ", tot)
	quit()
