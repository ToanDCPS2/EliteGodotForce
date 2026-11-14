extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	var args := OS.get_cmdline_user_args()
	var out := args[0]; var ims := []
	for k in args.slice(1):
		var d: Dictionary = m.world.sprite(k)
		for f in d.get("frames", []): ims.append(f["image"])
		print("SPR ", k, " frames ", d.get("frames", []).size(), " center ", d.get("center"), " size ", d["frames"][0]["image"].get_size() if d.get("frames", []).size() > 0 else null)
	var w := 0; var h := 0
	for im in ims: w += im.get_width() + 2; h = maxi(h, im.get_height())
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8); sheet.fill(Color(0.3, 0.5, 0.3))
	var x := 0
	for im in ims:
		var c: Image = im.duplicate(); c.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(x, 0)); x += im.get_width() + 2
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out); quit()
