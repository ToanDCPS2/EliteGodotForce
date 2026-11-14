extends SceneTree
## For the given object scripts, list the event reasons and API calls they reference (identifiers only).
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	var chunks := EpfArc.parse(w.rom.file("chunks.arc"))
	for stem in OS.get_cmdline_user_args():
		var fn := LuaVM.load_chunk(chunks.get_chunk(stem))
		if fn == null: print("MISSING ", stem); continue
		var ids := {}
		_walk(fn.p, ids)
		var r := []; var c := []
		for k in ids:
			if k == k.to_upper() and k.length() > 3 and not k.begins_with("M1"): r.append(k)
			elif k[0] == k[0].to_upper() and not k.begins_with("M1") and not " " in k and k.length() < 30: c.append(k)
		r.sort(); c.sort()
		print(stem, "\n  REASONS ", r, "\n  CALLS ", c)
	quit()
func _walk(p, ids: Dictionary) -> void:
	for k in p.consts:
		if k is String: ids[k] = true
	for q in p.protos: _walk(q, ids)
