class_name EpfMusic
extends RefCounted
## Re-implementation of the game's ARM9 tracker engine (overlay 0, tick function 0x214a6c0) plus a
## software model of the DS SPU. Everything is read from the user's ROM at runtime:
##   sound/music.bin  (instruments = IMA-ADPCM / PCM8 samples, patterns, songs)
##   overlay 0        (pitch table @0x21866dc, vibrato table @0x2187208, room->song table @0x217d008)
## XM-style: 12 channels, volume/pan envelopes + fadeout, tone porta, vibrato, arpeggio, retrig, E-effects.

const OV0_BASE := 0x20767a0
const VIB_ADDR := 0x2187208
const PITCH_ADDR := 0x21872dc - 0xc00      # table index 0x600 lives at 0x21872dc
const ROOM_TABLE_ADDR := 0x217d008
const SPU_CLOCK := 16756991.0
const MIX_RATE := 32768
const STEP := [7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767]
const IDX := [-1, -1, -1, -1, 2, 4, 6, 8]

# ---- bank ----
var mb: PackedByteArray
var ov0: PackedByteArray
var pdata: PackedByteArray
var song_offs: PackedInt32Array = PackedInt32Array()
var insts: Array = []          # Dictionary per instrument
var vib: PackedByteArray
var pitch: PackedInt32Array = PackedInt32Array()
var _pcm_cache: Dictionary = {}
var _cache_mtx := Mutex.new()

static func s8(v: int) -> int: return v - 256 if v >= 128 else v
static func s16(v: int) -> int: return v - 65536 if v >= 32768 else v

static func open(music_bin: PackedByteArray, overlay0: PackedByteArray) -> EpfMusic:
	var m := EpfMusic.new()
	m.mb = music_bin; m.ov0 = overlay0
	var n := music_bin[2]; var nsongs := music_bin[3]
	var pd_off := music_bin.decode_u32(8); var pd_len := music_bin.decode_u32(12)
	m.pdata = music_bin.slice(pd_off, pd_off + pd_len)
	for i in nsongs: m.song_offs.append(music_bin.decode_u32(16 + 4 * i))
	var p := 16 + nsongs * 4
	for i in n:
		var cnt := music_bin.decode_u32(p)
		var ins := {
			"off": p, "count": cnt,
			"loop_start": music_bin.decode_s32(p + 4) if false else _s32(music_bin.decode_u32(p + 4)),
			"words": music_bin.decode_u32(p + 8), "fmt": music_bin.decode_u16(p + 12),
			"vol": music_bin[p + 14], "pan": s8(music_bin[p + 15]), "finetune": s8(music_bin[p + 16]), "rel": s8(music_bin[p + 17]),
			"fadeout": music_bin.decode_u16(p + 18),
			"venv": music_bin.slice(p + 0x14, p + 0x48), "penv": music_bin.slice(p + 0x48, p + 0x7c),
			"data_off": p + 124,
		}
		m.insts.append(ins)
		p += 124 + cnt * 4
	var vo := VIB_ADDR - OV0_BASE
	m.vib = overlay0.slice(vo, vo + 32)
	var po := PITCH_ADDR - OV0_BASE
	for i in 17000: m.pitch.append(overlay0.decode_u16(po + 2 * i))
	return m

static func _s32(v: int) -> int: return v - 4294967296 if v >= 2147483648 else v

func song_count() -> int: return song_offs.size()

func timer_for(idx: int) -> int:
	return pitch[clampi(idx, 0x600, 16999)]

