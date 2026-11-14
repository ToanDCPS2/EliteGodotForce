class_name MainMenu
extends CanvasLayer
## Main menu + sub menus (single-screen 16:9 rebuild of the DS bottom-screen menus; layout code in 0x209aa18).
## Online/wireless entries (DGamer, Upload/Download, Wi-Fi) are removed. Strings are the ROM's GameStrings (English).
signal start_game(new_game: bool)
signal back_to_title
signal lang_changed(lang: String)
signal settings_changed
signal start_minigame(game: String, opts: Dictionary)
var on_screen := Callable()   # called on every screen change (white flash)
var on_click := Callable()    # button pressed (UI click SFX)
const LB := Vector2(64, 12)   # 256x192 DS screen centred in the 384x216 view
const VIEW := Vector2(384, 216)
const _Pack := preload("res://epf/rom/epf_pack.gd")
var SAVE: String = _Pack.save_path("save.json")      # <game folder>/saves/
const S_MISSIONS := 68; const S_MULTI := 69; const S_MINIGAMES := 71; const S_CREDITS := 12; const S_BACK := 76
const S_START := 64; const S_CONTINUE := 65; const S_ERASE := 66; const S_ERASE_ASK := 67
const S_CHOOSE_PLAYERS := 895; const S_2P := 796; const S_3P := 797; const S_4P := 798
const S_MINIS := [803, 804, 805, 806, 807, 808]

class Btn:
	extends RefCounted
	var rect: Rect2
	var spr: Sprite2D
	var up: Array = []
	var durs: Array = []
	var down: Texture2D
	var i := 0
	var t := 0.0
	var enabled := true
	var cb: Callable
	var animated := true

var world: RomWorld
var text: TextTable
var fonts := {}
var root := Node2D.new()
var scr := Node2D.new()
var btns: Array = []
var els: Array = []            # {img, pos, a} for snapshot()
var pressed: Btn = null
var hovering := false
var screen := ""
var credits_node: Sprite2D
var credits_h := 0.0
var credits_y := 0.0
var _imgcache := {}
var settings: Dictionary = {}
var player_name := ""
var player_color := "blue"

func setup(w: RomWorld, tt: TextTable) -> void:
	world = w; text = tt
	layer = 5
	root.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	add_child(root); root.add_child(scr)
	for f in ["Comicrazy", "faceFront", "tinyUI"]: fonts[f] = EpfFont.load_font(w.fs, "fonts/%s.fnt" % f)
	get_tree().root.size_changed.connect(_layout); _layout()
	# DS order (checked in an emulator): no profile -> colour, name, confirm -> profile card -> main menu
	if has_profile(): show_profile()
	else: show_color()

# ---------- helpers ----------
func _str(i: int) -> String: return text.get_text(i)

func _clear() -> void:
	if on_screen.is_valid(): on_screen.call()
	for c in scr.get_children(): c.queue_free()
	btns.clear(); els.clear(); pressed = null; credits_node = null; anims.clear()

func _tex(img: Image) -> ImageTexture: return ImageTexture.create_from_image(img)

func _add_img(img: Image, pos: Vector2, a := 1.0) -> Sprite2D:
	var s := Sprite2D.new(); s.centered = false; s.texture = _tex(img); s.position = pos; s.modulate.a = a
	scr.add_child(s); els.append({"img": img, "pos": pos, "a": a}); return s

func _text(font: String, s: String, pos: Vector2, color := Color.WHITE, wrap_w := 0, align := 0, a := 1.0) -> Sprite2D:
	var f: EpfFont = fonts[font]
	return _add_img(f.render(s, color, wrap_w, align), pos, a)

func _text_c(font: String, s: String, center: Vector2, color := Color.WHITE, wrap_w := 0, a := 1.0) -> void:
	var f: EpfFont = fonts[font]
	var sz := f.measure(s, wrap_w)
	_text(font, s, center - Vector2(sz) * 0.5, color, wrap_w, 1, a)

func _frames(key: String) -> Array:
	if _imgcache.has(key): return _imgcache[key]
	var d := world.sprite(key); var out: Array = []
	if not d.is_empty(): out = d["frames"]
	_imgcache[key] = out; return out

## Panel background = the ROM's Menus_bottom art, 9-sliced to 384x216.
func _panel(size := Vector2i(384, 216), flat := false) -> void:
	var src := EpfNbfc.load_bg(world, "bg/Menus/Menus_bottom")
	if flat:   # profile screen: the frame over the plain backdrop colour (the gradient centre is not shown on the DS)
		src = src.duplicate(); var edge := src.get_pixel(14, src.get_height() / 2)
		src.fill_rect(Rect2i(12, 12, src.get_width() - 24, src.get_height() - 24), edge)
	var m := 12
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var sw := src.get_width(); var sh := src.get_height()
	var parts := [
		[Rect2i(0, 0, m, m), Vector2i(0, 0), Vector2i(m, m)],
		[Rect2i(sw - m, 0, m, m), Vector2i(size.x - m, 0), Vector2i(m, m)],
		[Rect2i(0, sh - m, m, m), Vector2i(0, size.y - m), Vector2i(m, m)],
		[Rect2i(sw - m, sh - m, m, m), Vector2i(size.x - m, size.y - m), Vector2i(m, m)],
		[Rect2i(m, 0, sw - 2 * m, m), Vector2i(m, 0), Vector2i(size.x - 2 * m, m)],
		[Rect2i(m, sh - m, sw - 2 * m, m), Vector2i(m, size.y - m), Vector2i(size.x - 2 * m, m)],
		[Rect2i(0, m, m, sh - 2 * m), Vector2i(0, m), Vector2i(m, size.y - 2 * m)],
		[Rect2i(sw - m, m, m, sh - 2 * m), Vector2i(size.x - m, m), Vector2i(m, size.y - 2 * m)],
		[Rect2i(m, m, sw - 2 * m, sh - 2 * m), Vector2i(m, m), Vector2i(size.x - 2 * m, size.y - 2 * m)]]
	for p in parts:
		var piece := src.get_region(p[0])
		piece.resize(p[2].x, p[2].y, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), p[1])
	_add_img(out, Vector2.ZERO)

