extends SceneTree
## which ARM9 overlays mention the jigsaw (sprite keys / bg names): identifiers only
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	for i in w.rom.overlay_count():
		var d: PackedByteArray = w.rom.overlay_data(i)
		var info: Dictionary = w.rom.overlay_info(i)
		for pat in ["MapPiece", "Jigsaw", "rotateHandle", "SnowCatPiece"]:
			var p: PackedByteArray = str(pat).to_ascii_buffer()
			var hits := []
			var j := _find(d, p, 0)
			while j >= 0 and hits.size() < 4:
				hits.append("0x%x" % (int(info.get("ram", 0)) + j)); j = _find(d, p, j + 1)
			if not hits.is_empty(): print("OVL ", i, " ram 0x%x size %d " % [int(info.get("ram", 0)), d.size()], pat, " ", hits)
	quit()
func _find(d: PackedByteArray, p: PackedByteArray, from: int) -> int:
	var n := p.size()
	for j in range(from, d.size() - n):
		if d[j] == p[0] and d.slice(j, j + n) == p: return j
	return -1
