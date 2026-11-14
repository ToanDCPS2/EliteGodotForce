extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var w := RomWorld.open(a[0])
	for p in ["Dock0", "Beach0", "Iceberg0", "TallestMountainTop0", "SnowCat1", "Town0", "Attic0"]:
		var r := w.compose_layers(p)
		var bgs: Array = r.get("bgs", [])
		var info := []
		for b in bgs: info.append("%s par=%s" % [b["image"].get_size(), b["par"]])
		print(p, " fg=", r["image"].get_size(), " bgs=", info)
		if p == "Dock0":
			r["image"].save_png("../previews/dock_fg.png")
			if bgs.size() > 0: bgs[0]["image"].save_png("../previews/dock_bg.png")
	quit()
