extends SceneTree
## Object positions per room (id, name, x, y, frame size) for the emulator driver: /tmp/emu/rooms2/objs.json
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	var out := {}
	for p in w.room_prefixes():
		var ov := -1
		for r in w.rooms:
			if str(r["map"]).begins_with(p + "_map_"): ov = int(r["overlay"]); break
		var lst := []
		for o in w.objects.get(ov, w.objects.get(str(ov), [])):
			var k := w._key_for(o)
			var dec := w.sprite(k) if k != "" else {}
			var bd = dec.get("bounds", [0, 0, 16, 16]) if not dec.is_empty() else [0, 0, 16, 16]
			var cen = dec.get("center", [0, 0]) if not dec.is_empty() else [0, 0]
			if cen == null: cen = [0, 0]
			lst.append({"id": int(o["id"]), "name": str(o["name"]), "x": int(o["x"]), "y": int(o["y"]),
				"bx": int(o["x"]) - int(cen[0]) + int(bd[0]) + int(bd[2]) / 2, "by": int(o["y"]) - int(cen[1]) + int(bd[1]) + int(bd[3]) / 2})
		out[p] = lst
	var f := FileAccess.open("/tmp/emu/rooms2/objs.json", FileAccess.WRITE); f.store_string(JSON.stringify(out)); f.close()
	print("ROOMS ", out.size())
	quit()