## Button from `<key>_up` (animated) / `<key>_down`. pos = top-left of the cropped button art. crop=true trims to the sprite's used area.
func _btn(key: String, pos: Vector2, cb: Callable, crop := true, enabled := true) -> Btn:
	var up := _frames(key + "_up"); var dn := _frames(key + "_down")
	if up.is_empty(): up = _frames(key)            # e.g. UI/MinigameInstructionsMenu/Arrow_forward (+ _down)
	var b := Btn.new(); b.cb = cb; b.enabled = enabled
	if up.is_empty(): return b
	var u := Rect2i()
	if crop:
		u = (up[0]["image"] as Image).get_used_rect()
		for f in up: u = u.merge((f["image"] as Image).get_used_rect())
		for f in dn: u = u.merge((f["image"] as Image).get_used_rect())
	else: u = Rect2i(Vector2i.ZERO, (up[0]["image"] as Image).get_size())
	for f in up:
		b.up.append(_tex((f["image"] as Image).get_region(u))); b.durs.append(maxf(float(f["dur_ms"]), 16.0))
	if not dn.is_empty(): b.down = _tex((dn[0]["image"] as Image).get_region(u))
	b.spr = Sprite2D.new(); b.spr.centered = false; b.spr.texture = b.up[0]; b.spr.position = pos
	b.spr.modulate = Color.WHITE if enabled else Color(0.42, 0.42, 0.42, 0.85)   # greyed out when unavailable
	scr.add_child(b.spr)
	els.append({"img": (up[0]["image"] as Image).get_region(u), "pos": pos, "a": 1.0 if enabled else 0.45})
	b.rect = Rect2(pos, Vector2(u.size))
	btns.append(b); return b

func _back_arrow(cb: Callable) -> void:
	_btn("UI/arrowBack", Vector2(8, 8), cb)

# ---------- screens ----------
func show_main() -> void:
	_clear(); screen = "main"; _panel()
	var xs := [48.0, 155.0, 262.0]
	var keys := ["UI/MainMenu/MainMenu_1player", "UI/MainMenu/MainMenu_2player", "UI/MainMenu/MainMenu_Options"]
	var labs := [S_MISSIONS, S_MULTI, S_MINIGAMES]
	var cbs := [func() -> void: start_game.emit(not read_save().has("mission")), show_multi, show_minigames]
	for i in 3:
		var b := _btn(keys[i], Vector2(xs[i], 46), cbs[i])
		var dy := roundf(102.0 - (46.0 + b.rect.size.y))
		b.spr.position.y += dy; b.rect.position.y += dy; els[els.size() - 1]["pos"].y += dy
		_text_c("Comicrazy", _str(labs[i]), Vector2(b.rect.position.x + b.rect.size.x * 0.5, 126))
	var cr := _btn("UI/MainMenu/creditsBttn", Vector2(108, 168), show_credits)
	_text_c("Comicrazy", _str(S_CREDITS), cr.rect.get_center() + Vector2(0, -2))
	var op := _btn("UI/MainMenu/creditsBttn", Vector2(208, 168), show_options)
	_text_c("Comicrazy", OPTIONS_LABEL.get(settings.get("lang", "en"), "Options"), op.rect.get_center() + Vector2(0, -2))
	_back_arrow(func(): back_to_title.emit())

func _big_button(label: String, pos: Vector2, cb: Callable, enabled := true) -> void:
	var b := _btn("UI/buttonBig", pos, cb, false, enabled)
	_text_c("faceFront", label, b.rect.get_center() + Vector2(0, -1), Color.WHITE, 0, 1.0 if enabled else 0.6)

func has_save() -> bool: return FileAccess.file_exists(SAVE)
func read_save() -> Dictionary:
	if not has_save(): return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	return j if j is Dictionary else {}
func has_profile() -> bool: return read_save().has("name")
## New profile: name + colour + 100 coins, no story progress yet.
func write_save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify({"name": player_name, "color": player_color, "coins": 100}))
func erase_save() -> void:
	if has_save(): DirAccess.remove_absolute(SAVE)

func show_missions() -> void:
	_clear(); screen = "missions"; _panel()
	_text_c("Comicrazy", _str(S_MISSIONS), Vector2(192, 34))
	var x := floorf((VIEW.x - 221.0) * 0.5)
	_big_button(_str(S_START), Vector2(x, 62), show_color)
	_big_button(_str(S_CONTINUE), Vector2(x, 100), func(): start_game.emit(false), has_save())
	_big_button(_str(S_ERASE), Vector2(x, 138), show_erase, has_save())
	_back_arrow(show_main)

func show_erase() -> void:
	_clear(); screen = "erase"; _panel()
	_text_c("faceFront", _str(S_ERASE_ASK), Vector2(192, 70), Color.WHITE, 280)
	var x := floorf((VIEW.x - 221.0) * 0.5)
	_big_button(_str(S_ERASE), Vector2(x, 100), func(): erase_save(); player_name = ""; show_color())
	_big_button(_str(S_BACK), Vector2(x, 138), show_missions)
	_back_arrow(show_missions)

## Mini Games (DS: UI/MinigameMenu/<game>Button_up, each a 256x192 canvas with the button at its spot on the bottom
## screen, measured 5 px lower in DeSmuME). Games the port does not have yet are greyed out and do nothing.
const MINIGAMES := [["SnowBoarding", ""], ["CartSurfer", "cartsurfer"], ["IceFishing", ""],
	["JetPack", ""], ["DanceChallenge", ""], ["Snowcat", ""]]
const DS_OFF := Vector2(64, 12)        # the DS 256x192 screen centred in the 384x216 menu view
func show_minigames() -> void:
	_clear(); screen = "minigames"; _panel()
	_text_c("Comicrazy", _str(S_MINIGAMES), DS_OFF + Vector2(128, 9))
	for g in MINIGAMES:
		var key := "UI/MinigameMenu/%sButton" % g[0]
		var fr := _frames(key + "_up")
		if fr.is_empty(): continue
		var ur := (fr[0]["image"] as Image).get_used_rect()
		for f in fr: ur = ur.merge((f["image"] as Image).get_used_rect())
		var ok: bool = g[1] != ""
		var cb := Callable()
		match g[1]:
			"cartsurfer": cb = show_cart_surfer
		_btn(key, DS_OFF + Vector2(0, 5) + Vector2(ur.position), cb if ok else func() -> void: pass, true, ok)
	_back_arrow(show_main)

