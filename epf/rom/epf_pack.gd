class_name EpfPack
extends RefCounted
## The .epf game-data archive (like Ship of Harkinian's .otr): built once from the player's own ROM on first boot,
## then the game runs from it and the ROM is no longer needed. Nothing from the game ships with the port.
##
## REQUIRED ROM: Club Penguin: Elite Penguin Force, North America (USA), REVISION 2
##   game code CLPE, header ROM version byte (0x1E) = 2. Checked by the MD5 of the used part of the cartridge,
##   so trimmed and untrimmed dumps of Rev 2 both pass. Rev 0 / Rev 1 and other regions are refused.
##
## Format (a zip with our own extension):
##   manifest.json   {format, game_code, rom_version, rom_md5, files: [paths], overlays: [info dicts]}
##   fs/<path>       every file of the cartridge's NitroFS, byte-for-byte
##   ovl/<i>.bin     ARM9 overlays, already BLZ-decompressed

const FORMAT := 1                       # bump when the port needs data the archive doesn't hold: forces a re-extract
const GAME_CODE := "CLPE"
const ROM_VERSION := 2
const USED_SIZE := 0x3FCE888            # header 0x80: bytes the cartridge actually uses
const REV2_MD5 := "07cda977a67a0e6f9f2d4bd76ffaf1bf"   # MD5 of those bytes on the USA Rev 2 cartridge
const FILE_NAME := "game.epf"

const REQUIREMENT := "This port needs your own copy of Club Penguin: Elite Penguin Force for Nintendo DS:\n" + \
	"the North American (USA) release, Revision 2 (game code CLPE, ROM version 2)."

## Checks a ROM file. Returns "" when it is the right game and revision, otherwise a message for the player.
static func check_rom(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return "Could not open the file."
	if f.get_length() < 0x200: return "That file is not a Nintendo DS ROM."
	var head := f.get_buffer(0x200)
	var code := head.slice(0x0C, 0x10).get_string_from_ascii()
	var ver := head[0x1E]
	if code.substr(0, 3) != "CLP":
		return "That ROM is not Club Penguin: Elite Penguin Force (game code %s)." % code
	if code != GAME_CODE:
		return "That is the %s release (game code %s). This port needs the North American (USA) release, game code CLPE." % [_region(code), code]
	if ver != ROM_VERSION:
		return "That is Revision %d of the USA release. This port is built on, and needs, Revision 2 (ROM version 2)." % ver
	if f.get_length() < USED_SIZE:
		return "That ROM is incomplete (over-trimmed or a bad dump)."
	f.seek(0)
	var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_MD5)
	var left := USED_SIZE
	while left > 0:
		var n := mini(left, 1 << 20)
		ctx.update(f.get_buffer(n)); left -= n
	if ctx.finish().hex_encode() != REV2_MD5:
		return "That looks like USA Revision 2, but its data doesn't match a clean dump (modified, patched or damaged)."
	return ""

static func _region(code: String) -> String:
	match code.substr(3, 1):
		"P": return "European"
		"J": return "Japanese"
		"K": return "Korean"
		"E": return "North American"
	return "other-region"

## Builds the archive from a checked ROM. `progress` gets (done, total). Returns "" or an error message.
## Safe to call from a thread.
static func build(rom_path: String, out_path: String, progress := Callable()) -> String:
	var rom := NdsRom.open(rom_path)
	if rom == null: return "Could not read the ROM."
	var tmp := out_path + ".part"
	var zp := ZIPPacker.new()
	if zp.open(tmp) != OK: return "Could not write " + out_path
	var paths: Array = rom.files_by_path.keys(); paths.sort()
	var ovl: Array = []
	var total := paths.size() + rom.overlay_count(); var done := 0
	for p in paths:
		zp.start_file("fs/" + p); zp.write_file(rom.file(p)); zp.close_file()
		done += 1
		if progress.is_valid() and done % 16 == 0: progress.call(done, total)
	for i in rom.overlay_count():
		var inf := rom.overlay_info(i)
		zp.start_file("ovl/%d.bin" % i); zp.write_file(rom.overlay_data(i)); zp.close_file()
		inf["compressed"] = false
		ovl.append(inf)
		done += 1
	var man := {"format": FORMAT, "game_code": GAME_CODE, "rom_version": ROM_VERSION, "rom_md5": REV2_MD5,
		"files": paths, "overlays": ovl}
	zp.start_file("manifest.json"); zp.write_file(JSON.stringify(man).to_utf8_buffer()); zp.close_file()
	zp.close()
	if FileAccess.file_exists(out_path): DirAccess.remove_absolute(out_path)
	if DirAccess.rename_absolute(tmp, out_path) != OK: return "Could not finish writing " + out_path
	if progress.is_valid(): progress.call(total, total)
	return ""

## The manifest of an existing archive, or {} when it is missing, unreadable or from an older format.
static func manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var z := ZIPReader.new()
	if z.open(path) != OK: return {}
	var m = JSON.parse_string(z.read_file("manifest.json").get_string_from_utf8())
	z.close()
	if not (m is Dictionary) or int(m.get("format", 0)) != FORMAT or m.get("rom_md5", "") != REV2_MD5: return {}
	return m

## The game folder: everything the port writes goes here (game.epf, and saves/ for progress and settings), never AppData.
## Exported build: the folder holding the executable. Run from the project (editor / godot --path): the project folder.
static func game_dir() -> String:
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return ProjectSettings.globalize_path("res://").simplify_path()
	return OS.get_executable_path().get_base_dir()

static func default_path() -> String:
	return game_dir().path_join(FILE_NAME)

static func candidates() -> Array:
	return [default_path()]

## Path for a save/settings file in <game folder>/saves/. A copy left in Godot's user data folder by an older
## build is moved over the first time so progress isn't lost.
static func save_path(name: String) -> String:
	var dir := game_dir().path_join("saves")
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir.path_join(name)
	var old := ProjectSettings.globalize_path("user://" + name)
	if not FileAccess.file_exists(p) and FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, p)
	return p
