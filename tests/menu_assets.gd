extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for b in ["bg/Menus/Menus_bottom", "bg/Cutscenes/MissionIntroTop", "bg/CreditsTop", "bg/CreditsBottom", "bg/Menus/MultiplayerMenuTop"]:
		var im := EpfNbfc.load_bg(w, b)
		print("M ", b, " ", im != null)
		if im != null: im.save_png("../previews/m_" + b.get_file() + ".png")
	for k in ["UI/MainMenu/MainMenu_1player_up", "UI/MainMenu/MainMenu_1player_down", "UI/MainMenu/MainMenu_2player_up", "UI/MainMenu/MainMenu_Options_up", "UI/MainMenu/creditsBttn_up", "UI/MainMenu/MainMenu_DGamer_up", "UI/arrowBack_up", "UI/buttonBig_up", "UI/buttonMedium_up"]:
		var d := w.sprite(k)
		if d.is_empty(): print("M MISSING ", k); continue
		var f: Dictionary = d["frames"][0]
		print("M ", k, " frames=", d["frames"].size(), " rect=", f["image"].get_used_rect(), " center=", d.get("center"))
	quit()