## Decoded sample as signed 16-bit-range floats (cached); also sets "spw" (samples per word).
func pcm(ins: Dictionary) -> PackedFloat32Array:
	var key: int = ins["off"]
	_cache_mtx.lock()
	var hit = _pcm_cache.get(key)
	_cache_mtx.unlock()
	if hit != null: return hit
	var nwords: int = ins["words"] if int(ins["words"]) != 0 else int(ins["count"])
	var b := mb.slice(int(ins["data_off"]), int(ins["data_off"]) + nwords * 4)
	var out := PackedFloat32Array()
	var fmt: int = ins["fmt"]
	if fmt == 0:
		ins["spw"] = 4
		out.resize(b.size())
		for i in b.size(): out[i] = float(s8(b[i])) / 128.0
	elif fmt == 1:
		ins["spw"] = 2
		out.resize(b.size() / 2)
		for i in out.size(): out[i] = float(s16(b.decode_u16(i * 2))) / 32768.0
	else:
		ins["spw"] = 8
		var p := s16(b.decode_u16(0)); var ix := mini(b[2], 88)
		out.resize((b.size() - 4) * 2)
		var o := 0
		for k in range(4, b.size()):
			var by := b[k]
			for h in 2:
				var nb := (by & 15) if h == 0 else (by >> 4)
				var st: int = STEP[ix]; var d := st >> 3
				if nb & 1: d += st >> 2
				if nb & 2: d += st >> 1
				if nb & 4: d += st
				p += -d if (nb & 8) else d
				p = clampi(p, -32768, 32767)
				ix = clampi(ix + IDX[nb & 7], 0, 88)
				out[o] = float(p) / 32768.0; o += 1
	_cache_mtx.lock(); _pcm_cache[key] = out; _cache_mtx.unlock()
	return out

## Decode every instrument ahead of time (run on a background thread) so song switches never stall.
func preload_all() -> void:
	for I in insts: pcm(I)

# ---- songs ----
func parse_song(sid: int) -> Dictionary:
	var b := mb.slice(song_offs[sid], song_offs[sid] + 0x4000)
	var s := {"nch": b[0], "npat": b[1], "length": b[2], "restart": b[4], "speed": b[5], "bpm": b.decode_u16(6)}
	var orders := []
	for i in int(s["length"]): orders.append(b[0x28 + i])
	s["orders"] = orders
	var p := 0x28 + ((int(s["length"]) + 3) & ~3)
	var pats := []
	for _i in int(s["npat"]):
		var rows := b.decode_u16(p)
		var ent := PackedInt64Array()
		for r in rows: ent.append(b.decode_u32(p + 4 + r * 4))
		pats.append(ent)
		p += 4 + rows * 4
	s["patterns"] = pats
	return s

## Room -> song from the game's own table (overlay 0, 0x217d008). Returns {default:{ROOM:song}, over:{"c,s,ROOM":song}}.
func room_song_table() -> Dictionary:
	var rd := {}; var over := {}
	var counts := {}
	for k in 7:
		var ptr := _u(ROOM_TABLE_ADDR + 8 * k); var cnt := _u(ROOM_TABLE_ADDR + 8 * k + 4)
		for j in cnt:
			var rp := _u(ptr + 8 * j); var rc := _u(ptr + 8 * j + 4)
			for r in rc:
				var rec := rp + 24 * r
				var name := _cstr(_u(rec + 4))
				if name == "": continue
				var song := _u(rec + 12)
				var key := "%d,%d,%s" % [k, j, name]
				over[key] = song
				if not counts.has(name): counts[name] = {}
				counts[name][song] = int(counts[name].get(song, 0)) + 1
	for n in counts:
		var best := -1; var bc := -1
		for sg in counts[n]:
			var c: int = counts[n][sg]
			# ties prefer the lower song id; song 11 is a mission-specific override, never a default
			if int(sg) != 11 and (c > bc or (c == bc and int(sg) < best)): best = int(sg); bc = c
		if best < 0: best = counts[n].keys()[0]
		rd[n] = best
	return {"default": rd, "over": over}

func _u(a: int) -> int:
	var o := a - OV0_BASE
	if o < 0 or o + 4 > ov0.size(): return 0
	return ov0.decode_u32(o)

func _cstr(a: int) -> String:
	var o := a - OV0_BASE
	if o < 0 or o >= ov0.size(): return ""
	var e := o
	while e < ov0.size() and ov0[e] != 0 and e - o < 80: e += 1
	return ov0.slice(o, e).get_string_from_ascii()

