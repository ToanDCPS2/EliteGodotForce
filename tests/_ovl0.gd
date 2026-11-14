extends SceneTree
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	print("INFO ", w.rom.overlay_info(0))
	var d: PackedByteArray = w.rom.overlay_data(0)
	var s := ""
	for j in range(0x12b400, 0x12b8c0):
		var c := d[j]
		s += char(c) if c >= 32 and c < 127 else "."
	print("STR ", s)
	quit()
