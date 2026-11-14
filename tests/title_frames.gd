extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for k in ["UI/MainMenu/Title_JetPackguy", "UI/MainMenu/Title_Bottom", "UI/MainMenu/Title_BttnPlay_up"]:
		var d := w.sprite(k); var s: String = k + ":"
		for i in d["frames"].size():
			var im: Image = d["frames"][i]["image"]; var n := 0
			var r := im.get_used_rect()
			s += " %d[%s dur%d]" % [i, r, d["frames"][i].get("dur_ms")]
		print(s)
	quit()
