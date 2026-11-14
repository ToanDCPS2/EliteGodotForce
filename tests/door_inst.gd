extends SceneTree
func _init() -> void:
	var w = RomWorld.open_rom("/tmp/p/rom/epf.nds") if RomWorld.has_method("open_rom") else null
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	w = m.world
	var want := OS.get_cmdline_user_args()
	for ov in w.objects:
		for o in w.objects[ov]:
			if str(o["name"]) in want:
				print(ov, " ", o["name"], " id=", o["id"], " dest=", o["dest"], " script=", o["script"], " frames=", o["frames"], " ok0.00=", RomWorld.mission_ok(o, "0.00"))
	quit()