# ---- sequencer state ----
class Chan:
	var hw := 0
	var flags := 1
	var vol_hw := 0; var pan_hw := 64; var timer := 0
	var ls := -1; var ln := 0
	var inst = null
	var n18 := 0; var n19 := 0; var rel := 0; var vol := 0; var pan := 0; var tgt := 0
	var vslide := 0; var vspd := 0; var vdep := 0; var vpos := 0
	var fine := 0; var poff := 0; var pspd := 0; var trem := 0
	var fade := 0xffff
	var vt := 0; var vv := 0x40; var vc := 0; var vn := 0
	var pt := 0; var pv := 0x20; var pc := 0; var pn := 0
	var delay := 0; var retrig := 0
	var fx := 0; var fp := 0

var song: Dictionary
var ch: Array = []
var tick_ctr := 0
var speed := 6
var bpm := 125
var order := 0
var row := 0
var row_delay := 0
var patptr: PackedInt64Array
var gvol := 0x100
var loops := 0
var fb := 1
var events: Array = []         # [kind, ch, a, b...] consumed by the mixer
var stop_mask := 0

func start(sid: int) -> void:
	song = parse_song(sid)
	ch.clear()
	for i in int(song["nch"]):
		var c := Chan.new(); c.hw = i; ch.append(c)
	tick_ctr = 0; speed = song["speed"]; bpm = song["bpm"]
	order = 0; row = 0; row_delay = 0; gvol = 0x100; loops = 0
	patptr = song["patterns"][song["orders"][0]]
	fb = (int(song["nch"]) * 5 + 7) >> 3
	events.clear(); stop_mask = 0

func tick_seconds() -> float: return 2.5 / float(maxi(bpm, 1))

func _env(flags: int, E: PackedByteArray, c: Chan, vol_env: bool) -> void:
	var cnt := E[0]
	var tick: int; var cur: int; var nxt: int
	if vol_env: tick = c.vt; cur = c.vc; nxt = c.vn
	else: tick = c.pt; cur = c.pc; nxt = c.pn
	var val := E.decode_u16(6 + cur * 4)
	if cur != nxt:
		var d := E.decode_u16(4 + nxt * 4) - E.decode_u16(4 + cur * 4)
		var num := (tick - E.decode_u16(4 + cur * 4)) * (E.decode_u16(6 + nxt * 4) - E.decode_u16(6 + cur * 4))
		val += (num / d) if d != 0 else 0
	val &= 0xffff
	tick += 1
	if tick >= E.decode_u16(4 + nxt * 4):
		cur = nxt; nxt += 1
		var sus := E[1]
		if sus != 0xff and (flags & 4) == 0 and nxt > sus:
			nxt = sus; cur = sus; tick = E.decode_u16(4 + sus * 4)
		elif E[2] != 0xff and nxt > E[3]:
			cur = E[2]; nxt = cur + (0 if cur == E[3] else 1); tick = E.decode_u16(4 + cur * 4)
		elif nxt >= cnt:
			nxt -= 1; tick -= 1
	if vol_env: c.vv = val; c.vc = cur; c.vn = nxt; c.vt = tick
	else: c.pv = val; c.pc = cur; c.pn = nxt; c.pt = tick

func tick() -> void:
	for c: Chan in ch:
		if (c.flags & 1) != 0 or c.inst == null: continue
		var I: Dictionary = c.inst
		if I["venv"][0] != 0:
			if (c.flags & 4) != 0:
				if c.fade > int(I["fadeout"]): c.fade -= int(I["fadeout"])
				else:
					c.fade = 0; c.flags = 0x81; continue
			c.flags |= 0x10
			_env(c.flags, I["venv"], c, true)
		if I["penv"][0] != 0:
			c.flags |= 0x20
			_env(c.flags, I["penv"], c, false)
	if tick_ctr == 0:
		if row_delay > 0:
			row_delay -= 1
			_flush(); return
		row += 1
		var ent := 0xffffffff
		if row - 1 < patptr.size(): ent = patptr[row - 1]
		if ent == 0xffffffff:
			for c: Chan in ch: c.fx = 0; c.fp = 0
		else:
			_read_row(ent)
		if row >= patptr.size():
			order += 1
			if order > int(song["length"]) - 1:
				loops += 1
				order = song["restart"]
			row = 0
			patptr = song["patterns"][song["orders"][order]]
	_fx_tick()
	_hw_update()
	tick_ctr += 1
	if tick_ctr >= speed: tick_ctr = 0
	_flush()

