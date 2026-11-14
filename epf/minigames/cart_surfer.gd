class_name CartSurferGame
extends CanvasLayer
## Cart Surfer (Normal), driven by the ROM's own data at runtime. Rules decoded from the ARM9 overlay and measured in
## DeSmuME (CLPE rev 2):
##  - the track is a chain of FLC movies (flc/straight1, leftInto/left/leftOut, rightInto/right/rightOut, end; table
##    built at 0x20db868); Normal is a fixed course of 8 turns alternating left/right, then the end segment
##  - a sign (Minigames/CartSurfer/Track/signLeft|signRight, 12 approach frames on a 256x192 canvas) shows 23 frames
##    before the turn; Into 36 frames, curve 38, Out 34, straight 303 frames to the next sign (first sign at 304)
##  - turn rules (handler 0x20d8fdc): entering the curve you must be leaning that way (lean, grind or surf-lean), letting
##    go of the lean inside the curve crashes (0x20d933c), leaving the turn still leaning scores
##  - player states (table 0x20d8880): CartAnimations/Cart_<state>, recoloured with palettes/cartsurfer_<colour>.nbfp
##  - 3 lives (HUD/cartLives), a crash costs one; at 0 the run is over
## Not decoded yet (provisional here): trick scoring, over-lean timing, hills and hazards (Extreme / later courses).
signal finished(score: int, completed: bool)
signal covered                        # the screen is fully white: the menu underneath can go

const VIEW := Vector2(256, 192)
const FLCS := ["straight1", "upInto", "up", "upOut", "downInto", "down", "downOut", "leftInto", "left", "leftOut",
	"rightInto", "right", "rightOut", "end"]
const COURSE := ["L", "R", "L", "R", "L", "R", "L", "R"]
const SIGN_LEAD := 23
const SURF_OVER_LEAN := 96.0
const OVER_LEAN := 85.0              # DS frames of leaning on a straight before the cart tips (DeSmuME: lean at 132,
                                     # OVER_LEAN at 217, CRASH at 246); turns do not count
const TURN_POINTS := 10
## Sounds (DeSmuME, sfx.bin ids): 132 starts 4 frames into a lean and is stopped when the lean ends (0x20d936d /
## 0x20d9399), 136 on a crash (0x20da415), 133 when the cart lands from a jump (0x20d9689). Entering, signs, the
## points pop-up and the finish play no sound effect.
const SND_LEAN := 132
const SND_LAND := 133
const SND_CRASH := 136
const SND_GRIND := 30                # DeSmuME: plays as GRIND_* starts, stopped when it ends
const SND_HAND_STAND := 80           # DeSmuME: on the up press that starts SURF_HAND_STAND
var _lean_snd_t := -1.0
## Controls and tricks, measured in DeSmuME on the opening straight (score at 0x22be434, frames = DS frames):
##  ground  A jump (0 pts, lands 58 later) | Up surf stance (goToSurf 25 frames, then stays; Down leaves it)
##          Down lean back (120 frames; Up cancels) | Left/Right lean (until released; A cancels it)
##  jump    Left/Right airTwist +80 (lands 79 after take-off) | Up fly +50 (lands 79) | Down slam +30 (lands 35)
##  surf    A surfJump +20 (lands 73) | Up (new press) handstand +80 (56) | Left/Right surf lean, 5 pts per 6 frames
##  surfJump Left/Right kickFlip +70 (lands 75) | Down tenEighty +80 (89) | Up superMan +80 (76)
##  leanBack A backFlip +100 (33) | Left/Right grind +50 (until released)
## One trick per jump; the turn check accepts lean, grind or surf lean in the turn's direction; surf leans and grinds
## never tip over. The landing sound (133) plays on every landing.
const AIR_TRICKS := {"ui_left": ["AIR_TWIST_LEFT", 80, 79], "ui_right": ["AIR_TWIST_RIGHT", 80, 79],
	"ui_up": ["FLY", 50, 79], "ui_down": ["SLAM", 30, 35]}
const SURF_AIR_TRICKS := {"ui_left": ["KICK_FLIP_LEFT", 70, 75], "ui_right": ["KICK_FLIP_RIGHT", 70, 75],
	"ui_down": ["TEN_EIGHTY", 80, 89], "ui_up": ["SUPER_MAN", 80, 76]}
