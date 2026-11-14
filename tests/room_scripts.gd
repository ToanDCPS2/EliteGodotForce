extends SceneTree
## godot --headless --path . -s tests/room_scripts.gd -- rom.nds [Prefix]
## Loads every scripted object of a room (or all rooms), fires CREATED and TOUCHED with the native GameApi, reports events/unknowns.
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var w := RomWorld.open(a[0])
	var chunks := EpfArc.parse(w.rom.file("chunks.arc"))
	var system := chunks.get_chunk("system")
	var api := GameApi.new()
	var prefixes: Array = [a[1]] if a.size() > 1 else w.room_prefixes()
	var ran := 0; var missing := 0; var errs := 0; var by_fn := {}
	for p in prefixes:
		var ov := -1
		for r in w.rooms:
			if str(r["map"]).begins_with(p + "_map_"): ov = int(r["overlay"]); break
		for o in w.objects.get(ov, w.objects.get(str(ov), [])):
			var sc = o["script"]
			if sc == null: continue
			var stem := str(sc).get_file().get_basename()
			var cb := chunks.get_chunk(stem)
			if cb.is_empty(): missing += 1; continue
			var rt := ObjectRuntime.create({}, system, cb, api, int(o["id"]), str(o["name"]))
			for reason in ["CREATED", "TOUCHED"]:
				var before := api.events.size()
				rt.fire(api, reason)
				ran += 1
				for e in api.events.slice(before): by_fn[e["fn"]] = by_fn.get(e["fn"], 0) + 1
	print("fired %d event runs, missing chunks %d" % [ran, missing])
	print("events by call: ", by_fn)
	print("unknown _util calls: ", api.unknown_calls)
	quit()