func _read_row(ent: int) -> void:
	var fp := ent; var dp := ent + fb; var mask := 0x80
	for c: Chan in ch:
		var vals := [0, 0, 0, 0, 0]
		for k in 5:
			var v := 0
			if (pdata[fp] & mask) != 0:
				v = pdata[dp]; dp += 1
			if mask > 1: mask >>= 1
			else:
				mask = 0x80; fp += 1
			vals[k] = v
		c.fx = vals[2]; c.fp = vals[4]
		_cell(c, vals[0], vals[1], vals[2], vals[3], vals[4])

func _key_off(c: Chan) -> void:
	if c.inst != null and c.inst["venv"][0] != 0: c.flags |= 4
	else: c.flags = 0x81

func _cell(c: Chan, note: int, inst: int, fxt: int, volc: int, fxp: int) -> void:
	if inst != 0 and inst <= insts.size():
		var I: Dictionary = insts[inst - 1]; c.inst = I
		c.vol = I["vol"]; c.pan = I["pan"]; c.rel = I["rel"]
		if note == 0:
			c.fade = 0xffff
			c.vt = 0; c.vv = 0x40; c.vc = 0; c.vn = 0
			c.pt = 0; c.pv = 0x20; c.pc = 0; c.pn = 0
			c.flags |= 0x38
		elif fxt != 3 and fxt != 5:
			if int(I["words"]) != 0: c.ls = I["loop_start"]; c.ln = I["words"]
			else: c.ls = -1; c.ln = I["count"]
			c.fine = I["finetune"]
			c.flags |= 0x78
	elif note != 0 and note != 0x61 and fxt == 0:
		if c.inst != null: c.flags |= 0x40
	if note != 0:
		if note == 0x61: _key_off(c)
		elif fxt == 3 or fxt == 5: c.tgt = note
		else:
			c.n18 = note; c.n19 = note; c.poff = 0; c.vpos = 0
			c.fade = 0xffff
			c.vt = 0; c.vv = 0x40; c.vc = 0; c.vn = 0
			c.pt = 0; c.pv = 0x20; c.pc = 0; c.pn = 0
			c.flags = (c.flags & ~5) | 0x78
	if volc != 0:
		var v := volc
		if v < 0xa0:
			if v <= 0x50: c.vol = s8((v - 0x10) & 0xff)
			elif v < 0x70: c.vol = maxi(0, s8(c.vol & 0xff) - ((v - 0x60) << 2))
			elif v < 0x80: c.vol = mini(0x40, s8(c.vol & 0xff) + ((v - 0x70) << 2))
			elif v < 0x90: c.vol = maxi(0, s8(c.vol & 0xff) - (v - 0x80))
			else: c.vol = mini(0x40, s8(c.vol & 0xff) + (v - 0x90))
			c.vol = s8(c.vol & 0xff)
			c.flags |= 0x10
		elif v < 0xd0:
			c.pan = s8(((v - 0xc0) * 8 - 0x40) & 0xff); c.flags |= 0x20
		elif v < 0xe0:
			c.pan = maxi(-0x40, c.pan - (v - 0xd0)); c.flags |= 0x20
		else:
			c.pan = mini(0x40, c.pan + (v - 0xe0)); c.flags |= 0x20
	_row_fx(c, fxt, fxp)