const JUMP_LAND := 58
const SURF_JUMP_LAND := 73
const GO_TO_SURF_LEN := 25
const LEAN_BACK_LEN := 120
const BACK_FLIP_LEN := 33
const HAND_STAND_LEN := 56
var age := 0.0                        # DS frames in the current state
var air_t := 0.0                      # DS frames since take-off
var land_at := 0.0
var surf_air := false
var _surf_pts := 0.0
var _need_fresh := false              # DS: after (re-)entering, a direction held from before does nothing until let go

var world
var sfx
var text                              # TextTable (GameStrings): the score label is string 158
const S_SCORE := 158
var music                             # MusicPlayer: Cart Surfer's song is 12 (the only new song in RAM, DeSmuME)
const SONG := 12
var _song_on := false
var color := "blue"
var flc: Dictionary = {}             # name -> Array[ImageTexture]
var anims: Dictionary = {}           # state -> {tex, dur(frames), center}
var signs: Dictionary = {}           # "L"/"R" -> Array[ImageTexture]
var lives_tex: Array = []
var score_bg: Texture2D
var font

var root: Control
var track: TextureRect
var sign_rect: TextureRect
var cart: TextureRect
var lives_rect: TextureRect
var score_rect: TextureRect
var score_lbl: TextureRect
var msg: TextureRect
var pop: TextureRect                  # floating points after a turn
var white_track: ColorRect            # the light at the end of the tunnel (over the track, under the sprites)
var white_all: ColorRect
var bg: ColorRect
var _covered := false
var _end_t := -1.0
var pop_t := 0.0
var pop_on := false
var u := 1.0
var origin := Vector2.ZERO

## Opening (DeSmuME, frames from the control-choice tap): the menu fades to white over 8 frames, white holds while
## the game loads, the cart's ENTER starts at 17 (under the white), the track starts at 57, and the picture fades in
## from white over 15 frames from 63. Here t = 0 is the start of ENTER.
const PRE_ROLL := -17.0
const WHITE_FULL := -9.0
const FADE_IN_FROM := 46.0
const FADE_IN_LEN := 15.0
const TRACK_START := 40               # the track starts at DS frame 57 (under the white)
const ENTER_ANIM := 44.0              # the PLAYER_ENTER state is set at 17 but its 14x4-frame animation runs 61-117
var t := PRE_ROLL                     # DS frames since ENTER started
var events: Array = []               # [{type, sign, into, curve, out, end}]
var score := 0
var lives := 3
var state := "ENTER"
var st_i := 0
var st_t := 0.0
var lean_t := 0.0
var over := false
var done := false
var air := false
var tricked := false

func setup(w, s, col: String) -> void:
	world = w; sfx = s; color = col
	layer = 7
	for n in FLCS:
		var b: PackedByteArray = world.loc_bytes("flc/%s.flc" % n)
		var f := FlcPlayer.open(b) if b.size() > 0 else null
		var arr: Array = []
		if f != null:
			for i in f.frame_count:
				f.next_frame(); arr.append(ImageTexture.create_from_image(f.image()))
		flc[n] = arr
	_load_cart()
	signs["L"] = _frames("Minigames/CartSurfer/Track/signLeft")
	signs["R"] = _frames("Minigames/CartSurfer/Track/signRight")
	lives_tex = _frames("Minigames/CartSurfer/HUD/cartLives")
	var sb := _frames("Minigames/CartSurfer/HUD/scoreBackground")
	score_bg = sb[0] if sb.size() > 0 else null
	font = EpfFont.load_font(world.fs, "fonts/faceFront.fnt")
	_build_course()
	_build_ui()
	root.visible = false                  # pre-roll: the menu shows through while it fades to white
	state = "ENTER"; cart.visible = false
	get_tree().root.size_changed.connect(_layout)
	_layout()

func _frames(key: String) -> Array:
	var d: Dictionary = world.sprite(key)
	var out: Array = []
	for f in d.get("frames", []): out.append(ImageTexture.create_from_image(f["image"]))
	return out

