class_name OverlayMeta
extends RefCounted
## Native port of tools/epf_rooms.py + tools/epf_objects.py: reads room level records and object instance tables
## straight out of the ARM9 overlays of the user's ROM. Output matches the Python tools' rooms.json / objects.json.

static func _cstr(b: PackedByteArray, base: int, p: int, min_len := 1, max_len := 96):
	var o := p - base
	if o < 0 or o >= b.size(): return null
	var e := o
	var lim := mini(b.size(), o + max_len)
	while e < lim and b[e] != 0: e += 1
	if e >= lim or e - o < min_len: return null
	for i in range(o, e):
		if b[i] < 32 or b[i] >= 127: return null
	return b.slice(o, e).get_string_from_ascii()

## Returns Array of {overlay, map, width, height, parallax:[x,y], tileset}
static func scan_rooms(rom: NdsRom) -> Array:
	var rooms: Array = []
	var ov0 := rom.overlay_data(0)
	var base0: int = rom.overlay_info(0)["ram_address"]
	for i in rom.overlay_count():
		var inf := rom.overlay_info(i)
		if inf["ram_size"] < 64: continue
		var b := rom.overlay_data(i)
		var base: int = inf["ram_address"]
		var off := 0
		while off + 24 < b.size():
			var w := b.decode_u32(off)
			if w >= base and w < base + b.size():
				var name = _cstr(b, base, w, 2, 90)
				if name != null and name.begins_with("levels/") and name.ends_with(".mpb"):
					var w1 := b.decode_u32(off + 4)
					var dims := b.decode_u32(off + 16)
					var par := b.decode_u32(off + 20)
					var ts = null
					if w1 >= base0 and w1 < base0 + ov0.size() - 8:
						var o := w1 - base0
						ts = _cstr(ov0, base0, ov0.decode_u32(o + 4), 2, 90)
						if ts == null: ts = _cstr(ov0, base0, ov0.decode_u32(o), 2, 90)
					rooms.append({"overlay": inf["id"], "map": name.split("/")[1], "width": dims & 0xFFFF, "height": dims >> 16,
						"parallax": [par & 0xFFFF, par >> 16], "tileset": ts,
						"layer": (b.decode_u32(off + 32) >> 16) & 0xFF, "scroll": b.decode_u32(off + 24),
						"wrap": b[off + 35]})   # 1 = camera wraps horizontally (ARM 0x2114cd8 reads record+0x23; DeSmuME-checked)
			off += 4
	return rooms

static func _objdef(b: PackedByteArray, base: int, p: int):
	if (p & 3) != 0: return null
	var o := p - base
	if o < 0 or o + 36 > b.size(): return null
	var nm = _cstr(b, base, b.decode_u32(o), 2)
	if nm == null: return null
	var w7 := b.decode_u32(o + 28)
	# Door/exit defs keep a pointer to the destination room name here ("Dock0", "GIFTSHOP0", "none"); everything else packs event<<16 | prio.
	var dest = null
	var event_v := w7 >> 16
	var prio_v := w7 & 0xFFFF
	if w7 >= 0x2000000:
		dest = _cstr(b, base, w7, 1)
		event_v = 0
		prio_v = 0
	return {"name": nm, "id": b.decode_u32(o + 4), "flags": b.decode_u32(o + 8), "dest": dest,
		"frames": _cstr(b, base, b.decode_u32(o + 12), 1, 1024), "nstates": b.decode_u32(o + 16),
		"sprite_dir": _cstr(b, base, b.decode_u32(o + 20)), "script": _cstr(b, base, b.decode_u32(o + 24)),
		"event": event_v, "prio": prio_v, "w8": b.decode_u32(o + 32),
		"locked": b.decode_u32(o + 40) if o + 44 <= b.size() else 0}   # doors: exit starts locked (DS field_84, checked in DeSmuME)