func _row_fx(c: Chan, t: int, p: int) -> void:
	if t > 0x1f: return
	match t:
		1, 2, 3:
			if p != 0: c.pspd = (p << 3) & 0xffff
		4, 7:
			if p != 0:
				if (p >> 4) != 0: c.vspd = p >> 4
				if (p & 15) != 0: c.vdep = p & 15
		5, 6, 10:
			c.vslide = -p if p < 0x10 else p >> 4
		8:
			c.pan = s8(((p >> 1) - 0x40) & 0xff); c.flags |= 0x20
		11:
			order = p - 1
			row = patptr.size()
		12:
			c.vol = p; c.flags |= 0x10
		13:
			order += 1
			if order > int(song["length"]) - 1:
				loops += 1; order = song["restart"]
			row = (p & 15) + (p >> 4) * 10
			patptr = song["patterns"][song["orders"][order]]
		14:
			var x := p >> 4
			if x == 1: c.poff = s16((c.poff + (p << 3)) & 0xffff); c.flags |= 8
			elif x == 2: c.poff = s16((c.poff - (p << 3)) & 0xffff); c.flags |= 8
			elif x == 5: c.fine = p & 15
			elif x == 10: c.vol = mini(0x40, c.vol + (p & 15)); c.flags |= 0x10
			elif x == 11: c.vol = maxi(0, c.vol - (p & 15)); c.flags |= 0x10
			elif x == 13:
				c.delay = p & 15
				if c.delay != 0: c.flags &= ~0x78
			elif x == 14: row_delay = p & 15
		15:
			if p < 0x20: speed = p
			else: bpm = p
		16:
			gvol = p
			for k: Chan in ch:
				if (k.flags & 1) == 0: k.flags |= 0x10
		17:
			var d := -p if p < 0x10 else p >> 4
			gvol = clampi(gvol + d, 0, 0x100)
			for k: Chan in ch:
				if (k.flags & 1) == 0: k.flags |= 0x10
		20:
			_key_off(c)
		21:
			c.pt = p; c.vt = p
		24:
			if p != 0:
				if (p & 15) != 0: c.pan = maxi(-0x40, c.pan - (p & 15))
				else: c.pan = mini(0x40, c.pan + (p >> 4))
				c.flags |= 0x20
		27:
			c.retrig = p & 15
			if c.retrig != 0: c.retrig -= 1
			if c.inst != null: c.flags |= 0x40

func _vol_slide(c: Chan) -> void:
	c.vol = clampi(c.vol + c.vslide, 0, 0x40); c.flags |= 0x10

func _vibrato(c: Chan) -> void:
	var v: int = vib[c.vpos & 31]
	if (c.vpos & 32) != 0: v = -v
	c.vpos = (c.vpos + c.vspd) & 0xff
	c.poff = (v * c.vdep) >> 5; c.flags |= 8

func _tone_porta(c: Chan) -> void:
	var sp := c.pspd
	if sp == 0 or c.tgt == c.n19: return
	var diff := (c.tgt << 7) - ((c.n19 << 7) + c.poff)
	if absi(diff) > sp:
		c.poff += sp if diff > 0 else -sp
	else:
		c.poff = 0; c.n18 = c.tgt; c.n19 = c.tgt
	c.flags |= 8

func _fx_tick() -> void:
	for c: Chan in ch:
		var t := c.fx; var p := c.fp
		match t:
			0:
				if p != 0:
					var m := tick_ctr % 3
					var n := c.n19
					if m == 1: n += p >> 4
					elif m == 2: n += p & 15
					c.n18 = n; c.flags |= 8
			1:
				c.poff = s16((c.poff + c.pspd) & 0xffff); c.flags |= 8
			2:
				c.poff = s16((c.poff - c.pspd) & 0xffff); c.flags |= 8
			3, 5:
				if t == 5: _vol_slide(c)
				_tone_porta(c)
			4, 6:
				if t == 6: _vol_slide(c)
				_vibrato(c)
			7:
				var v: int = vib[c.vpos & 31]
				if (c.vpos & 32) != 0: v = -v
				c.vpos = (c.vpos + c.vspd) & 0xff
				c.trem = (v * c.vdep) >> 6; c.flags |= 0x10
			10:
				_vol_slide(c)
			14:
				if (p >> 4) == 13 and c.delay != 0:
					c.delay -= 1
					if c.delay == 0: c.flags |= 0x78
			27:
				if c.retrig == 0:
					if c.inst != null: c.flags |= 0x40
					c.retrig = p & 15
					if c.retrig == 0: c.retrig = 1
				else: c.retrig -= 1