## Cart_<state> sprites, recoloured: the stock art uses one palettes/cartsurfer_<c>.nbfp; swap it for the player's.
const STATES := {"IDLE": "", "ENTER": "_enter", "CRASH": "_crash", "LEAN_LEFT": "_leanLeft", "OVER_LEAN_LEFT": "_overLeanLeft",
	"LEAN_RIGHT": "_leanRight", "OVER_LEAN_RIGHT": "_overLeanRight", "JUMP": "_jump", "LEAN_BACK": "_leanBack",
	"AIR_TWIST_LEFT": "_airTwistLeft", "AIR_TWIST_RIGHT": "_airTwistRight", "BACK_FLIP": "_backFlip", "SUPER_MAN": "_superMan",
	"GO_TO_SURF": "_goToSurf", "SURF": "_surf", "FLY": "_fly", "SLAM": "_slam", "SURF_JUMP": "_surfJump",
	"KICK_FLIP_LEFT": "_kickFlipLeft", "KICK_FLIP_RIGHT": "_kickFlipRight", "TEN_EIGHTY": "_tenEighty",
	"SURF_HAND_STAND": "_surfHandStand", "SURF_LEAN_LEFT": "_surfLeanLeft", "SURF_LEAN_RIGHT": "_surfLeanRight",
	"GRIND_LEFT": "_grindLeft", "GRIND_RIGHT": "_grindRight",
	"SURF_OVER_LEAN_LEFT": "_surfOverLeanLeft", "SURF_OVER_LEAN_RIGHT": "_surfOverLeanRight"}
func _load_cart() -> void:
	var base := "Minigames/CartSurfer/CartAnimations/CartRed" if color == "red" else "Minigames/CartSurfer/CartAnimations/Cart"
	var remap := _palette_map(base)
	for s in STATES:
		var d: Dictionary = world.sprite(base + STATES[s])
		if d.is_empty() or d.get("frames", []).is_empty(): continue
		var a := {"tex": [], "dur": [], "center": Vector2(d.get("center", [0, 0])[0], d.get("center", [0, 0])[1])}
		for f in d["frames"]:
			var im: Image = f["image"]
			if not remap.is_empty(): im = _recolor(im, remap)
			a["tex"].append(ImageTexture.create_from_image(im))
			a["dur"].append(maxf(float(f["dur_ms"]) * 60.0 / 1000.0, 1.0))
		anims[s] = a

func _pal(c: String) -> Array:
	var b: PackedByteArray = world.fs.get_by_path("palettes/cartsurfer_%s.nbfp" % c)
	var out: Array = []
	for i in b.size() / 2:
		var v := b.decode_u16(i * 2)
		out.append(Color8(((v & 31) * 255) / 31, (((v >> 5) & 31) * 255) / 31, (((v >> 10) & 31) * 255) / 31))
	return out

## The stock Cart art draws the penguin in three greens (dark to light 004a00 007300 009c00); a colour's palette
## (palettes/cartsurfer_<c>.nbfp, 16 slots) keeps its body shades in slots 10-12, dark to light.
## CartRed (a red cart, for red penguins) draws the penguin with 005a00 for the darkest shade.
const BODY := [["004a00", "005a00"], ["007300"], ["009c00"]]
func _palette_map(_base: String) -> Dictionary:
	var dst := _pal(color)
	if dst.size() < 13: return {}
	var m := {}
	for i in 3:
		for k in BODY[i]: m[k] = dst[10 + i]
	return m

func _recolor(im: Image, m: Dictionary) -> Image:
	var o: Image = im.duplicate(); o.convert(Image.FORMAT_RGBA8)
	for y in o.get_height():
		for x in o.get_width():
			var c := o.get_pixel(x, y)
			if c.a < 0.5: continue
			var k: String = c.to_html(false)
			if m.has(k): var n: Color = m[k]; n.a = c.a; o.set_pixel(x, y, n)
	return o

## The track is a timeline of FLC frames with per-frame holds, measured in DeSmuME by matching every DS frame
## against the decoded movies (frames counted from the control-choice tap; t here = DS frame - 17):
##  - movies tick on a 4,2,4,2 rhythm (20 fps on average); the last frame of a segment absorbs the remainder
##  - the 8 turns' Into starts at DS frames 387 825 1263 1701 2137 2575 3011 3449 (the cycle wanders 436-438)
##  - Into lasts 37 frames (rhythm starting 4), the curve 38 and the Out 34 (rhythm starting 2)
##  - straight1 (12 frames, 36 per loop) fills the gaps; the end movie starts at 3669 (145 after the last Out)
##  - the sign appears 23 frames before each Into
const STRAIGHT_FRAMES := 12
const INTO_AT := [387, 825, 1263, 1701, 2137, 2575, 3011, 3449]
const END_AT := 3669
const DS_T0 := 16
const LEN_INTO := 37
const LEN_CURVE := 38
const LEN_OUT := 34
var timeline: Array = []              # [{name, start, frames, durs, event}]
var _tl_end := 0

