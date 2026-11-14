extends SceneTree
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	var ch := EpfArc.parse(w.rom.file("chunks.arc"))
	var hits := []
	var pre := ["M1C1", "M1C2", "M1C3", "M2C3"]
	var mids := ["", "_Outro", "_Intro", "_End", "_Ending", "_Cutscene", "_CS", "_MissionEnd", "_Complete", "_Map", "_MapMarking", "_GarySit", "_Dot", "_DotBarrel", "_Lighthouse", "_Final", "_LastCutscene"]
	var sufs := ["", "_MCS", "MCS", "_CS", "CS"]
	for p in pre:
		for m in mids:
			for s in sufs:
				var n: String = p + m + s
				if ch.get_chunk(n).size() > 0: hits.append(n)
	for n in ["system", "Screen", "cutscene", "Cutscene", "MissionEnd", "mission_end", "EndMission", "MissionComplete", "DL_OutroCS", "DL_IntroCS", "Outro", "Intro", "MapMarking", "credits", "Credits"]:
		if ch.get_chunk(n).size() > 0: hits.append(n)
	print("HITS ", hits)
	quit()
