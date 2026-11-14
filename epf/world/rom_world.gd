class_name RomWorld
extends RefCounted
## ROM-native room composition: no extracted files, everything read from the user's ROM.
var rom: NdsRom
var fs: EpfArc
var rdt: EpfRdt
var rooms: Array
var objects: Dictionary
var _sprite_cache: Dictionary = {}
var _keys_lower: Dictionary = {}

static func open(data_path: String) -> RomWorld:
	var w := RomWorld.new()
	w.rom = NdsRom.open_pack(data_path)        # game data comes only from a .epf archive (EpfPack)
	if w.rom == null: return null
	w.fs = EpfArc.parse(w.rom.file("fs.arc"))
	w.rdt = EpfRdt.parse(w.rom.file("Game.rdt"))
	w.rooms = OverlayMeta.scan_rooms(w.rom)
	w.objects = OverlayMeta.scan_objects(w.rom)
	for k in w.rdt.keys.keys(): w._keys_lower[k.to_lower()] = k
	return w

func room_prefixes() -> Array:
	var s := {}
	for r in rooms:
		var m := str(r["map"]); var i := m.find("_map_")
		if i > 0: s[m.substr(0, i)] = true
	var a := s.keys(); a.sort(); return a

func _key_for(o: Dictionary) -> String:
	var d0: String = o["sprite_dir"] if o["sprite_dir"] != null else ""
	var n: String = o["name"]
	# Objects whose definition points at 3d/<Name>/ are drawn in rooms from the pre-rendered 2D sprites under NPC/<Name>/.
	var dirs: Array = [d0]
	if d0.to_lower().begins_with("3d/"): dirs.append("NPC/" + d0.substr(3))
	for d in dirs:
		for pre in [d, d + "state/", d + "static/"]:
			for suf in ["", "_closed", "_open", "_idle", "0"]:
				var k: String = pre + n + suf
				if rdt.keys.has(k): return k
	for d in dirs:
		for pre in [d, d + "state/"]:
			var k2: String = (pre + n).to_lower()
			if _keys_lower.has(k2): return _keys_lower[k2]
	return ""

## Objects defined under 3d/ are real-time 3D models; their 2D sprite is only a tiny placeholder label ("Bot").
func is_model_object(o: Dictionary) -> bool:
	var sd = o["sprite_dir"]
	return sd != null and str(sd).to_lower().begins_with("3d/") and not model(str(o["name"])).is_empty()

## Instances of doors, Command Coach hints etc. carry a chapter.mission list in `frames` ("1.01,2.02,0.10"): shown only while that mission is active.
## mission == "" disables the filter.
## event 0x100: object exists in every season but starts hidden until a script reveals it
## (ActivateNpc / AddItem / SetVisible) - hiding puffles, crates, the Coffee Shop blue puffle...
const HIDDEN_UNTIL_ACTIVATED := 0x100

## flags 5 + UI/InventoryPanel sprites are inventory item definitions (M1C1_Card1 = MapPart1 ...), never drawn in the room.
## Door/exit objects carry a destination room (or "none" for a door that only talks / is locked this mission).
static func is_door(o: Dictionary) -> bool:
	return o.get("dest") != null

## Several instances of the same door are stacked in a room, one per set of missions. Keep one per name:
## an instance listing the active mission > an always-present scripted one > an always-present plain one >
## (with no mission set: a free-play one (0.xx) > any other, so the dev room list keeps a way out). With a mission set, an
## instance listed only for other missions is left out, as on the DS (e.g. the broken Gift Office door exists in 4.02+ only).
static func pick_doors(objs: Array, mission: String) -> Array:
	var best := {}
	for o in objs:
		if not is_door(o): continue
		var f = o.get("frames")
		var fs := str(f) if f != null else ""
		var has_list := fs.length() >= 4 and fs[1] == "."
		var score := 0
		if has_list and mission != "" and mission in fs.split(","): score = 5
		elif not has_list: score = 4 if o.get("script") != null else 3
		elif mission != "": continue          # listed for other missions only: not in this room now (as on the DS)
		elif fs.contains("0.0") or fs.contains("0.1"): score = 2
		else: score = 1
		var n := str(o["name"])
		if not best.has(n) or score > best[n][0]: best[n] = [score, o]
	var out := []
	for o in objs:
		if not is_door(o): out.append(o)
		elif best.has(str(o["name"])) and best[str(o["name"])][1] == o: out.append(o)
	return out