## n holds alternating `first`/the other of 4 and 2, fitted to `total` frames (remainder on the last frame)
func _rhythm(n: int, total: int, first: int) -> Array:
	var d: Array = []
	var sum := 0
	for i in n:
		var h := first if i % 2 == 0 else 6 - first
		d.append(h); sum += h
	while sum > total and d.size() > 0:
		var cut := mini(d[-1] - 1, sum - total)
		if cut <= 0: break
		d[-1] -= cut; sum -= cut
	if sum < total: d[-1] += total - sum
	return d

func _push(name: String, durs: Array, ev, first := 0) -> void:
	var tot := 0
	for x in durs: tot += x
	timeline.append({"name": name, "start": _tl_end, "frames": durs.size(), "durs": durs, "event": ev, "first": first})
	_tl_end += tot

## Straight loops are phased to END exactly where the next segment begins (DeSmuME: the big arch passes 5 frames
## before each Into); a leftover shorter than a loop is the tail of a loop at the start of the gap.
func _straight_until(t_end: int) -> void:
	var gap := t_end - _tl_end
	if gap <= 0: return
	var full := _rhythm(STRAIGHT_FRAMES, 36, 4)
	var rem := gap % 36
	if rem > 0:
		var tail: Array = []; var acc := 0; var k := full.size() - 1
		while k >= 0 and acc < rem:
			tail.push_front(full[k]); acc += full[k]; k -= 1
		tail[0] -= acc - rem
		if tail[0] <= 0: tail.pop_front(); k += 1
		_push("straight1", tail, null, k + 1)
	for i in gap / 36: _push("straight1", full.duplicate(), null)

func _build_course() -> void:
	_tl_end = TRACK_START
	for k in COURSE.size():
		var d: String = COURSE[k]
		_straight_until(int(INTO_AT[k]) - DS_T0)
		var pre := "left" if d == "L" else "right"
		var e := {"type": d, "into": _tl_end}
		e["sign"] = _tl_end - SIGN_LEAD
		_push(pre + "Into", _rhythm(flc[pre + "Into"].size(), LEN_INTO, 4), e); e["curve"] = _tl_end
		_push(pre, _rhythm(flc[pre].size(), LEN_CURVE, 2), e); e["out"] = _tl_end
		_push(pre + "Out", _rhythm(flc[pre + "Out"].size(), LEN_OUT, 2), e); e["end"] = _tl_end
		events.append(e)
	_straight_until(END_AT - DS_T0)
	var ee := {"type": "END", "sign": -1, "into": _tl_end}
	var en: int = flc["end"].size()
	_push("end", _rhythm(en, (en / 2) * 6 + (en % 2) * 4, 4), ee)
	events.append(ee)

func _seg_total(sg: Dictionary) -> int:
	var tot := 0
	for x in sg["durs"]: tot += x
	return tot

func _tr() -> TextureRect:
	var r := TextureRect.new(); r.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	r.stretch_mode = TextureRect.STRETCH_SCALE; r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r); return r

func _build_ui() -> void:
	bg = ColorRect.new(); bg.color = Color.BLACK; bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	bg.visible = false
	root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	track = _tr(); sign_rect = _tr()
	white_track = ColorRect.new(); white_track.color = Color(1, 1, 1, 0); white_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(white_track)
	pop = _tr(); pop.visible = false; cart = _tr(); lives_rect = _tr(); score_rect = _tr(); score_lbl = _tr(); msg = _tr()
	white_all = ColorRect.new(); white_all.color = Color(1, 1, 1, 0); white_all.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white_all.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(white_all)
	score_rect.texture = score_bg
	_refresh_score()

func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	u = minf(win.x / VIEW.x, win.y / VIEW.y)
	origin = ((win - VIEW * u) * 0.5).floor()
	for r in [track, sign_rect, lives_rect, white_track]:
		r.position = origin; r.size = VIEW * u
	lives_rect.position = origin + Vector2(-1, -1) * u           # DS lives icons start at (4,4)
	_place_cart(); _refresh_score()

