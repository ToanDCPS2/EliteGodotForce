extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	var t := TitleScreen.new(); root.add_child(t)
	await process_frame
	t.setup(w)
	await process_frame
	await process_frame
	var img: Image = (t.root.get_child(0) as Sprite2D).texture.get_image()
	img.save_png("../previews/title_bg.png")
	print("T ok anims=", t.anims.size())
	quit()