static func is_inventory_def(o: Dictionary) -> bool:
	return int(o.get("flags", 0)) == 5 and str(o.get("sprite_dir", "")).begins_with("UI/InventoryPanel")

static func mission_ok(o: Dictionary, mission: String) -> bool:
	if mission == "": return true
	var f = o.get("frames")
	if f == null: return true
	var fs := str(f)
	if fs.length() < 4 or not fs[0].is_valid_int() or fs[1] != "." : return true
	return mission in fs.split(",")

static func visible(o: Dictionary, ev: int) -> bool:
	if ev < 0: return true
	var w8 := int(o["w8"])
	# doors: w8 = arrival camera x << 16 | 300, not a flag word
	if o.get("dest") == null and w8 < 0x2000000 and (w8 & 0x10000) != 0: return false   # April Fools objects; large values are pointers, not flags
	var oe := int(o["event"])
	if oe == HIDDEN_UNTIL_ACTIVATED: oe = 0
	return oe == 0 or oe == ev

## Language (the DS takes it from the firmware; the port has it in Options). The ROM's base art is French; English and
## Spanish versions sit in an "english"/"spanish" folder next to it (UI/UtilityBorder/english/Bttn_Map_up ...).
var lang := "en"
const LANG_DIR := {"en": "english", "es": "spanish", "fr": ""}
func set_lang(l: String) -> void:
	if not LANG_DIR.has(l): l = "en"
	lang = l; _sprite_cache.clear()

## Room maps are localised too (ARM 0x2112c70 inserts "french/", "english/" or "spanish/" before the file name and uses
## that file when it exists): levels/english/Town0_map_0.mpb points the shop signs at the English tiles of Town.tsb.
## Any ROM file through the same rule: dir/<lang>/name if present, else dir/name.
## Localised files come two ways in this ROM: a language suffix on the name (bg/Menus/Title_topscreen2_en.nbfc,
## flc/M1C1Intro03NewsPaperFull_sp.flc; the plain name is the French one) and a language folder (levels/english/...).
## Any ROM file goes through the same rule: suffixed name, then dir/<lang>/name, then the plain name.
const LANG_SUFFIX := {"en": ["_en"], "es": ["_sp", "_es"], "fr": ["_fr"]}
func loc_path(path: String) -> String:
	var base := path.get_basename(); var ext := path.get_extension()
	for sx in LANG_SUFFIX.get(lang, []):
		var p2: String = base + str(sx) + ("." + ext if ext != "" else "")
		if fs.get_by_path(p2).size() > 0: return p2
	var ld: String = LANG_DIR.get(lang, "")
	if ld != "":
		var p3: String = path.get_base_dir() + "/" + ld + "/" + path.get_file()
		if fs.get_by_path(p3).size() > 0: return p3
	return path

func loc_bytes(path: String) -> PackedByteArray:
	return fs.get_by_path(loc_path(path))

func map_bytes(map_name: String) -> PackedByteArray:
	return loc_bytes("levels/" + map_name)

func sprite(key: String) -> Dictionary:
	if not _sprite_cache.has(key):
		var d := {}
		var ld: String = LANG_DIR.get(lang, "")
		if ld != "" and not key.contains("/" + ld + "/"):
			var lk := key.get_base_dir() + "/" + ld + "/" + key.get_file()
			if rdt.keys.has(lk): d = rdt.decode(lk)
		if d.is_empty(): d = rdt.decode(key)
		_sprite_cache[key] = d
	return _sprite_cache[key]

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
	mine.reverse()
	for r in mine:
		var ts := EpfTileset.load_tsb(loc_bytes(str(r["tileset"])))
		var layer := ts.render_map(map_bytes(str(r["map"])), int(r["width"]), int(r["height"]))
		canvas.blend_rect(layer, Rect2i(0, 0, layer.get_width(), layer.get_height()), Vector2i(0, 0))
	var placed := 0; var total := 0; var unresolved := {}
	for o in objects.get(int(mine[0]["overlay"]), objects.get(str(mine[0]["overlay"]), [])):
		if not visible(o, ev): continue
		total += 1
		if is_model_object(o): placed += 1; continue   # drawn as 3D in the viewer, not in this 2D composite
		var k := _key_for(o)
		if k == "": unresolved[o["name"]] = true; continue
		var dec := sprite(k)
		if dec.is_empty() or dec["frames"].is_empty(): continue
		var cen = dec.get("center"); if cen == null: cen = [0, 0]
		var cv: Array = dec["canvas"]
		canvas.blend_rect(dec["frames"][0]["image"], Rect2i(0, 0, int(cv[0]), int(cv[1])), Vector2i(int(o["x"]) - int(cen[0]), int(o["y"]) - int(cen[1])))
		placed += 1
	return {"image": canvas, "placed": placed, "total": total, "unresolved": unresolved.keys()}