func _place(r: TextureRect, tex: Texture2D, pos: Vector2) -> void:
	r.texture = tex
	if tex == null: r.visible = false; return
	r.visible = true
	r.position = origin + pos.floor() * u
	r.size = Vector2(tex.get_width(), tex.get_height()) * u

func _refresh_score() -> void:
	if score_rect == null: return
	var ttx := ""
	if font != null:
		var lbl: String = text.get_text(S_SCORE).strip_edges() if text != null else ""
		var im: Image = font.render(("%s %d" % [lbl, score]).strip_edges(), Color.WHITE, 0, 0)
		var ur := im.get_used_rect()
		if ur.size.x > 0: score_lbl.texture = ImageTexture.create_from_image(im.get_region(ur)); ttx = "ok"
	if ttx != "":
		var sz := Vector2(score_lbl.texture.get_width(), score_lbl.texture.get_height())
		score_lbl.position = origin + Vector2(243.0 - sz.x, 14) * u; score_lbl.size = sz * u   # DS: right edge 242, top 14
	if lives_tex.size() > 0:
		lives_rect.texture = lives_tex[clampi(3 - lives, 0, lives_tex.size() - 1)]

# ---- player state ----
func _set_state(s: String) -> void:
	if not anims.has(s): s = "IDLE"
	# plain and surf leans both play the lean sound (DeSmuME: SURF_LEAN 182 -> sfx 132 at 186, stopped on release)
	var was_lean := _is_lean_state(state)
	var is_lean := _is_lean_state(s)
	if sfx != null:
		if was_lean and not is_lean: sfx.stop(SND_LEAN); _lean_snd_t = -1.0
		if is_lean and not was_lean: _lean_snd_t = 0.0
		if state.begins_with("GRIND") and not s.begins_with("GRIND"): sfx.stop(SND_GRIND)
		if s.begins_with("GRIND") and not state.begins_with("GRIND"): sfx.play(SND_GRIND)
		if s == "SURF_HAND_STAND": sfx.play(SND_HAND_STAND)
		if s == "CRASH": sfx.play(SND_CRASH)
	state = s; st_i = 0; st_t = 0.0; age = 0.0
	_place_cart()

func _is_lean_state(s: String) -> bool:
	return s.trim_prefix("SURF_").trim_prefix("OVER_").begins_with("LEAN_") and not s == "LEAN_BACK"

func _place_cart() -> void:
	if cart == null or not anims.has(state): return
	var a: Dictionary = anims[state]
	# DeSmuME: the riding cart spans x 107-148, y 104-178 (penguin + cart) - anchor (127,182)
	var dx := crash_dx if state == "CRASH" else 0.0
	_place(cart, a["tex"][st_i % a["tex"].size()], Vector2(127 + dx, 182) - a["center"])

func _anim_done() -> bool:
	var a: Dictionary = anims.get(state, {})
	return a.is_empty() or st_i >= a["tex"].size() - 1 and st_t >= a["dur"][st_i]

## A tip-over crash is thrown off the side it tipped to (DeSmuME: the crash plays ~56 px left of the rails after a
## left over-lean); a missed turn crashes on the rails (no offset).
var crash_dx := 0.0
func _crash() -> void:
	if state == "CRASH" or done: return
	crash_dx = 0.0
	if state.contains("OVER_LEAN"): crash_dx = -56.0 if state.ends_with("LEFT") else 56.0
	lives -= 1; air = false; pending = 0; lean_t = 0.0
	_set_state("CRASH"); _refresh_score()

func _opening() -> void:
	if t >= FADE_IN_FROM and not _song_on and music != null:
		_song_on = true; music.play_song(SONG)
	if t < WHITE_FULL: white_all.color.a = clampf((t - PRE_ROLL) / (WHITE_FULL - PRE_ROLL), 0.0, 1.0)
	elif t < FADE_IN_FROM: white_all.color.a = 1.0
	else: white_all.color.a = clampf(1.0 - (t - FADE_IN_FROM) / FADE_IN_LEN, 0.0, 1.0)
	if t >= WHITE_FULL and not _covered:
		_covered = true; bg.visible = true; root.visible = true; covered.emit()
	if t >= FADE_IN_FROM + FADE_IN_LEN - 0.5: white_all.color.a = 0.0

