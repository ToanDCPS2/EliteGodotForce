extends SceneTree
## sprsheet.gd -- <out.png> keys... : first-to-last frames of each sprite in a row
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var args := OS.get_cmdline_user_args()
	var rows: Array = []
	var W := 0; var H := 0
	for k in args.slice(1):
		var d: Dictionary = m.world.sprite(k)
		if d.is_empty(): print("NONE ", k); continue
		var fr: Array = d["frames"]
		var cw := 0; var ch := 0
		for f in fr: cw = maxi(cw, f["image"].get_width()); ch = maxi(ch, f["image"].get_height())
		var n := mini(fr.size(), 12)
		rows.append([fr, cw, ch, n])
		print("SPR ", k, " frames=", fr.size(), " looping=", d.get("looping"), " center=", d.get("center"), " canvas=", d.get("canvas"), " durs=", fr.map(func(f): return f["dur_ms"]).slice(0, 12))
		W = maxi(W, cw * n); H += ch + 2
	var out := Image.create(maxi(W, 1), maxi(H, 1), false, Image.FORMAT_RGBA8); out.fill(Color(0.4, 0.6, 0.8))
	var y := 0
	for r in rows:
		for i in r[3]:
			var im: Image = r[0][i]["image"].duplicate(); im.convert(Image.FORMAT_RGBA8)
			out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(i * r[1], y))
		y += r[2] + 2
	out.save_png(args[0]); quit()
