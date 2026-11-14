class_name TextTable
extends RefCounted
## Localization tables from fs.arc (u8 0, u32 count, count x u32 offsets, UTF-16LE NUL-terminated strings).
## per-language tables (ids = file name hashes): game strings and dialogue for English / Spanish / French
const GAME_STRINGS := {"en": 0xbb9f30ba, "es": 0x0825a503, "fr": 0x2b5a391f}
const DIALOGUE := {"en": 0x1d91b0d3, "es": 0xa8f37153, "fr": 0xb73dd01e}
const GAME_STRINGS_EN := 0xbb9f30ba   # 898 UI strings: menus, credits, mission titles, minigame names
const EN_DIALOGUE := 0x1d91b0d3
const EN_SPEAKER_LABELS := 0xf0092a17
const DEV_CONTEXT_NOTES := 0x6d629e15
const NPC_NAMES := 0x551f7310
const EN_ITEM_NAMES := 0x2b5a391f   # not verified: 117-entry item/medal names (en)  -- see docs
var strings: PackedStringArray = []

static func load_id(fs: EpfArc, id: int) -> TextTable:
	var t := TextTable.new()
	if not fs.by_id.has(id): return t
	var b := fs.get_entry(fs.by_id[id])
	if b.size() < 9 or b[0] != 0: return t
	var n := b.decode_u32(1)
	if n <= 0 or 5 + 4 * n > b.size(): return t
	var offs: Array = []
	for i in n: offs.append(b.decode_u32(5 + 4 * i))
	offs.append(b.size())
	t.strings.resize(n)
	for i in n:
		var s := b.slice(offs[i], offs[i + 1]).get_string_from_utf16()
		t.strings[i] = s.rstrip(char(0))
	return t

func get_text(i: int) -> String:
	return strings[i] if i >= 0 and i < strings.size() else "<%d>" % i
