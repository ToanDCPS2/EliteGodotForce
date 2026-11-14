extends SceneTree
## Static map of mission-related script calls: which object scripts call SetObjective / StartMission / EndMission /
## StartMiniGame, and which mission codes or vars they test. Prints identifiers only.
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	var chunks := EpfArc.parse(w.rom.file("chunks.arc"))
	var by_obj := {}
	for ov in w.objects:
		for o in w.objects[ov]:
			var sc = o["script"]
			if sc == null: continue
			var stem := str(sc).get_file().get_basename()
			var cb := chunks.get_chunk(stem)
			if cb.is_empty(): continue
			var fn := LuaVM.load_chunk(cb)
			if fn == null: continue
			var found := {}
			_walk(fn.p, found)
			if not found.is_empty(): by_obj[stem] = found
	var keys := by_obj.keys(); keys.sort()
	for k in keys: print("OBJ ", k, " ", by_obj[k])
	quit()

const WANT := ["SetObjective", "StartMission", "EndMission", "StartMiniGame", "GetMission", "IsMission", "GetMissionCode", "MissionComplete"]
func _walk(p, found: Dictionary) -> void:
	for c in p.consts:
		var s := str(c)
		if s in WANT: found[s] = true
		elif s.begins_with("M1") or s.begins_with("MISSION") or s.begins_with("m1"): found[s] = true
	for q in p.protos: _walk(q, found)
