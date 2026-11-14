class_name NdsRom
extends RefCounted
## Nintendo DS cartridge reader: header, FAT/FNT file system, ARM9 overlays (BLZ-decompressed on demand).

var rom: PackedByteArray
var fat_off := 0
var fnt_off := 0
var y9_off := 0
var y9_size := 0
var files_by_path: Dictionary = {}   # "sound/music.bin" -> file id
var game_code := ""
## pack mode: reading from a .epf archive (EpfPack) instead of a cartridge image
var _zip: ZIPReader
var _ovl: Array = []

## Opens a .epf archive built by EpfPack; the same file()/overlay API as a ROM.
static func open_pack(path: String) -> NdsRom:
	var r := NdsRom.new()
	r._zip = ZIPReader.new()
	if r._zip.open(path) != OK: return null
	var m = JSON.parse_string(r._zip.read_file("manifest.json").get_string_from_utf8())
	if not (m is Dictionary) or not m.has("files"): return null
	r.game_code = m["game_code"]
	var i := 0
	for p in m["files"]: r.files_by_path[p] = i; i += 1
	for o in m["overlays"]:
		var d: Dictionary = {}
		for k in o: d[k] = o[k] if k == "compressed" else int(o[k])
		r._ovl.append(d)
	return r

static func open(path: String) -> NdsRom:
	var r := NdsRom.new()
	r.rom = FileAccess.get_file_as_bytes(path)
	if r.rom.size() < 0x200: return null
	r.game_code = r.rom.slice(0x0C, 0x10).get_string_from_ascii()
	r.fnt_off = r.rom.decode_u32(0x40)
	r.fat_off = r.rom.decode_u32(0x48)
	r.y9_off = r.rom.decode_u32(0x50)
	r.y9_size = r.rom.decode_u32(0x54)
	r._walk_dir(0xF000, "")
	return r

func _walk_dir(dir_id: int, prefix: String) -> void:
	var ent := fnt_off + (dir_id & 0xFFF) * 8
	var sub := fnt_off + rom.decode_u32(ent)
	var fid := rom.decode_u16(ent + 4)
	var p := sub
	while true:
		var t := rom[p]; p += 1
		if t == 0: break
		var ln := t & 0x7F
		var nm := rom.slice(p, p + ln).get_string_from_ascii(); p += ln
		if t & 0x80:
			var did := rom.decode_u16(p); p += 2
			_walk_dir(did, prefix + nm + "/")
		else:
			files_by_path[prefix + nm] = fid; fid += 1

func file_by_id(fid: int) -> PackedByteArray:
	var s := rom.decode_u32(fat_off + fid * 8)
	var e := rom.decode_u32(fat_off + fid * 8 + 4)
	return rom.slice(s, e)

func file(path: String) -> PackedByteArray:
	if not files_by_path.has(path): return PackedByteArray()
	if _zip != null: return _zip.read_file("fs/" + path)
	return file_by_id(files_by_path[path])

func overlay_count() -> int: return _ovl.size() if _zip != null else y9_size / 32

## {id, ram_address, ram_size, bss_size, file_id, compressed(bool)}
func overlay_info(i: int) -> Dictionary:
	if _zip != null: return _ovl[i].duplicate()
	var o := y9_off + i * 32
	var comp := rom.decode_u32(o + 28)
	return {"id": rom.decode_u32(o), "ram_address": rom.decode_u32(o + 4), "ram_size": rom.decode_u32(o + 8),
		"bss_size": rom.decode_u32(o + 12), "file_id": rom.decode_u32(o + 24), "compressed": (comp >> 24) & 1 != 0}

func overlay_data(i: int) -> PackedByteArray:
	if _zip != null: return _zip.read_file("ovl/%d.bin" % i)
	var inf := overlay_info(i)
	var raw := file_by_id(inf["file_id"])
	return EpfCompress.blz(raw) if inf["compressed"] else raw
