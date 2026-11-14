extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	var t = w.fs.get_by_path("bg/Menus/Title_topscreen2.nbfc"); var s = w.fs.get_by_path("bg/Menus/Title_topscreen2.nbfs")
	var used := {}
	for i in 768: used[s.decode_u16(i * 2) & 0x3FF] = true
	var un := []
	for i in t.size() / 64:
		if not used.has(i): un.append(i)
	print("U tiles=", t.size() / 64, " used=", used.size(), " unreferenced=", un.size(), " first=", un.slice(0, 20))
	var mx := 0
	for k in used: mx = maxi(mx, k)
	print("U max used idx ", mx)
	quit()
