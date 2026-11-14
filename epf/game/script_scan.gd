extends RefCounted
## Static scan of a compiled script for object ids it passes to AddItem / DelItem / SetSpawn (as `_id.<Name>`).
## Used to decide which stacked mission-variant objects exist at room load (those only ever *added* start absent).

static func scan(chunk: PackedByteArray) -> Dictionary:
	var out := {"add": [], "del": []}
	if chunk.is_empty(): return out
	var fn := LuaVM.load_chunk(chunk)
	if fn == null: return out
	_walk(fn.p, out)
	return out

static func _walk(p: LuaVM.Proto, out: Dictionary) -> void:
	var reg := {}
	var pend_fn := ""; var pend_reg := -1
	for ins in p.code:
		var op := int(ins) & 63
		var a := (int(ins) >> 6) & 255
		var b := (int(ins) >> 23) & 511
		var c := (int(ins) >> 14) & 511
		if op == 5:   # GETGLOBAL
			var bx := (int(ins) >> 14) & 0x3ffff
			reg[a] = str(p.consts[bx]) if bx < p.consts.size() else ""
		elif op == 6: # GETTABLE
			var key := ""
			if c >= 256 and c - 256 < p.consts.size(): key = str(p.consts[c - 256])
			var base: String = reg.get(b, "")
			if base == "_util":
				reg[a] = "util:" + key
				if key == "AddItem" or key == "DelItem" or key == "SetSpawn": pend_fn = key; pend_reg = a
			elif base == "_id":
				reg[a] = "id:" + key
				if pend_reg >= 0 and a > pend_reg:
					if pend_fn == "AddItem": out["add"].append(key)
					elif pend_fn == "DelItem": out["del"].append(key)
					elif pend_fn == "SetSpawn": out["spawn"] = out.get("spawn", []) + [key]
			else: reg[a] = key
		elif op == 28: # CALL
			if a == pend_reg: pend_reg = -1; pend_fn = ""
	for sub in p.protos: _walk(sub, out)