# ---- two-pane minigame screens: the DS top-screen art on the left, the DS bottom-screen menu as a column on the right
const ART_RECT := Rect2(12, 34, 192, 144)      # 256x192 art at 3/4, smoothly downscaled, in a thin frame
const COL_X := 216.0
const COL_W := 158.0
func _art(img: Image) -> void:
	if img == null: return
	var im := img.duplicate(); im.convert(Image.FORMAT_RGBA8)
	im.resize(int(ART_RECT.size.x), int(ART_RECT.size.y), Image.INTERPOLATE_LANCZOS)
	var fr := Image.create(int(ART_RECT.size.x) + 4, int(ART_RECT.size.y) + 4, false, Image.FORMAT_RGBA8)
	fr.fill(Color8(8, 32, 72))
	fr.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(2, 2))
	_add_img(fr, ART_RECT.position - Vector2(2, 2))

## UI/buttonBig cut to a narrower width (its rounded ends kept, the middle shortened)
func _key_out(img: Image) -> Image:
	var im: Image = img.duplicate(); im.convert(Image.FORMAT_RGBA8)
	var k := im.get_pixel(0, 0)
	if k.a < 0.5: return im
	for yy in im.get_height():
		for xx in im.get_width():
			if im.get_pixel(xx, yy).is_equal_approx(k): im.set_pixel(xx, yy, Color(0, 0, 0, 0))
	return im

func _slim(img: Image, w: int) -> Image:
	var src := img.duplicate(); src.convert(Image.FORMAT_RGBA8)
	var h: int = src.get_height(); var cap := 14
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(src, Rect2i(0, 0, cap, h), Vector2i.ZERO)
	var mid: Image = src.get_region(Rect2i(cap, 0, src.get_width() - 2 * cap, h))
	mid.resize(w - 2 * cap, h, Image.INTERPOLATE_NEAREST)
	out.blit_rect(mid, Rect2i(Vector2i.ZERO, mid.get_size()), Vector2i(cap, 0))
	out.blit_rect(src, Rect2i(src.get_width() - cap, 0, cap, h), Vector2i(w - cap, 0))
	return out

func _col_button(label: String, y: float, cb: Callable, enabled := true) -> void:
	var up := _frames("UI/buttonBig_up"); var dn := _frames("UI/buttonBig_down")
	if up.is_empty(): up = _frames("UI/buttonBig")
	if up.is_empty(): return
	var w := int(COL_W)
	var b := Btn.new(); b.cb = cb; b.enabled = enabled
	var uimg := _slim(up[0]["image"], w)
	b.up.append(_tex(uimg)); b.durs.append(100.0)
	if not dn.is_empty(): b.down = _tex(_slim(dn[0]["image"], w))
	var pos := Vector2(COL_X, y)
	b.spr = Sprite2D.new(); b.spr.centered = false; b.spr.texture = b.up[0]; b.spr.position = pos
	b.spr.modulate = Color.WHITE if enabled else Color(0.42, 0.42, 0.42, 0.85)
	scr.add_child(b.spr)
	els.append({"img": uimg, "pos": pos, "a": 1.0 if enabled else 0.45})
	b.rect = Rect2(pos, Vector2(uimg.get_size()))
	btns.append(b)
	_text_c("faceFront", label, b.rect.get_center() + Vector2(0, -1), Color.WHITE, 0, 1.0 if enabled else 0.6)

func _col_text(font: String, t: String, y: float, wrap := 0) -> float:
	## centred in the right column; returns the y below it
	var f: EpfFont = fonts[font]
	var sz := f.measure(t, wrap if wrap > 0 else int(COL_W))
	_text(font, t, Vector2(COL_X + floorf((COL_W - sz.x) * 0.5), y), Color.WHITE, wrap if wrap > 0 else int(COL_W), 1)
	return y + sz.y

# ---- Cart Surfer front end: title (Play / Instructions, high score, medals) -> difficulty -> controls ----
const S_PLAY := 62; const S_INSTRUCTIONS := 63; const S_HIGH := 452; const S_MEDAL_SILVER := 462; const S_MEDAL_GOLD := 461
const S_CS_PAD := 403; const S_CS_TOUCH := 404; const S_CS_NORMAL := 407; const S_CS_EXTREME := 408
const S_CS_HELP := [374, 375, 376, 377, 378]
var MINI_SAVE: String = _Pack.save_path("minigames.json")
func mini_scores() -> Dictionary:
	if not FileAccess.file_exists(MINI_SAVE): return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(MINI_SAVE))
	return j if j is Dictionary else {}
func set_mini_score(game: String, sc: int) -> void:
	var d := mini_scores()
	if sc <= int(d.get(game, 0)): return
	d[game] = sc
	var f := FileAccess.open(MINI_SAVE, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(d))

func _fmt_num(t: String, n: int) -> String:
	for k in ["%d", "%i", "%s"]:
		if t.contains(k): return t.replace(k, str(n))
	return t.strip_edges() + " " + str(n)

func show_cart_surfer() -> void:
	_clear(); screen = "cartsurfer"; _panel()
	_art(_loc_bg("bg/CartSurfer/CartSurferTitleScreen"))
	var y := 30.0
	y = _col_text("faceFront", _fmt_num(_str(S_HIGH), int(mini_scores().get("cartsurfer", 0))), y) + 10.0
	for m in [[S_MEDAL_SILVER, "silver"], [S_MEDAL_GOLD, "gold"]]:
		var tr := _frames("UI/MinigameResultsMenu/Trophies/Small/CartSurfer_" + m[1])
		var tw := 0.0
		if not tr.is_empty():
			var ti: Image = _key_out(tr[0]["image"]); var r := ti.get_used_rect()
			if r.size.x > 0:      # ribbon + medal (~22x45): shown at 22 px tall beside its name
				var ic := ti.get_region(r); var hh := 22
				ic.resize(maxi(1, roundi(r.size.x * hh / float(r.size.y))), hh, Image.INTERPOLATE_LANCZOS)
				_add_img(ic, Vector2(COL_X + 2, y)); tw = ic.get_width() + 6.0
		var f: EpfFont = fonts["tinyUI"]
		var t := _str(m[0]).replace("%", "").strip_edges()
		var sz := f.measure(t, int(COL_W - tw))
		_text("tinyUI", t, Vector2(COL_X + tw, y + floorf((22.0 - sz.y) * 0.5)), Color.WHITE, int(COL_W - tw), 0)
		y += 28.0
	_col_button(_str(S_PLAY), 146, show_cs_difficulty)
	_col_button(_str(S_INSTRUCTIONS), 180, func() -> void: show_cs_help(0))
	_back_arrow(show_minigames)