func _segment() -> Array:
	## [flc name, frame index, turn event] for the current time
	if t < TRACK_START: return ["straight1", 0, null]
	var seg: Dictionary = timeline[-1]
	for sg in timeline:
		if t < sg["start"] + _seg_total(sg): seg = sg; break
	var local := int(t) - int(seg["start"])
	var i := 0; var acc := 0
	for h in seg["durs"]:
		acc += h
		if local < acc: break
		i += 1
	return [seg["name"], int(seg.get("first", 0)) + mini(i, int(seg["frames"]) - 1), seg["event"]]

var _prev_seg := "straight1"
func _process(dt: float) -> void:
	if done: return
	var steps := dt * 60.0
	t += steps
	if t < FADE_IN_FROM + FADE_IN_LEN and _end_t < 0.0:
		_opening()
		if t < 0.0: return
	var sg := _segment()
	var name: String = sg[0]
	var frames: Array = flc[name]
	if frames.size() > 0: track.texture = frames[clampi(int(sg[1]), 0, frames.size() - 1)]
	_update_sign()
	_update_points(steps)
	_rules(name, sg[2])
	_prev_seg = name
	_input_state(steps)
	if t < ENTER_ANIM: return
	if not cart.visible and state == "ENTER" and st_i == 0 and st_t == 0.0: _set_state("ENTER")
	_animate(steps)
	if name == "end" and t >= float(timeline[-1]["start"] + _seg_total(timeline[-1])):
		_light(steps)

## Points pop-up (DeSmuME, every frame after the first turn): the value in faceFront, yellow (160,160,0), appears
## 5 frames after the turn ends at x 118-135, top y 72, keeps its size and rises steadily to top y 52 over 34 frames,
## then disappears (visible frames 498-532 for a turn ending at 493).
const POP_COLOR := Color8(160, 160, 0)
func _show_points(n: int) -> void:
	if font == null: return
	var im: Image = font.render(str(n), POP_COLOR, 0, 0)
	var ur := im.get_used_rect()
	if ur.size.x <= 0: return
	pop.texture = ImageTexture.create_from_image(im.get_region(ur))
	pop_t = -5.0; pop_on = true

func _update_points(steps: float) -> void:
	if not pop_on or pop.texture == null: pop.visible = false; return
	pop_t += steps
	if pop_t < 0.0: pop.visible = false; return
	if pop_t >= 35.0: pop.visible = false; pop_on = false; return
	var top := 72.0 - 20.0 * minf(pop_t / 34.0, 1.0)
	var sz := Vector2(pop.texture.get_width(), pop.texture.get_height())
	pop.visible = true
	pop.position = origin + Vector2(127.0 - floorf(sz.x * 0.5), floorf(top)) * u
	pop.size = sz * u

## Warning signs (DeSmuME, frame-by-frame on the first two turns): the sign rushes past three times before every turn,
## each pass playing its 12 approach frames on the track's 4,2 rhythm (36 frames), starting 145, 84 and 23 frames
## before the Into (first turn: visible from 257, 317 and 379 for an Into at 387; second: 698, 761, 822 for 825).
const SIGN_PASSES := [145, 84, 23]
func _update_sign() -> void:
	sign_rect.visible = false
	for e in events:
		if e["type"] == "END": continue
		var arr: Array = signs[e["type"]]
		if arr.is_empty(): continue
		for lead in SIGN_PASSES:
			var local := t - float(int(e["into"]) - int(lead))
			if local < 0.0 or local >= 36.0: continue
			var li := int(local)
			var i := mini((li / 6) * 2 + (1 if li % 6 >= 4 else 0), arr.size() - 1)
			sign_rect.texture = arr[i]; sign_rect.visible = true
			return

func _leaning(d: String) -> bool:
	var side := "LEFT" if d == "L" else "RIGHT"
	return state in ["LEAN_" + side, "GRIND_" + side, "SURF_LEAN_" + side]