func _hw_update() -> void:
	for c: Chan in ch:
		var f := c.flags & 0xf8
		if f == 0: continue
		if (f & 8) != 0:
			c.timer = timer_for(c.fine + ((c.n18 + c.rel) << 7) + c.poff)
		if (f & 0x10) != 0:
			var v := clampi(c.vol + c.trem, 0, 0x40)
			if v <= 0: c.vol_hw = 0
			else:
				var r := v * (c.vv * gvol)
				if (c.flags & 4) != 0: r = ((r >> 5) * c.fade) >> 24
				else: r = r >> 13
				c.vol_hw = mini(r, 127)
		if (f & 0x20) != 0:
			var pn := c.pan
			var r2 := ((0x80 - absi(pn)) * (c.pv - 0x20)) >> 5
			c.pan_hw = clampi(pn + r2 + 0x40, 0, 127)
		if (f & 0x80) != 0:
			stop_mask |= 1 << c.hw
		elif (f & 0x40) != 0:
			events.append(["on", c.hw, c.inst, c.ls, c.vol_hw, c.timer, c.pan_hw])
		else:
			if (f & 8) != 0: events.append(["timer", c.hw, c.timer])
			if (f & 0x10) != 0: events.append(["vol", c.hw, c.vol_hw])
			if (f & 0x20) != 0: events.append(["pan", c.hw, c.pan_hw])
		c.flags &= ~f

func _flush() -> void:
	for k in ch.size():
		if (stop_mask >> k) & 1: events.append(["off", k])
	stop_mask = 0

# ---- SPU model ----
class Voice:
	var inst: Dictionary
	var pcm: PackedFloat32Array
	var spw := 8
	var ls := -1          # loop start in words (-1 = one shot)
	var vol := 0
	var pan := 64
	var timer := 0
	var pos := 0.0

var voices: Dictionary = {}     # hw channel -> Voice
var master := 1.0

func apply_events() -> void:
	for e in events:
		var k: String = e[0]
		var c: int = e[1]
		if k == "on":
			var v := Voice.new()
			v.inst = e[2]; v.pcm = pcm(v.inst); v.spw = v.inst["spw"]
			v.ls = e[3]; v.vol = e[4]; v.timer = e[5]; v.pan = e[6]
			voices[c] = v
		elif k == "off": voices.erase(c)
		elif voices.has(c):
			var v: Voice = voices[c]
			if k == "timer": v.timer = e[2]
			elif k == "vol": v.vol = e[2]
			elif k == "pan": v.pan = e[2]
	events.clear()

## Mixes `n` stereo frames from the current voice state into `out` (interleaved L,R floats appended).
func mix(n: int, out: PackedVector2Array, off: int, interp: bool) -> void:
	for ci in voices.keys():
		var v: Voice = voices[ci]
		if v.timer <= 0: continue
		var step := (SPU_CLOCK / float(v.timer)) / float(MIX_RATE)
		var pcm_a := v.pcm
		var total := pcm_a.size()
		if total < 2: voices.erase(ci); continue
		var gl := float(v.vol) * float(127 - v.pan) / (127.0 * 127.0 * 2.0) * master
		var gr := float(v.vol) * float(v.pan) / (127.0 * 127.0 * 2.0) * master
		var pos := v.pos
		var looped := v.ls >= 0
		var lstart := 0
		var llen := 1
		if looped:
			lstart = maxi(0, (v.ls - 1) * 8) if v.spw == 8 else v.ls * v.spw
			lstart = clampi(lstart, 0, total - 2)
			llen = total - lstart
		var dead := false
		for i in n:
			if pos >= total:
				if looped: pos = lstart + fmod(pos - lstart, llen)
				else: dead = true; break
			var ip := int(pos)
			var s: float
			if interp and ip + 1 < total:
				var fr := pos - ip
				s = pcm_a[ip] * (1.0 - fr) + pcm_a[ip + 1] * fr
			else:
				s = pcm_a[ip]
			var o := out[off + i]
			out[off + i] = Vector2(o.x + s * gl, o.y + s * gr)
			pos += step
		v.pos = pos
		if dead: voices.erase(ci)