## minigame title screens are localised by suffix (CartSurferTitleScreen_en; the plain one is French)
func _loc_bg(base: String) -> Image:
	return EpfNbfc.load_bg(world, base)      # load_bg picks the language version (RomWorld.loc_path)

func show_cs_difficulty() -> void:
	_clear(); screen = "cs_difficulty"; _panel()
	_art(_loc_bg("bg/CartSurfer/CartSurferTitleScreen"))
	_col_button(_str(S_CS_NORMAL), 60, func() -> void: show_cs_controls("normal"))
	_col_button(_str(S_CS_EXTREME), 96, func() -> void: pass, false)     # not decoded yet
	_col_button(_str(S_BACK), 170, show_cart_surfer)
	_back_arrow(show_cart_surfer)

func show_cs_controls(mode: String) -> void:
	_clear(); screen = "cs_controls"; _panel()
	_art(_loc_bg("bg/CartSurfer/CartSurferTitleScreen"))
	_col_button(_str(S_CS_PAD), 60, func() -> void: start_minigame.emit("cartsurfer", {"mode": mode, "controls": "pad"}))
	_col_button(_str(S_CS_TOUCH), 96, func() -> void: pass, false)        # touch controls not in yet
	_col_button(_str(S_BACK), 170, show_cs_difficulty)
	_back_arrow(show_cs_difficulty)

## Results (DS: bg/CartSurfer/Results/Results_top on the top screen, the coin panel and buttons on the bottom).
## Coins earned = score / 10 (DeSmuME: 80 points -> 8 coins). Upload Coins and Shop are not in the port.
const S_GAME_OVER := 444; const S_EARNED := 453; const S_NOW_HAVE := 454; const S_COINS_WORD := 455
const S_NEW_HIGH := 603; const S_RES_CONTINUE := 448; const S_UPLOAD := 449; const S_SHOP := 450
func show_cs_results(score: int, earned: int, total: int, new_high: bool, completed: bool) -> void:
	_clear(); screen = "cs_results"; _panel()
	_art(_loc_bg("bg/CartSurfer/Results/Results_top"))
	var y := 14.0
	if not completed: y = _col_text("faceFront", _str(S_GAME_OVER), y) + 3.0
	if new_high: y = _col_text("faceFront", _str(S_NEW_HIGH), y) + 4.0
	y = _col_text("faceFront", "%s %d %s" % [_str(S_EARNED).strip_edges(), earned, _str(S_COINS_WORD)], y) + 3.0
	_col_text("faceFront", "%s %d %s" % [_str(S_NOW_HAVE).strip_edges(), total, _str(S_COINS_WORD)], y)
	_col_button(_str(S_UPLOAD), 128, func() -> void: pass, false)
	_col_button(_str(S_SHOP), 154, func() -> void: pass, false)
	_col_button(_str(S_RES_CONTINUE), 180, show_cart_surfer)

## add coins to the profile save (minigames pay into the same purse as the story)
func add_coins(n: int) -> int:
	var sv := read_save()
	var total := int(sv.get("coins", 100)) + n
	sv["coins"] = total
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(sv))
	return total

func show_cs_help(i: int) -> void:
	_clear(); screen = "cs_help"; _panel()
	_art(EpfNbfc.load_bg(world, "bg/CartSurfer/Instructions/CartSurfer_1player_%d" % (i + 1)))
	var t := _str(S_CS_HELP[i])
	var fn := "faceFront"
	var sz: Vector2 = (fonts[fn] as EpfFont).measure(t, int(COL_W))
	if sz.y > 150.0:
		fn = "tinyUI"; sz = (fonts[fn] as EpfFont).measure(t, int(COL_W))
	_col_text(fn, t, maxf(8.0, floorf(ART_RECT.get_center().y - 14.0 - sz.y * 0.5)))
	var nxt := func() -> void: (show_cs_help(i + 1) if i + 1 < S_CS_HELP.size() else show_cart_surfer())
	var prv := func() -> void: (show_cs_help(i - 1) if i > 0 else show_cart_surfer())
	var fb := _btn("UI/MinigameInstructionsMenu/Arrow_forward", Vector2.ZERO, nxt, true)
	_move_btn(fb, Vector2(VIEW.x - fb.rect.size.x - 8, VIEW.y - fb.rect.size.y - 6))
	var bb := _btn("UI/MinigameInstructionsMenu/Arrow_back", Vector2.ZERO, prv, true)
	_move_btn(bb, Vector2(COL_X, VIEW.y - bb.rect.size.y - 6))
	_text_c("tinyUI", "%d / %d" % [i + 1, S_CS_HELP.size()], Vector2(COL_X + COL_W * 0.5, VIEW.y - 18))
	_back_arrow(show_cart_surfer)

func _move_btn(b: Btn, pos: Vector2) -> void:
	if b.spr == null: return
	var d := pos - b.rect.position
	b.spr.position += d; b.rect.position += d
	for e in els:
		if e["img"] == null: continue
	els[els.size() - 1]["pos"] = pos

func show_multi() -> void:
	_clear(); screen = "multi"; _panel()
	_text_c("Comicrazy", _str(S_CHOOSE_PLAYERS), Vector2(192, 30))
	var x := floorf((VIEW.x - 221.0) * 0.5)
	var ids := [S_2P, S_3P, S_4P]
	for i in 3: _big_button(_str(ids[i]), Vector2(x, 56.0 + i * 38.0), func(): pass, false)
	_text_c("faceFront", "Wireless play is not in the PC port", Vector2(192, 184), Color(1, 1, 1), 340, 0.7)
	_back_arrow(show_main)

const CREDIT_IDS := [258, 259, 260, 261, 262, 263, 265, 266, 267, 268, 269, 270, 545, 546, 550, 554, 556, 558, 564, 571, 572, 576, 588, 592, 595, 271]
func show_credits() -> void:
	_clear(); screen = "credits"
	var bg := EpfNbfc.load_bg(world, "bg/CreditsBottom")
	bg.resize(384, 288, Image.INTERPOLATE_BILINEAR)
	_add_img(bg.get_region(Rect2i(0, 72, 384, 216)), Vector2.ZERO)
	var f: EpfFont = fonts["Comicrazy"]
	var pages: Array = []; var total := 0
	for id in CREDIT_IDS:
		var im := f.render(_str(id).strip_edges(), Color.WHITE, 330, 1)
		pages.append(im); total += im.get_height() + 22
	var master := Image.create(344, total + 216, false, Image.FORMAT_RGBA8)
	var y := 216
	for im in pages:
		master.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i((344 - im.get_width()) / 2, y))
		y += im.get_height() + 22
	credits_node = Sprite2D.new(); credits_node.centered = false; credits_node.texture = _tex(master)
	credits_node.position = Vector2(20, 0); scr.add_child(credits_node)
	credits_h = master.get_height(); credits_y = 0.0
	_back_arrow(show_main)

