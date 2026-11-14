extends SceneTree
func _init():
	var rom := NdsRom.open(OS.get_cmdline_user_args()[0])
	for k in rom.files_by_path.keys():
		var l: String = k.to_lower()
		if "cut" in l or "intro" in l or "movie" in l or "flash" in l or "fade" in l or "story" in l or "comic" in l or "scene" in l: print(k, " ", rom.file(k).size())
	print(rom.files_by_path.size())
	quit()
