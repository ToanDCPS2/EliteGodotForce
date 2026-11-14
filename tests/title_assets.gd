extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for k in ["bg/Menus/Title_topscreen2", "bg/Menus/Title_bottomscreen", "UI/MainMenu/Title_BttnPlay", "UI/MainMenu/Title_BttnPlay_up", "UI/MainMenu/Title_BttnMicrophone", "UI/MainMenu/Title_JetPackguy", "UI/MainMenu/Title_GreenPuffle", "UI/MainMenu/Title_Bottom", "UI/MainMenu/MainMenu_1player", "UI/MainMenu/MainMenu_Options"]:
		var d := w.sprite(k)
		if d.is_empty(): print("MISSING ", k); continue
		var f: Dictionary = d["frames"][0]
		print(k, " frames=", d["frames"].size(), " size=", f["image"].get_size(), " center=", d.get("center"))
		f["image"].save_png("../previews/t_" + k.get_file() + ".png")
	quit()