# ---------- loop ----------
func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	var sc := minf(win.x / VIEW.x, win.y / VIEW.y)
	root.scale = Vector2(sc, sc)
	root.position = ((win - VIEW * sc) * 0.5).floor()

func _local(p: Vector2) -> Vector2: return (p - root.position) / maxf(root.scale.x, 0.001)

func _hit(p: Vector2) -> Btn:
	for b in btns:
		if b.enabled and b.rect.has_point(p): return b
	return null

func _process(dt: float) -> void:
	for a in anims:
		if not is_instance_valid(a["spr"]) or a["tex"].size() < 2: continue
		a["t"] += dt * 1000.0
		while a["t"] >= a["durs"][a["i"]]:
			a["t"] -= a["durs"][a["i"]]; a["i"] = (a["i"] + 1) % a["tex"].size()
			a["spr"].texture = a["tex"][a["i"]]
	for b in btns:
		if b == pressed or b.up.size() < 2: continue
		b.t += dt * 1000.0
		while b.t >= b.durs[b.i]:
			b.t -= b.durs[b.i]; b.i = (b.i + 1) % b.up.size(); b.spr.texture = b.up[b.i]
	hovering = _hit(_local(get_tree().root.get_mouse_position())) != null
	if credits_node != null:
		credits_y += dt * 22.0
		credits_node.position.y = -credits_y
		if credits_y > credits_h: show_main()

func _input(e: InputEvent) -> void:
	if screen == "tutorial" and e is InputEventMouseButton and e.pressed:
		get_viewport().set_input_as_handled()
		var d := _tut_done; _tut_done = Callable(); screen = ""
		if d.is_valid(): d.call()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var b := _hit(_local(e.position))
		if e.pressed and b != null:
			pressed = b
			if b.down != null: b.spr.texture = b.down
			if on_click.is_valid(): on_click.call()
			get_viewport().set_input_as_handled()
		elif not e.pressed and pressed != null:
			var p := pressed; pressed = null
			if p.spr != null: p.spr.texture = p.up[p.i]
			if b == p: p.cb.call()
			get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and screen == "name" and e.keycode != KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if e.keycode == KEY_BACKSPACE: player_name = player_name.substr(0, maxi(player_name.length() - 1, 0)); _refresh_name()
		elif e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER: _finish_name()
		elif e.unicode >= 32 and e.unicode < 127 and player_name.length() < 12: player_name += char(e.unicode); _refresh_name()
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if screen == "profile": back_to_title.emit()
		elif screen == "main": show_profile()
		elif screen in ["color", "name", "finish"]: back_to_title.emit()
		else: show_main()

## CPU composite of the current screen (first animation frames) for previews/tests.
func snapshot() -> Image:
	var out := Image.create(384, 216, false, Image.FORMAT_RGBA8)
	for e in els:
		var im: Image = e["img"].duplicate()
		if float(e["a"]) < 1.0:
			for y in im.get_height():
				for x in im.get_width():
					var c := im.get_pixel(x, y); c.a *= float(e["a"]); im.set_pixel(x, y, c)
		out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(e["pos"]))
	return out

# ---------- new game: penguin creation (ARM 0x20a0f..: colour screen, 0x20a2..: name screen) ----------
## Colour screen: bottom bg Menus_bottom, title GameStrings 165 at (26,10) w200 in Comicrazy, paper-doll penguin at
## (70,-18) from the panel origin, 13 colour buttons (UI/ProfileCreation/<colour>, art placed on the 256x192 canvas)
## and UI/ProfileCreation/bttn_select. Name screen: title 166, NameField at (41,48) (12 chars, faceFront),
## Keyboard at (13,91) with the key rectangles from /dat/AsciiMap.dat; "Finish creating your penguin?" = 164.
const COLORS := ["lightblue", "black", "blue", "brown", "darkgreen", "pink", "green", "limegreen", "orange", "peach", "purple", "red", "yellow"]
const S_COLOR_TITLE := 165; const S_NAME_TITLE := 166; const S_FINISH := 164
var color_btns := {}
var color_rgb := {}
var preview: Sprite2D
var name_label: Sprite2D
var name_msg: Sprite2D
var kb_shift := false
var kb_caps := false
var kb_keys: Array = []      # [{rect, ch, shift_ch, name, spr}]

func _swatch(c: String) -> Color:
	if color_rgb.has(c): return color_rgb[c]
	var fr := _frames("UI/ProfileCreation/" + c + "_up")
	var col := Color(0.8, 0, 0)
	if not fr.is_empty():
		var im: Image = fr[0]["image"]
		var r := im.get_used_rect(); var counts := {}
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var px := im.get_pixel(x, y)
				if px.a < 0.5 or px.v < 0.12 or px.s < 0.15 and px.v > 0.85: continue
				var k := px.to_html(false); counts[k] = int(counts.get(k, 0)) + 1
		var best := ""; var bn := 0
		for k in counts:
			if counts[k] > bn: bn = counts[k]; best = k
		if best != "": col = Color(best)
		if c == "black": col = Color8(66, 66, 66)
	color_rgb[c] = col
	return col

## The paper-doll body art is red; its red ramp (206/165/115/49,0,0) is the colour slot. Recolour it by brightness.
func _penguin_img(c: String) -> Image:
	var fr := _frames("UI/PaperDoll/penguin/body")
	if fr.is_empty(): return null
	return _recolor(fr[0]["image"], c)

func _recolor(src: Image, c: String) -> Image:
	var im: Image = src.duplicate()
	var tgt := _swatch(c)
	for y in im.get_height():
		for x in im.get_width():
			var px := im.get_pixel(x, y)
			if px.a < 0.1 or px.g > 0.05 or px.b > 0.05 or px.r < 0.1: continue
			var k := px.r / (206.0 / 255.0)
			im.set_pixel(x, y, Color(minf(tgt.r * k, 1.0), minf(tgt.g * k, 1.0), minf(tgt.b * k, 1.0), px.a))
	return im

