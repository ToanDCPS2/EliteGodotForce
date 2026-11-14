extends SceneTree
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	var ch := EpfArc.parse(w.rom.file("chunks.arc"))
	var n := 0
	for e in ch.entries:
		var nm := str(e)
		if nm.to_lower().contains("m1c1") or nm.to_lower().contains("cutscene") or nm.to_lower().contains("outro") or nm.to_lower().contains("screen") or nm.to_lower().contains("mission"):
			print("CH ", nm); n += 1
	print("TOTAL ", ch.entries.size())
	quit()
