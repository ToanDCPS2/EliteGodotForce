extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	var top := EpfNbfc.load_bg(w, "bg/Menus/Title_topscreen2")
	var bot := EpfNbfc.load_bg(w, "bg/Menus/Title_bottomscreen")
	for k in ["UI/MainMenu/Title_JetPackguy", "UI/MainMenu/Title_GreenPuffle", "UI/MainMenu/Title_Bottom", "UI/MainMenu/Title_BttnPlay_up", "UI/MainMenu/Title_BttnPlay_down", "UI/MainMenu/Title_BttnDGamer_up", "UI/MainMenu/Title_BttnMicrophone_up"]:
		var d := w.sprite(k)
		print(k, " frames=", d["frames"].size(), " dur0=", d["frames"][0].get("dur_ms"), " size=", d["frames"][0]["image"].get_size(), " center=", d.get("center"))
	var out := Image.create(256, 384, false, Image.FORMAT_RGBA8)
	out.blit_rect(top, Rect2i(0, 0, 256, 192), Vector2i(0, 0))
	out.blit_rect(bot, Rect2i(0, 0, 256, 192), Vector2i(0, 192))
	for k in ["UI/MainMenu/Title_JetPackguy", "UI/MainMenu/Title_GreenPuffle"]:
		var im: Image = w.sprite(k)["frames"][0]["image"]
		out.blend_rect(im, Rect2i(0, 0, 256, 192), Vector2i(0, 0))
	for k in ["UI/MainMenu/Title_Bottom", "UI/MainMenu/Title_BttnPlay_up", "UI/MainMenu/Title_BttnDGamer_up"]:
		var im2: Image = w.sprite(k)["frames"][0]["image"]
		out.blend_rect(im2, Rect2i(0, 0, im2.get_width(), im2.get_height()), Vector2i(0, 192))
	out.save_png("../previews/title_comp.png")
	quit()