## The paper-doll body has no face: UI/PaperDoll/penguin/penguinMotion is the eye layer (12-frame idle/blink loop,
## same 256x192 canvas as the body), drawn on top of it.
var anims: Array = []        # [{spr, tex, durs, i, t}]
func _add_eyes(pos: Vector2) -> void:
	var fr := _frames("UI/PaperDoll/penguin/penguinMotion")
	if fr.is_empty(): return
	var a := {"tex": [], "durs": [], "i": 0, "t": 0.0, "src": [], "eyes": true}
	for f in fr:
		a["src"].append(f["image"]); a["durs"].append(maxf(float(f["dur_ms"]), 16.0))
		a["tex"].append(_tex(_recolor(f["image"], player_color)))   # the lids around the eyes are body colour
	var sp := Sprite2D.new(); sp.centered = false; sp.position = pos; sp.texture = a["tex"][0]
	scr.add_child(sp); a["spr"] = sp
	anims.append(a)

func show_color() -> void:
	_clear(); screen = "color"; _panel()
	_text_c("Comicrazy", _str(S_COLOR_TITLE), LB + Vector2(126, 24), Color.WHITE, 200)
	preview = Sprite2D.new(); preview.centered = false; preview.position = LB + Vector2(70, -18); scr.add_child(preview)
	_add_eyes(LB + Vector2(70, -18))
	color_btns.clear()
	for c in COLORS:
		var fr := _frames("UI/ProfileCreation/" + c + "_up")
		if fr.is_empty(): continue
		var ur := (fr[0]["image"] as Image).get_used_rect()
		var cc: String = c
		color_btns[c] = _btn("UI/ProfileCreation/" + c, LB + Vector2(ur.position), func() -> void: _pick_color(cc))
	var fs := _frames("UI/ProfileCreation/bttn_select_up")
	if not fs.is_empty():
		var ur2 := (fs[0]["image"] as Image).get_used_rect()
		_btn("UI/ProfileCreation/bttn_select", LB + Vector2(ur2.position), show_name)
	_back_arrow(show_missions)
	_pick_color(player_color)

func _pick_color(c: String) -> void:
	player_color = c
	for k in color_btns:
		var b: Btn = color_btns[k]
		if b.spr == null: continue
		b.spr.texture = b.down if (k == c and b.down != null) else b.up[0]
	var im := _penguin_img(c)
	if im != null and preview != null: preview.texture = _tex(im)
	for a in anims:
		if not a.get("eyes", false): continue
		for i in a["src"].size(): a["tex"][i] = _tex(_recolor(a["src"][i], c))
		a["spr"].texture = a["tex"][a["i"]]

func _kb_map() -> Array:
	var d := world.fs.get_by_path("dat/AsciiMap.dat")
	var out: Array = []
	if d == null or d.size() < 4: return out
	var n := d.decode_u32(0)
	for i in n:
		var o := 4 + i * 20
		if o + 20 > d.size(): break
		var nm := ""
		for j in 8:
			var ch := d[o + 5 + j]
			if ch == 0: break
			nm += char(ch)
		out.append({"rect": Rect2(d[o + 1], d[o + 2], d[o + 3] - d[o + 1], d[o + 4] - d[o + 2]), "name": nm,
			"ch": d[o + 13], "shift_ch": d[o + 15] if d[o + 14] == 1 else d[o + 13]})
	return out

func show_name() -> void:
	_clear(); screen = "name"; _panel()
	_text_c("Comicrazy", _str(S_NAME_TITLE), LB + Vector2(126, 24), Color.WHITE, 200)
	var nf := _frames("UI/ProfileCreation/NameField")
	if not nf.is_empty(): _add_img(nf[0]["image"], LB + Vector2(41, 48))
	var kb := _frames("Keyboard/keyboard")
	var ko := LB + Vector2(13, 91)
	if not kb.is_empty(): _add_img(kb[0]["image"], ko)
	kb_keys.clear()
	for k in _kb_map():
		var kk: Dictionary = k
		# AsciiMap rects span x 13..206; the keyboard art's body spans 19..228 (its centre x 123 is in the sprite
		# header), so the key grid sits 14 px in from the art's left edge
		var b := _btn("Keyboard/Keys/" + str(kk["name"]), ko + Vector2(14, 0) + kk["rect"].position, func() -> void: _key(kk), false)
		kk["btn"] = b
		kb_keys.append(kk)
	_back_arrow(show_color)
	_refresh_name()

func _refresh_keys() -> void:
	var sh := kb_shift != kb_caps
	for k in kb_keys:
		var b: Btn = k["btn"]
		if b.spr == null: continue
		var alt := _frames("Keyboard/Keys/" + str(k["name"]) + "_shift_up")
		if sh and not alt.is_empty(): b.spr.texture = _tex(alt[0]["image"])
		else: b.spr.texture = b.up[0]

func _refresh_name() -> void:
	if name_label != null and is_instance_valid(name_label): name_label.queue_free()
	name_label = _text("faceFront", player_name + "_", LB + Vector2(49, 56), Color.BLACK)

func _say(msg: String) -> void:
	if name_msg != null and is_instance_valid(name_msg): name_msg.queue_free()
	name_msg = _text("faceFront", msg, LB + Vector2(49, 80), Color(1, 0.9, 0.3))

func _key(k: Dictionary) -> void:
	var nm: String = k["name"]
	match nm:
		"bs":
			player_name = player_name.substr(0, maxi(player_name.length() - 1, 0))
		"shift": kb_shift = not kb_shift; _refresh_keys(); return
		"caps": kb_caps = not kb_caps; _refresh_keys(); return
		"enter": _finish_name(); return
		_:
			var sh := kb_shift != kb_caps
			var c := int(k["shift_ch"]) if sh else int(k["ch"])
			if c >= 32 and c < 127 and player_name.length() < 12: player_name += char(c)
			if kb_shift: kb_shift = false; _refresh_keys()
	_refresh_name()

func _finish_name() -> void:
	if player_name.strip_edges().length() < 1:
		_say("Name is too short!"); return       # ov0 literal at 0x138b10
	show_finish()

