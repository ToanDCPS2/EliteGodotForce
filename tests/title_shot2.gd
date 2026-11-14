extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	var t := TitleScreen.new(); root.add_child(t)
	await process_frame
	t.setup(w)
	await process_frame
	var out: Image = (t.root.get_child(0) as Sprite2D).texture.get_image()
	for a in t.anims:
		var s: Sprite2D = a["spr"]; var im: Image = s.texture.get_image()
		out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(s.position))
	out.save_png("../previews/title_full.png")
	quit()