## Background layers only (for the interactive viewer): {image, overlay}
func compose_layers(prefix: String) -> Dictionary:
	var mine: Array = []
	for r in rooms:
		if str(r["map"]).begins_with(prefix + "_map_"): mine.append(r)
	mine.sort_custom(func(a, b): return str(a["map"]) < str(b["map"]))
	if mine.is_empty(): return {}
	# Layers with layer id >= 2 (BG) scroll at their own parallax and wrap (tile) in both axes; id 1 is the main layer.
	var fgl: Array = []; var bgl: Array = []
	for r in mine:
		if int(r.get("layer", 1)) >= 2 and str(r["map"]).ends_with("_map_0.mpb") == false: bgl.append(r)
		else: fgl.append(r)
	if fgl.is_empty(): fgl = mine; bgl = []
	var cw := 0; var ch := 0
	for r in fgl:
		cw = maxi(cw, int(r["width"]) * 8); ch = maxi(ch, int(r["height"]) * 8)
	var canvas := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0 if not bgl.is_empty() else 1))
	var order := fgl.duplicate(); order.reverse()
	for r in order:
		var ts := EpfTileset.load_tsb(loc_bytes(str(r["tileset"])))
		var layer := ts.render_map(map_bytes(str(r["map"])), int(r["width"]), int(r["height"]))
		canvas.blend_rect(layer, Rect2i(0, 0, layer.get_width(), layer.get_height()), Vector2i(0, 0))
	var bgs: Array = []
	bgl.reverse()   # highest layer id first = furthest back
	for r in bgl:
		var ts2 := EpfTileset.load_tsb(loc_bytes(str(r["tileset"])))
		var img := ts2.render_map(map_bytes(str(r["map"])), int(r["width"]), int(r["height"]))
		var par: Array = r["parallax"]
		bgs.append({"image": img, "par": Vector2(float(par[0]), float(par[1])) / 4096.0})
	return {"image": canvas, "overlay": int(mine[0]["overlay"]), "bgs": bgs}

## 3D models (nsbmd) by model name -> parsed dict. Built lazily on first use.
var _models: Dictionary = {}
var _models_scanned := false
func model(name: String) -> Dictionary:
	if not _models_scanned:
		_models_scanned = true
		for id in fs.by_id:
			var b := fs.get_entry(fs.by_id[id])
			if b.size() < 16 or b.slice(0, 4).get_string_from_ascii() != "BMD0": continue
			var parsed := EpfNsbmd.parse(b)
			for m in parsed["models"]:
				if not _models.has(m["name"]): _models[m["name"]] = {"model": m, "textures": parsed["textures"]}
	return _models.get(name, {})

## Joint animations (nsbca) list, parsed lazily: [{name, frames, objs}]
var _anims: Array = []
var _anims_scanned := false
func animations() -> Array:
	if not _anims_scanned:
		_anims_scanned = true
		for id in fs.by_id:
			var b := fs.get_entry(fs.by_id[id])
			if b.size() < 4 or b.slice(0, 4).get_string_from_ascii() != "BCA0": continue
			_anims.append_array(EpfNsbca.parse(b))
	return _anims

## Find the idle animation for a model: names are truncated to 16 chars, e.g. 'SuperRobotTown_i'.
func idle_animation(model_name: String, num_objects: int) -> Dictionary:
	return find_animation(model_name, "i", num_objects)

## suffix: i = idle, t = talk, f/s = other states (names are cut at 16 chars, so the suffix is the 16th-ish char of the stem).
func find_animation(model_name: String, suffix: String, num_objects: int) -> Dictionary:
	var pre := (model_name + "_" + suffix).substr(0, 16)
	var best := {}
	for a in animations():
		if a["objs"].size() == num_objects and str(a["name"]).begins_with(pre):
			if best.is_empty() or a["frames"] < best["frames"]: best = a
	return best

## Does this room's camera wrap horizontally? From the main map layer's record (byte 0x23), as the DS decides it.
func room_wraps(prefix: String) -> bool:
	var want := prefix.to_lower() + "_map_"
	for r in rooms:
		if str(r["map"]).to_lower().begins_with(want) and int(r.get("layer", 1)) == 1:
			return int(r.get("wrap", 0)) != 0
	return false