func show_finish() -> void:
	_clear(); screen = "finish"; _panel()
	var im := _penguin_img(player_color)
	if im != null: _add_img(im, LB + Vector2(70, -42))
	_add_eyes(LB + Vector2(70, -42))
	_text_c("Comicrazy", player_name, LB + Vector2(128, 104), Color.WHITE)
	_text_c("faceFront", _str(S_FINISH), LB + Vector2(128, 128), Color.WHITE, 220)
	_btn("UI/chkmarkBttn", LB + Vector2(146, 154), func() -> void: write_save(); show_profile())
	_btn("UI/cancelBttn", LB + Vector2(78, 154), show_name)

# ---------- profile card (after penguin creation and on every boot with a profile) ----------
## Blue 9-slice UI/PlayerCard on the left with the name, the paper-doll penguin and coins; on the right
## Continue (+ story %), Guest (GameStrings 274) and Erase (66).
func _nine(pre: String, r: Rect2) -> void:
	var g := {}
	for k in ["tl", "top", "tr", "left", "", "right", "bl", "bottom", "br"]:
		var f := _frames(pre + ("_" + k if k != "" else ""))
		if not f.is_empty(): g[k] = f[0]["image"]
	if g.size() < 9: return
	# palette as the DS shows it: index 0 (black) is transparent, the card is (0,96,176) with a white rim
	for k in g:
		var im: Image = (g[k] as Image).duplicate(); im.convert(Image.FORMAT_RGBA8)
		for y in im.get_height():
			for x in im.get_width():
				var c := im.get_pixel(x, y)
				if c.r8 == 0 and c.g8 == 0 and c.b8 == 0: im.set_pixel(x, y, Color(0, 0, 0, 0))
				elif c.r8 == 107 and c.g8 == 173 and c.b8 == 206: im.set_pixel(x, y, Color8(0, 96, 176))
		g[k] = im
	var tl: Image = g["tl"]; var br: Image = g["br"]
	var x0 := r.position.x; var y0 := r.position.y; var x1 := r.end.x; var y1 := r.end.y
	var lw := tl.get_width(); var th := tl.get_height(); var rw := br.get_width(); var bh := br.get_height()
	var body := Image.create(int(r.size.x), int(r.size.y), false, Image.FORMAT_RGBA8)
	var put := func(im: Image, x: int, y: int, w: int, h: int) -> void:
		for yy in range(0, h, im.get_height()):
			for xx in range(0, w, im.get_width()):
				body.blend_rect(im, Rect2i(0, 0, mini(im.get_width(), w - xx), mini(im.get_height(), h - yy)), Vector2i(x + xx, y + yy))
	var W := int(r.size.x); var H := int(r.size.y)
	put.call(g[""], lw, th, W - lw - rw, H - th - bh)
	put.call(g["top"], lw, 0, W - lw - rw, th); put.call(g["bottom"], lw, H - bh, W - lw - rw, bh)
	put.call(g["left"], 0, th, lw, H - th - bh); put.call(g["right"], W - rw, th, rw, H - th - bh)
	put.call(g["tl"], 0, 0, lw, th); put.call(g["tr"], W - rw, 0, rw, th)
	put.call(g["bl"], 0, H - bh, lw, bh); put.call(g["br"], W - rw, H - bh, rw, bh)
	_add_img(body, Vector2(x0, y0))

func show_profile() -> void:
	_clear(); screen = "profile"; _panel(Vector2i(384, 216), true)
	var sv := read_save()
	player_name = str(sv.get("name", player_name)); player_color = str(sv.get("color", player_color))
	# DS layout (DeSmuME, profile screen, in DS pixels): NewPlayerCard 9-slice card (3,3)-(115,188) with its own dark
	# inner box; name in tinyUI above the box; the no-badge star in the box's top-left; penguin centred in the box;
	# coin + count (tinyUI) below; Continue (with story %) / Guest / Erase down the right. Plain dark backdrop.
	_nine("UI/PlayerCard/NewPlayerCard/card", Rect2(LB + Vector2(3, 2), Vector2(112, 186)))
	_text("tinyUI", player_name, LB + Vector2(11, 5), Color.WHITE)
	var im := _penguin_img(player_color)
	if im != null:
		var ur := im.get_used_rect()
		var at := Vector2(59 - ur.position.x - ur.size.x * 0.5, 51 - ur.position.y).round()
		_add_img(im, LB + at)
		_add_eyes(LB + at)
	var badge := _frames("UI/noBadge")
	if not badge.is_empty():
		var bi: Image = badge[0]["image"]; var bu := bi.get_used_rect()
		_add_img(bi.get_region(bu), LB + Vector2(7, 23))
	var coin := _frames("UI/coin")
	if not coin.is_empty():
		var ci: Image = coin[0]["image"]; var cr := ci.get_used_rect()
		_add_img(ci.get_region(cr), LB + Vector2(12, 149))
	_text("tinyUI", str(int(sv.get("coins", 100))), LB + Vector2(35, 149), Color.WHITE)
	var pct := int(sv.get("percent", 0))
	var c := _btn("UI/buttonBigTall", LB + Vector2(128, 24), show_main)
	_fit_btn(c, Vector2(108, 60))
	_text_c("faceFront", _str(S_CONTINUE) + "\n%d%%" % pct, c.rect.get_center() + Vector2(0, 1), Color.WHITE)
	var gb := _btn("UI/buttonMedium", LB + Vector2(128, 99), show_main); _fit_btn(gb, Vector2(108, 34))
	_text_c("faceFront", _str(274), gb.rect.get_center() + Vector2(0, -1), Color.WHITE)
	var eb := _btn("UI/buttonMedium", LB + Vector2(128, 144), show_erase); _fit_btn(eb, Vector2(108, 34))
	_text_c("faceFront", _str(S_ERASE), eb.rect.get_center() + Vector2(0, -1), Color.WHITE)

## stretch a button sprite to a DS-size box (the profile card buttons are narrower than buttonBig)
func _fit_btn(b: Btn, sz: Vector2) -> void:
	if b == null or b.spr == null: return
	var t := b.spr.texture.get_size()
	b.spr.scale = sz / t
	b.rect.size = sz
	for e in els:
		if e.get("spr") == b.spr: e["scale"] = b.spr.scale

