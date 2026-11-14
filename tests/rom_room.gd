extends SceneTree
## godot --headless --path . -s tests/rom_room.gd -- rom.nds Prefix out.png [ev]   (prefix 'all' = list/composite all, writes into out dir)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	var w := RomWorld.open(a[0])
	print("opened in %d ms; %d rooms, %d prefixes" % [Time.get_ticks_msec() - t0, w.rooms.size(), w.room_prefixes().size()])
	var ev := int(a[3]) if a.size() > 3 else -1
	var r := w.compose(a[1], ev)
	if r.is_empty(): print("no such room"); quit(); return
	r["image"].save_png(a[2])
	print("%s: placed %d / %d, unresolved %s" % [a[1], r["placed"], r["total"], r["unresolved"]])
	quit()
