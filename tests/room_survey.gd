extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for p in w.room_prefixes():
		var r := w.compose_layers(p)
		if r.is_empty(): print(p, " EMPTY"); continue
		var im: Image = r["image"]
		var W := im.get_width(); var H := im.get_height()
		# seam score: mean colour diff between last column and first column vs. between adjacent interior columns
		var seam := 0.0; var adj := 0.0; var n := 0
		for y in range(0, H, 2):
			var a := im.get_pixel(0, y); var b := im.get_pixel(W - 1, y); var c := im.get_pixel(W / 2, y); var d := im.get_pixel(W / 2 + 1, y)
			if a.a < 0.5 or b.a < 0.5: continue
			seam += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b); adj += absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b); n += 1
		print("%s %dx%d bgs=%d seam=%.3f adj=%.3f" % [p, W, H, r.get("bgs", []).size(), seam / maxf(n, 1), adj / maxf(n, 1)])
		im.save_png("../previews/rooms/%s.png" % p)
	quit()