# ---------- stylus tutorial (shown when Missions is first entered) ----------
## Top screen: GameStrings 219 "Drag your Nintendo DS stylus to move around and explore."; bottom: UI/HelpMenus/StylusDrag
## (an 8-frame DS-and-stylus animation). Any tap continues.
var _tut_done := Callable()
func show_tutorial(done: Callable) -> void:
	_clear(); screen = "tutorial"; _panel()
	_tut_done = done
	_text_c("Comicrazy", _str(219), Vector2(192, 22), Color.WHITE, 300)
	var fr := _frames("UI/HelpMenus/StylusDrag")
	if fr.is_empty(): return
	var a := {"tex": [], "durs": [], "i": 0, "t": 0.0}
	for f in fr: a["tex"].append(_tex(f["image"])); a["durs"].append(maxf(float(f["dur_ms"]), 16.0))
	var sp := Sprite2D.new(); sp.centered = false; sp.position = LB + Vector2(0, 14); sp.texture = a["tex"][0]
	scr.add_child(sp); a["spr"] = sp; anims.append(a)

## Player's penguin (body + first eye frame) in their colour, on the 256x192 paper-doll canvas.
func doll_image() -> Image:
	var im := _penguin_img(player_color)
	if im == null: return null
	var fr := _frames("UI/PaperDoll/penguin/penguinMotion")
	if not fr.is_empty():
		var e := _recolor(fr[0]["image"], player_color); im.convert(Image.FORMAT_RGBA8); e.convert(Image.FORMAT_RGBA8)
		im.blend_rect(e, Rect2i(Vector2i.ZERO, e.get_size()), Vector2i.ZERO)
	return im

# ---------- Options: the DS Microphone screen (title "Mic" button on the DS) + language (DS firmware setting) ----------
const OPTIONS_LABEL := {"en": "Options", "es": "Opciones", "fr": "Options"}
const LANGS := [["en", "English"], ["es", "Español"], ["fr", "Français"]]
func set_text(tt: TextTable) -> void:
	text = tt; _imgcache.clear()
	if screen == "lang": show_language()
	elif screen == "options": show_options()

func show_options() -> void:
	_clear(); screen = "options"; _panel()
	_text_c("Comicrazy", OPTIONS_LABEL.get(settings.get("lang", "en"), "Options"), Vector2(192, 30))
	var x := floorf((VIEW.x - 221.0) * 0.5)
	_big_button(_str(2), Vector2(x, 70), show_mic)          # "Microphone"
	_big_button(_str(786), Vector2(x, 112), show_language)  # "Select a language"
	_back_arrow(show_main)

func show_language() -> void:
	_clear(); screen = "lang"; _panel()
	_text_c("Comicrazy", _str(786), Vector2(192, 30))
	var x := floorf((VIEW.x - 221.0) * 0.5)
	var cur: String = settings.get("lang", "en")
	for i in LANGS.size():
		var code: String = LANGS[i][0]
		var label: String = ("> " + LANGS[i][1] + " <") if code == cur else LANGS[i][1]
		_big_button(label, Vector2(x, 62 + i * 38), func() -> void:
			settings["lang"] = code; settings_changed.emit(); lang_changed.emit(code); show_language())
	_back_arrow(show_options)

## DS layout (emulator): title "Microphone" (GameStrings 2), "Blow gently into the microphone to test!" (4),
## "Volume" (1) over UI/MicMenu/mic_volume (4 levels, one frame each) on mic_bar, "Sensitivity" (3) over
## UI/MicMenu/FX_slider (9 levels) on FX_bar, and a green/red input meter on the right.
var _mic_vol: Sprite2D
var _mic_sens: Sprite2D
func show_mic() -> void:
	_clear(); screen = "mic"; _panel()
	_text_c("faceFront", _str(2), LB + Vector2(128, 18), Color.WHITE)
	_text_c("Comicrazy", _str(4), LB + Vector2(96, 52), Color.WHITE, 150)
	_text("Comicrazy", _str(1), LB + Vector2(44, 76), Color.WHITE)
	_text("Comicrazy", _str(3), LB + Vector2(44, 110), Color.WHITE)
	var meter := Image.create(34, 60, false, Image.FORMAT_RGBA8); meter.fill(Color8(0, 64, 0))
	meter.fill_rect(Rect2i(22, 0, 10, 60), Color8(64, 0, 0)); meter.fill_rect(Rect2i(33, 0, 1, 60), Color8(220, 0, 0))
	_add_img(meter, LB + Vector2(192, 34))
	_mic_vol = _slider("UI/MicMenu/mic_bar_up", "UI/MicMenu/mic_volume", LB + Vector2(57, 90), int(settings.get("mic_volume", 1)))
	_mic_sens = _slider("UI/MicMenu/FX_bar_up", "UI/MicMenu/FX_slider", LB + Vector2(57, 124), int(settings.get("mic_sensitivity", 5)))
	_btn("UI/arrowBack", LB + Vector2(4, 166), show_options)      # bottom-left on this DS screen
	# tap anywhere on a bar to move its knob
	var bv := _frames("UI/MicMenu/mic_volume"); var bs := _frames("UI/MicMenu/FX_slider")
	if not bv.is_empty():
		var w := float((bv[0]["image"] as Image).get_width())
		var b := Btn.new(); b.rect = Rect2(LB + Vector2(57, 90), Vector2(w, 19)); b.cb = func() -> void: _slide("mic_volume", _mic_vol, bv, b.rect)
		btns.append(b)
	if not bs.is_empty():
		var w2 := float((bs[0]["image"] as Image).get_width())
		var b2 := Btn.new(); b2.rect = Rect2(LB + Vector2(57, 124), Vector2(w2, 19)); b2.cb = func() -> void: _slide("mic_sensitivity", _mic_sens, bs, b2.rect)
		btns.append(b2)

func _slider(bar: String, knob: String, pos: Vector2, level: int) -> Sprite2D:
	var bf := _frames(bar)
	if not bf.is_empty(): _add_img(bf[0]["image"], pos)
	var kf := _frames(knob)
	var sp := Sprite2D.new(); sp.centered = false; sp.position = pos
	if not kf.is_empty(): sp.texture = _tex(kf[clampi(level, 0, kf.size() - 1)]["image"])
	scr.add_child(sp)
	return sp

func _slide(key: String, sp: Sprite2D, fr: Array, r: Rect2) -> void:
	var lp := _local(get_viewport().get_mouse_position())
	var n := fr.size()
	var t := clampf((lp.x - r.position.x - 6.0) / maxf(r.size.x - 12.0, 1.0), 0.0, 1.0)
	var lvl := int(round(t * (n - 1)))
	settings[key] = lvl; settings_changed.emit()
	sp.texture = _tex(fr[lvl]["image"])