var _turn = null                     # the turn being ridden (its event), kept until the straight after it
func _rules(name: String, e) -> void:
	if e != null: _turn = e
	if state in ["CRASH", "ENTER"]: return
	if name != _prev_seg and _turn != null:
		var d: String = _turn["type"]
		if name in ["left", "right"] and not _leaning(d): _crash(); return          # into the curve: must lean
		if name == "straight1" and _prev_seg.ends_with("Out"):
			if _leaning(d):                                                          # still leaning as the turn ends
				score += TURN_POINTS; _refresh_score(); _show_points(TURN_POINTS)
			_turn = null
	if name in ["left", "right"] and e != null and not _leaning(e["type"]) and not air:
		_crash(); return                                                              # let go inside the curve

## Trick points are held until the trick is finished (landing, end of a back flip or handstand, letting go of a
## grind or surf lean) and lost on a crash (DeSmuME: an air twist's 80 reaches the score 10 frames after landing,
## a surf lean's points when it is let go, and a surf lean that tips over scores nothing).
var pending := 0
func _pts(n: int) -> void:
	pending += n

func _bank() -> void:
	if pending == 0: return
	score += pending; pending = 0; _refresh_score()

func _land(to: String) -> void:
	air = false
	_bank()
	if sfx != null: sfx.play(SND_LAND)
	_set_state(to)

func _input_state(steps: float) -> void:
	if state in ["CRASH", "ENTER"] or done: return
	age += steps
	var l := Input.is_action_pressed("ui_left"); var r := Input.is_action_pressed("ui_right")
	var up := Input.is_action_pressed("ui_up"); var dn := Input.is_action_pressed("ui_down")
	if _need_fresh:
		if not (l or r or up or dn): _need_fresh = false
		else:
			l = Input.is_action_just_pressed("ui_left"); r = Input.is_action_just_pressed("ui_right")
			up = Input.is_action_just_pressed("ui_up"); dn = Input.is_action_just_pressed("ui_down")
			if l or r or up or dn: _need_fresh = false
	var a_hit := Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_select")
	# ---- in the air ----
	if air:
		air_t += steps
		if not tricked:
			var table: Dictionary = SURF_AIR_TRICKS if surf_air else AIR_TRICKS
			for k in table:
				if Input.is_action_just_pressed(k):
					var tr: Array = table[k]
					tricked = true; _set_state(tr[0]); _pts(int(tr[1])); land_at = float(tr[2])
					break
		# an air twist settles back into the jump pose before landing (DS: twist 151 -> jump 193 -> land 220)
		if state.begins_with("AIR_TWIST") and age >= 42.0: _set_state("JUMP"); age = 42.0
		if air_t >= land_at: _land("SURF" if surf_air else "IDLE")
		return
	if state.contains("OVER_LEAN"): return
	# ---- timed ground states ----
	match state:
		"GO_TO_SURF":
			if age >= GO_TO_SURF_LEN: _set_state("SURF")
			return
		"BACK_FLIP":
			if age >= BACK_FLIP_LEN: _bank(); _set_state("IDLE")
			return
		"SURF_HAND_STAND":
			if age >= HAND_STAND_LEN: _bank(); _set_state("SURF")
			return
	# ---- surf stance ----
	if state == "SURF" or state.begins_with("SURF_LEAN"):
		if a_hit:
			air = true; tricked = false; surf_air = true; air_t = 0.0; land_at = SURF_JUMP_LAND
			_pts(20); _set_state("SURF_JUMP"); return
		if dn: _set_state("IDLE"); return
		if Input.is_action_just_pressed("ui_up") and state == "SURF": _pts(80); _set_state("SURF_HAND_STAND"); return
		var sw := "SURF"
		if l and not r: sw = "SURF_LEAN_LEFT"
		elif r and not l: sw = "SURF_LEAN_RIGHT"
		if sw != state:
			if sw == "SURF": _bank()                               # surf lean let go: its points count
			lean_t = 0.0; _set_state(sw)
		if state.begins_with("SURF_LEAN"):
			_surf_pts += steps * 5.0 / 6.0
			if _surf_pts >= 1.0: var n := int(_surf_pts); _surf_pts -= n; _pts(n)
			# a surf lean on a straight tips too, later than a plain lean (DS: lean 182, tip 278, crash 295)
			if _prev_seg == "straight1":
				lean_t += steps
				if lean_t >= SURF_OVER_LEAN: _set_state(state.replace("SURF_LEAN", "SURF_OVER_LEAN"))
		return
	# ---- lean back ----
	if state == "LEAN_BACK" or state.begins_with("GRIND"):
		if state == "LEAN_BACK":
			if a_hit: _pts(100); _set_state("BACK_FLIP"); return
			if Input.is_action_just_pressed("ui_up") or age >= LEAN_BACK_LEN: _set_state("IDLE"); return
			if l and not r: _pts(50); _set_state("GRIND_LEFT"); return
			if r and not l: _pts(50); _set_state("GRIND_RIGHT"); return
			return
		if (state == "GRIND_LEFT" and not l) or (state == "GRIND_RIGHT" and not r): _bank(); _set_state("IDLE")
		return
	# ---- plain riding / leaning ----
	if state.begins_with("LEAN_"):
		if a_hit: _set_state("IDLE"); return                    # A breaks a lean (in a curve that is a crash)
		if (state == "LEAN_LEFT" and not l) or (state == "LEAN_RIGHT" and not r): _set_state("IDLE")
		elif _prev_seg == "straight1":
			lean_t += steps                                         # leaning on a straight tips the cart over
			if lean_t >= OVER_LEAN: _set_state("OVER_" + state)
		return
	lean_t = 0.0
	if a_hit:
		air = true; tricked = false; surf_air = false; air_t = 0.0; land_at = JUMP_LAND
		_set_state("JUMP"); return
	if l and not r: _set_state("LEAN_LEFT")
	elif r and not l: _set_state("LEAN_RIGHT")
	elif Input.is_action_just_pressed("ui_down"): _set_state("LEAN_BACK")
	elif Input.is_action_just_pressed("ui_up"): _set_state("GO_TO_SURF")

