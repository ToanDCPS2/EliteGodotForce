extends Node
## Sound effects from the ROM's sound/sfx.bin, decoded at runtime.
## sfx.bin: u8 1, u8 1, u16 count, then count x {u32 offset, u32 size_words, u32 rate_and_flags (low 16 = Hz)};
## each sample is DS IMA-ADPCM (s16 predictor, u16 step index, 4-bit nibbles low first), mono.
## ARM9 0x211d730 (_util.PlaySFX) calls the sound manager as play(id, volume 127, 16, pan 64) with the raw index,
## so script ids and ARM UI ids are direct indices into this table.

## ids the ARM UI code passes to the same play() call (0x2149ab1)
const UI_BUTTON := 38        # 41 call sites: menu / HUD buttons; also dismissing a thought or an item pop-up (0x20b8fbb)
const UI_TOUCH := 0          # 0x210eb49: an object / NPC was tapped (also a ready puffle aimed at something)
const DLG_NEXT := 2          # 0x20b6abb / 0x20b934b: next dialogue line, reply option picked, thought closed
const ITEM_GET := 27         # 0x21196ab: AddInventoryItem
const ITEM_ZOOM := 26        # 0x20b7a35: item pop-up flies in
const ITEM_GIVE := 48        # 0x20bb7cd: inventory item dropped on an object
const DOOR := 64             # 0x2112851: exit tapped

const STEP := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
	73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408,
	449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
	2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630,
	9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
const INDEX := [-1, -1, -1, -1, 2, 4, 6, 8]

var data: PackedByteArray
var table: Array = []          # [offset, bytes, rate]
var cache: Dictionary = {}     # id -> AudioStreamWAV
var voices: Array = []
var volume := 0.8
var muted := false

func setup(bytes: PackedByteArray) -> bool:
	data = bytes
	if data.size() < 16: return false
	var n := data.decode_u16(2)
	for i in n:
		var p := 4 + 12 * i
		table.append([data.decode_u32(p), data.decode_u32(p + 4) * 4, data.decode_u32(p + 8) & 0xffff])
	for i in 8:
		var a := AudioStreamPlayer.new(); add_child(a); voices.append(a)
	return true

func count() -> int: return table.size()

func stream(id: int) -> AudioStreamWAV:
	if id < 0 or id >= table.size(): return null
	if cache.has(id): return cache[id]
	var off: int = table[id][0]; var nb: int = table[id][1]
	if off + nb > data.size() or nb < 4: return null
	var pred := data.decode_s16(off); var idx := clampi(data.decode_u16(off + 2), 0, 88)
	var pcm := PackedByteArray(); pcm.resize((nb - 4) * 4)
	var w := 0
	for i in range(off + 4, off + nb):
		var b := data[i]
		for nib in [b & 15, b >> 4]:
			var st: int = STEP[idx]
			var diff := st >> 3
			if nib & 1: diff += st >> 2
			if nib & 2: diff += st >> 1
			if nib & 4: diff += st
			pred = maxi(-0x7fff, pred - diff) if nib & 8 else mini(0x7fff, pred + diff)
			idx = clampi(idx + INDEX[nib & 7], 0, 88)
			pcm.encode_s16(w, pred); w += 2
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS; s.mix_rate = table[id][2]; s.stereo = false; s.data = pcm
	cache[id] = s
	return s

## volume 0..127 like the DS call; pan 0..127 (64 = centre) is ignored (mono output keeps the original centred mix)
var _log := OS.get_environment("SFXLOG") != ""
func play(id: int, vol := 127) -> void:
	if _log: print("SFX ", id)
	if muted: return
	var s := stream(id)
	if s == null: return
	var v: AudioStreamPlayer = null
	for a in voices:
		if not a.playing: v = a; break
	if v == null: v = voices[0]
	v.stream = s
	v.volume_db = linear_to_db(maxf(0.0001, volume * float(vol) / 127.0))
	v.play()

## stop every voice playing sound `id` (DS 0x2149b9c, e.g. Cart Surfer's lean sound when the lean is let go)
func stop(id: int) -> void:
	if _log: print("SFXSTOP ", id)
	var s := stream(id)
	for a in voices:
		if a.playing and a.stream == s: a.stop()

func is_playing(id: int) -> bool:
	var s := stream(id)
	for a in voices:
		if a.playing and a.stream == s: return true
	return false
