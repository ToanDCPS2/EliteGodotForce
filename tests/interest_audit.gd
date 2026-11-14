extends SceneTree
## For each room: scripted objects, how many have interest bit1 (touchable) after CREATED, and how many dest-door objects lack it.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	for rp in ["Town0", "Dock0", "Beach0", "CoffeeShop0", "GiftShop0", "Plaza0", "Forest0", "Dojo0", "Attic0"]:
		m.load_room(rp); await process_frame
		var n := 0; var t := 0; var nodest := 0; var doors := 0; var doors_ok := 0
		for o in m.objs:
			var d: Dictionary = o["data"]
			var id := int(d.get("id", 0)); var mask := int(m.api.interests.get(id, 0))
			if o["rt"] != null: n += 1; if mask & 2: t += 1
			var dst = d.get("dest")
			if dst != null and str(dst).to_lower() != "none":
				doors += 1; if mask & 2: doors_ok += 1
		print("%s scripted=%d touchable=%d doors=%d doors_touchable=%d" % [rp, n, t, doors, doors_ok])
	quit()