## Returns Dictionary overlay_id(String) -> Array of object instance dictionaries
static func scan_objects(rom: NdsRom) -> Dictionary:
	var res := {}
	for i in rom.overlay_count():
		var inf := rom.overlay_info(i)
		if inf["id"] == 0 or inf["ram_size"] < 64: continue
		var b := rom.overlay_data(i)
		var base: int = inf["ram_address"]
		var out: Array = []
		var seen := {}
		var n := b.size() / 4
		var wi := 0
		while wi + 4 <= n:
			var j := wi
			var run: Array = []
			while j + 4 <= n:
				var x := b.decode_s32((j + 1) * 4)
				var y := b.decode_s32((j + 2) * 4)
				var p := b.decode_u32((j + 3) * 4)
				if p < base or p >= base + b.size() or absi(x) > 8192 or absi(y) > 8192: break
				var d = _objdef(b, base, p)
				if d == null: break
				d["x"] = x; d["y"] = y; d["unk"] = b.decode_u32(j * 4); d["at"] = base + j * 4
				run.append(d)
				j += 4
			if not run.is_empty():
				for r in run:
					if not seen.has(r["at"]):
						seen[r["at"]] = true; out.append(r)
				wi = j
			else:
				wi += 1
		if not out.is_empty(): res[str(inf["id"])] = out
	return res

## The map screen's data, all from overlay 0:
##  "pads":  {level name: Vector2}   the 12 places on the LevelSelect map (instance table: id, x, y, def)
##  "links": {level name: [neighbour level names]}   which pads have a walking path between them
##  "lists": [[{room, level}, ...], ...]   one room list per story stage; a room tagged with a level name is
##           the room that pad leads to in that stage (the pad is absent from the stage when no room has it)
static func scan_map(rom: NdsRom) -> Dictionary:
	var b := rom.overlay_data(0)
	var base: int = rom.overlay_info(0)["ram_address"]
	var out := {"pads": {}, "links": {}, "lists": []}
	var n := b.size() - 4
	# level defs: 76-byte records starting with a "level_*" name; neighbours are words 7..9
	var defs := {}
	var off := 0
	while off + 76 <= n:
		var nm = _cstr(b, base, b.decode_u32(off), 7, 24)
		if nm != null and str(nm).begins_with("level_") and _cstr(b, base, b.decode_u32(off + 20), 8, 24) == "UI/LevelSelect/":
			var nb: Array = []
			for j in 3:
				var s2 = _cstr(b, base, b.decode_u32(off + 28 + j * 4), 4, 24)
				if s2 != null and str(s2).begins_with("level_"): nb.append(str(s2).substr(6))
			defs[base + off] = str(nm).substr(6)
			out["links"][str(nm).substr(6)] = nb
			off += 76
		else:
			off += 4
	# instances: (id, x, y, pointer to a level def)
	off = 0
	while off + 16 <= n:
		var p := b.decode_u32(off + 12)
		if defs.has(p) and b.decode_u32(off + 4) < 2048 and b.decode_u32(off + 8) < 2048:
			out["pads"][defs[p]] = Vector2(b.decode_u32(off + 4), b.decode_u32(off + 8))
		off += 4
	# stage room lists: a table of (pointer, count) pairs; each entry is 24 bytes (level name or 0, room name, ...)
	off = 0
	while off + 16 <= n:
		var lists: Array = []
		var q := off
		while q + 8 <= n:
			var lp := b.decode_u32(q); var cnt := b.decode_u32(q + 4)
			if lp < base or lp >= base + b.size() or cnt == 0 or cnt > 64: break
			var lst: Array = []
			for k in cnt:
				var ro := lp - base + k * 24
				if ro + 24 > b.size(): lst = []; break
				var rn = _cstr(b, base, b.decode_u32(ro + 4), 4, 32)
				var w0 := b.decode_u32(ro)
				var lv = _cstr(b, base, w0, 7, 24) if w0 != 0 else null
				if rn == null or str(rn) != str(rn).to_upper() or (w0 != 0 and (lv == null or not str(lv).begins_with("level_"))):
					lst = []; break
				lst.append({"room": str(rn), "level": str(lv).substr(6) if lv != null else ""})
			if lst.is_empty(): break
			lists.append(lst); q += 8
		if lists.size() >= 10:
			out["lists"] = lists
			break
		off += 4
	return out