func _animate(steps: float) -> void:
	if _lean_snd_t >= 0.0:
		_lean_snd_t += steps
		if _lean_snd_t >= 4.0:
			_lean_snd_t = -1.0
			if sfx != null: sfx.play(SND_LEAN)
	var a: Dictionary = anims.get(state, {})
	if a.is_empty(): return
	st_t += steps
	while st_t >= a["dur"][st_i]:
		st_t -= a["dur"][st_i]
		if st_i + 1 < a["tex"].size(): st_i += 1; continue
		# one-shot states end here
		match state:
			"ENTER":
				_need_fresh = true; _set_state("IDLE"); return
			"CRASH":
				if lives <= 0: _finish(false); return
				_set_state("ENTER"); return
			"OVER_LEAN_LEFT", "OVER_LEAN_RIGHT", "SURF_OVER_LEAN_LEFT", "SURF_OVER_LEAN_RIGHT": _crash(); return
			"IDLE", "SURF", "LEAN_BACK":
				st_i = 0                                  # riding poses loop
			# leans play their lean-in once and hold the last (fully leaned) frame (DeSmuME: no return to upright
			# before an over-lean); one-shot poses hold their last frame too; timers decide what comes next
			_:
				st_t = 0.0; break                         # one-shot poses hold their last frame; timers decide
	_place_cart()

## End of the course (DeSmuME): the end movie plays to its last frame (the cart rolls into the opening), holds it
## 43 frames while the tunnel whites out from 8 frames in (the HUD and the cart stay on top), then the whole screen
## goes white over 15 frames and the results come up.
const LIGHT_HOLD := 43.0
const LIGHT_FROM := 8.0
const LIGHT_ALL := 15.0
func _light(steps: float) -> void:
	if _end_t < 0.0:
		_end_t = 0.0
		if sfx != null: sfx.stop(SND_LEAN); sfx.stop(SND_GRIND)
	_end_t += steps
	white_track.color.a = clampf((_end_t - LIGHT_FROM) / (LIGHT_HOLD - LIGHT_FROM), 0.0, 1.0)
	white_all.color.a = clampf((_end_t - LIGHT_HOLD) / LIGHT_ALL, 0.0, 1.0)
	if _end_t >= LIGHT_HOLD + LIGHT_ALL and not done:
		done = true
		finished.emit(score, true)

func _finish(completed: bool) -> void:
	if done: return
	done = true
	if sfx != null: sfx.stop(SND_LEAN); sfx.stop(SND_GRIND)
	# out of lives (or Esc): a short pause, then the results screen (heading from GameStrings, see menus.gd)
	var tw := create_tween(); tw.tween_interval(1.5)
	tw.tween_callback(func() -> void: finished.emit(score, completed))

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and not done:
		get_viewport().set_input_as_handled(); _finish(false)
