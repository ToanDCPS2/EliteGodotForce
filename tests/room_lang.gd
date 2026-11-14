extends SceneTree
## Composes every room in en / fr / es and reports the rooms whose images differ between languages (where signs are).
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	var prefixes: Array = w.room_prefixes()
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	for p in prefixes:
		var ims := {}
		for l in ["en", "fr", "es"]:
			w.set_lang(l)
			var r: Dictionary = w.compose(p, 0)
			if r.is_empty() or not r.has("image"): continue
			ims[l] = r["image"]
		if ims.size() < 3: continue
		var d1 := _diff(ims["en"], ims["fr"]); var d2 := _diff(ims["en"], ims["es"])
		print("ROOM ", p, " en/fr ", d1, " en/es ", d2)
		if out != "" and (d1 > 0 or d2 > 0):
			for l in ims: (ims[l] as Image).save_png(out + "/%s_%s.png" % [p, l])
	quit()

func _diff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size(): return -1
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			if a.get_pixel(x, y) != b.get_pixel(x, y): n += 1
	return n
