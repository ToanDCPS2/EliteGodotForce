class_name RoomCompose
extends RefCounted
## Compose a room (map layers + object sprites) from extracted data. data_root = the 'out' folder made by the tools.
## Event slot filter: -1 = show everything, 0 = no event, 2 Summer, 3 Halloween, 4 Xmas ('aprilfools' via w8 bit16 handled by flag).

var root: String
var rooms: Array
var objects: Dictionary
var sprites: Dictionary

func _init(data_root: String) -> void:
	root = data_root
	var r = JSON.parse_string(FileAccess.get_file_as_string(root + "/rooms.json"))
	rooms = r.values() if r is Dictionary else r
	objects = JSON.parse_string(FileAccess.get_file_as_string(root + "/objects.json"))
	sprites = JSON.parse_string(FileAccess.get_file_as_string(root + "/sprites/index.json"))

func _key_for(o: Dictionary) -> String:
	var d: String = o["sprite_dir"] if o["sprite_dir"] != null else ""
	var n: String = o["name"]
	for pre in [d, d + "state/", d + "static/"]:
		for suf in ["", "_closed", "_open", "_idle", "0"]:
			var k: String = pre + n + suf
			if sprites.has(k): return k
	var low := {}
	for k in sprites.keys(): low[k.to_lower()] = k
	for pre in [d, d + "state/"]:
		var k2: String = (pre + n).to_lower()
		if low.has(k2): return low[k2]
	return ""

func _visible(o: Dictionary, ev: int) -> bool:
	if ev < 0: return true
	var apr := (int(o["w8"]) & 0x10000) != 0
	if apr: return false
	var oe := int(o["event"])
	return oe == 0 or oe == ev

## Returns {image, placed, total, unresolved}
func compose(prefix: String, ev: int) -> Dictionary:
	var mine: Array = []
	for r in rooms:
		if str(r["map"]).begins_with(prefix + "_map_"): mine.append(r)
	mine.sort_custom(func(a, b): return str(a["map"]) < str(b["map"]))
	if mine.is_empty(): return {}
	var cw := 0; var ch := 0
	for r in mine:
		cw = maxi(cw, int(r["width"]) * 8); ch = maxi(ch, int(r["height"]) * 8)
	var canvas := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 1))
	mine.reverse()   # background layer first
	for r in mine:
		var ts := EpfTileset.load_tsb(FileAccess.get_file_as_bytes("%s/named/%s" % [root, r["tileset"]]))
		var mp := FileAccess.get_file_as_bytes("%s/named/levels/%s" % [root, r["map"]])
		var layer := ts.render_map(mp, int(r["width"]), int(r["height"]))
		canvas.blend_rect(layer, Rect2i(0, 0, layer.get_width(), layer.get_height()), Vector2i(0, 0))
	var placed := 0; var total := 0
	var unresolved := {}
	var objs: Array = objects.get(str(mine[0]["overlay"]), [])
	for o in objs:
		if not _visible(o, ev): continue
		total += 1
		var k := _key_for(o)
		if k == "": unresolved[o["name"]] = true; continue
		var m: Dictionary = sprites[k]
		var img := Image.load_from_file("%s/sprites/%s" % [root, m["file"]])
		if img == null: continue
		img.convert(Image.FORMAT_RGBA8)
		var cv: Array = m["canvas"]; var cen: Array = m.get("center", [0, 0])
		var frame_rect := Rect2i(0, 0, int(cv[0]), int(cv[1]))
		canvas.blend_rect(img, frame_rect, Vector2i(int(o["x"]) - int(cen[0]), int(o["y"]) - int(cen[1])))
		placed += 1
	return {"image": canvas, "placed": placed, "total": total, "unresolved": unresolved.keys()}
