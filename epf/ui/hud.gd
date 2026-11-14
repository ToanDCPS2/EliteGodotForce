extends Control
## In-room HUD built from the ROM's touch-screen UI (UI/UtilityBorder, UI/InventoryPanel):
##   thin blue border + corner buttons: Map (top-left), SpyPod (top-right, once owned), Inventory (bottom-left),
##   Puffle (bottom-right; "no puffle" sign until a puffle is enabled).
## The suitcase opens the inventory strip (inventory_left + one 32x45 tile per item + inventory_right). Items are
## dragged out of the strip onto the room (ITEM_DROPPED on the target) or onto another item (COMBINE on that item);
## a quick tap shows the item's pop-up text. Built at window resolution with u = window px per DS px, like DialogBox.

signal item_dropped(item_id: int, win_pos: Vector2)
signal items_combined(src_id: int, dst_id: int)
signal item_tapped(item_id: int)
signal map_pressed
signal spypod_pressed

var world
var sfx
var u := 1.0
var win := Vector2(1152, 648)
var inv_open := false
var items: Array = []              # inventory item ids, in pick-up order
var item_defs: Dictionary = {}     # id -> object def (flags 5, UI/InventoryPanel)
var puffle_corner := false        # DS M1C1: no puffle corner after SetPuffle/EnablePuffle; what shows it is checked at M1C2
var puffle_item := -1              # SetPuffle(id): the puffle "item" dragged out of the puffle button
var map_enabled := false      # no map corner until a script calls ShowMap (mission 1.2's Puffle Handler)
var spypod_enabled := false
var objective := ""

var _tex := {}                     # key -> {tex, rect (DS px, in the 256x192 canvas)}
var _drag: Dictionary = {}         # {id, tex, ghost, start, moved}
var _strip: Control
var _ghost: TextureRect
var _objective_lbl: Label
var _objective_tw: Tween

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(w, s) -> void:
	world = w; sfx = s
	for ov in world.objects:
		for o in world.objects[ov]:
			if int(o.get("flags", 0)) == 5 and str(o.get("sprite_dir", "")).begins_with("UI/InventoryPanel"):
				item_defs[int(o["id"])] = o

## English variant first (UI/UtilityBorder/english/Bttn_Map_up), then the base (French) art.
func _sprite(key: String) -> Dictionary:
	return world.sprite(key)      # RomWorld picks the english/ or spanish/ variant for the current language

## Tight texture of frame `f` of a sprite whose canvas is the full 256x192 screen; rect keeps its DS position.
func _t(key: String, f := 0) -> Dictionary:
	var ck := "%s#%d" % [key, f]
	if _tex.has(ck): return _tex[ck]
	var d := _sprite(key)
	var r := {}
	if not d.is_empty() and d.has("frames") and d["frames"].size() > f:
		var im: Image = d["frames"][f]["image"]
		var used := im.get_used_rect()
		if used.size.x > 0:
			r = {"tex": ImageTexture.create_from_image(im.get_region(used)), "rect": Rect2(used), "frames": d["frames"].size()}
	_tex[ck] = r
	return r

func build(scale_u: float, window: Vector2) -> void:
	u = scale_u; win = window
	for c in get_children(): c.queue_free()
	_strip = null; _ghost = null
	_build_border()
	if map_enabled:     # HideMap removes the button (FP00 Town on the DS has no map corner)
		_corner("UI/UtilityBorder/Bttn_Map_up", "UI/UtilityBorder/Bttn_Map_down", Vector2(0, 0), _on_map, true)
	if spypod_enabled:
		_corner("UI/UtilityBorder/Bttn_Spypod_up", "UI/UtilityBorder/Bttn_Spypod_down", Vector2(1, 0), func() -> void: spypod_pressed.emit(), true)
	_corner("UI/UtilityBorder/Bttn_Inventory_up", "UI/UtilityBorder/Bttn_Inventory_down", Vector2(0, 1), _toggle_inventory, true)
	# the puffle corner only exists once a puffle has joined (SetPuffle); there is no button before that
	if puffle_item >= 0 and puffle_corner:
		var pb := _corner("UI/UtilityBorder/Bttn_Puffle_up", "UI/UtilityBorder/Bttn_Puffle_down", Vector2(1, 1), Callable(), true)
		if pb != null:
			pb.button_down.connect(func() -> void: _begin_drag(puffle_item, _puffle_tex()))
	_objective_lbl = Label.new()
	_objective_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_lbl.add_theme_font_size_override("font_size", int(7 * u))
	_objective_lbl.add_theme_color_override("font_color", Color.WHITE)
	_objective_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.2, 0.45))
	_objective_lbl.add_theme_constant_override("outline_size", int(2 * u))
	_objective_lbl.size = Vector2(win.x - 120 * u, 30 * u); _objective_lbl.position = Vector2(60 * u, 22 * u)
	_objective_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_lbl.modulate.a = 0.0
	add_child(_objective_lbl)
	if inv_open: _build_strip()
	_build_top()

func _build_border() -> void:
	var h := _t("UI/UtilityBorder/BorderPanel")          # 16x4 strip (top/bottom)
	var v := _t("UI/UtilityBorder/BorderPanel_side")     # 4x16 strip (left/right)
	if not h.is_empty():
		for y in [0.0, win.y - 4 * u]:
			var tr := TextureRect.new(); tr.texture = h["tex"]; tr.stretch_mode = TextureRect.STRETCH_TILE
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.position = Vector2(0, y); tr.size = Vector2(win.x / u, 4); tr.scale = Vector2(u, u)
			if y > 0: tr.flip_v = true
			add_child(tr)
	if not v.is_empty():
		for x in [0.0, win.x - 4 * u]:
			var tr2 := TextureRect.new(); tr2.texture = v["tex"]; tr2.stretch_mode = TextureRect.STRETCH_TILE
			tr2.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE; tr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr2.position = Vector2(x, 0); tr2.size = Vector2(4, win.y / u); tr2.scale = Vector2(u, u)
			if x > 0: tr2.flip_h = true
			add_child(tr2)
	for c in [["Corner_TL", Vector2(0, 0)], ["Corner_TR", Vector2(1, 0)], ["Corner_BL", Vector2(0, 1)], ["Corner_BR", Vector2(1, 1)]]:
		var t := _t("UI/UtilityBorder/" + c[0])
		if t.is_empty(): continue
		var cr := TextureRect.new(); cr.texture = t["tex"]; cr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE; cr.scale = Vector2(u, u)
		var sz: Vector2 = t["rect"].size * u
		cr.position = Vector2(c[1].x * (win.x - sz.x), c[1].y * (win.y - sz.y))
		add_child(cr)

## Corner button; `corner` (0/1, 0/1) picks the window corner the DS art is anchored to.
func _corner(up: String, down: String, corner: Vector2, cb: Callable, enabled: bool) -> TextureButton:
	var a := _t(up); var b := _t(down)
	if a.is_empty(): return null
	var btn := TextureButton.new()
	btn.texture_normal = a["tex"]; btn.texture_pressed = b.get("tex", a["tex"])
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	btn.ignore_texture_size = true; btn.stretch_mode = TextureButton.STRETCH_SCALE
	var sz: Vector2 = a["rect"].size * u
	btn.size = sz
	btn.position = Vector2(corner.x * (win.x - sz.x), corner.y * (win.y - sz.y))
	btn.disabled = not enabled
	if not enabled: btn.modulate = Color(1, 1, 1, 0.55)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if cb.is_valid():
		btn.pressed.connect(func() -> void:
			if sfx: sfx.play(SfxPlayerRef.UI_BUTTON)
			cb.call())
	add_child(btn)
	return btn

const SfxPlayerRef := preload("res://epf/audio/sfx_player.gd")

func _on_map() -> void:
	map_pressed.emit()

## ARM 0x20bb60c / 0x20bb6b8: the inventory panel (created at x 0, y 193 - height) slides in to x = 0 and back out to
## x = -width over 15 frames, i.e. it comes out from under the suitcase button. 15 DS frames = 0.25 s.
const SLIDE_TIME := 15.0 / 60.0
var _strip_tw: Tween
func _toggle_inventory() -> void:
	inv_open = not inv_open
	if inv_open:
		_build_strip(true)
	elif _strip != null:
		if _strip_tw: _strip_tw.kill()
		var st := _strip
		_strip_tw = create_tween()
		_strip_tw.tween_property(st, "position:x", -st.size.x, SLIDE_TIME)
		_strip_tw.tween_callback(func() -> void:
			if is_instance_valid(st): st.queue_free()
			if _strip == st: _strip = null)

func refresh() -> void:
	build(u, win)

## ---- inventory strip ----
func _item_tex(id: int, kind := "Icon_up") -> Texture2D:
	var o: Dictionary = item_defs.get(id, {})
	if o.is_empty(): return null
	var d := _sprite("UI/InventoryPanel/" + str(o["name"]) + kind)
	if d.is_empty() or not d.has("frames") or d["frames"].is_empty(): return null
	return ImageTexture.create_from_image(d["frames"][0]["image"])

## The item's big art (UI/Zoom/<item>, drawn on the 256x192 screen canvas) used by the pick-up pop-up; falls back to the icon.
func item_zoom_tex(id: int) -> Texture2D:
	var o: Dictionary = item_defs.get(id, {})
	if o.is_empty(): return null
	var d := _sprite("UI/Zoom/" + str(o["name"]))
	if d.is_empty() or not d.has("frames") or d["frames"].is_empty(): return _item_tex(id, "Icon_up")
	return ImageTexture.create_from_image(d["frames"][0]["image"])

func _puffle_tex() -> Texture2D:
	var d := _sprite("UI/puffleCursor")
	if d.is_empty() or d["frames"].is_empty(): return null
	return ImageTexture.create_from_image(d["frames"][0]["image"])

func _build_strip(animate := false) -> void:
	if _strip != null: _strip.queue_free()
	_strip = Control.new(); _strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip); move_child(_strip, 0)       # under the border and the suitcase button
	var L := _t("UI/InventoryPanel/InventoryBorderPanels/inventory_left")
	var M := _t("UI/InventoryPanel/InventoryBorderPanels/inventory")
	var R := _t("UI/InventoryPanel/InventoryBorderPanels/inventory_right")
	if L.is_empty() or M.is_empty() or R.is_empty(): return
	# ARM 0x20ba98c(panel, 4): 4 slots to start, one more per item; icons at x = 34 + slot*32, y = 5 (0x20baa6c)
	var slots := maxi(items.size(), 4)
	var cap: float = L["rect"].size.x; var sw: float = M["rect"].size.x; var h: float = L["rect"].size.y
	var w: float = cap + sw * slots + R["rect"].size.x
	_strip.size = Vector2(w, h) * u
	_strip.position = Vector2(-_strip.size.x if animate else 0.0, win.y - (h - 1.0) * u)   # y = 193 - height
	# the strip is composed at DS pixel size and scaled as one picture: scaling the end caps and slot tiles separately
	# left 1-pixel seams between them at non-integer window scales
	var parts: Array = [L]
	for i in slots: parts.append(M)
	parts.append(R)
	var img := Image.create(int(w), int(h), false, Image.FORMAT_RGBA8)
	var xi := 0
	for t in parts:
		var pim: Image = t["tex"].get_image(); pim.convert(Image.FORMAT_RGBA8)
		img.blend_rect(pim, Rect2i(Vector2i.ZERO, pim.get_size()), Vector2i(xi, 0))
		xi += int(t["rect"].size.x)
	var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(img)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.size = Vector2(w, h) * u
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(tr)
	for i in items.size():
		var icon := TextureRect.new(); icon.texture = _item_tex(items[i])
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		icon.size = Vector2(32, 32) * u; icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(cap + i * sw, 5.0) * u
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.set_meta("item", items[i])
		var iid: int = items[i]
		icon.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_begin_drag(iid, _item_tex(iid)))
		_strip.add_child(icon)
	if animate:
		if _strip_tw: _strip_tw.kill()
		_strip_tw = create_tween()
		_strip_tw.tween_property(_strip, "position:x", 0.0, SLIDE_TIME)

func _slot_item_at(p: Vector2) -> int:
	if _strip == null: return -1
	for c in _strip.get_children():
		if c.has_meta("item") and c.get_global_rect().has_point(p): return int(c.get_meta("item"))
	return -1

## ---- drag & drop ----
func _begin_drag(id: int, tex: Texture2D) -> void:
	_drag = {"id": id, "start": get_global_mouse_position(), "moved": false}
	_ghost = TextureRect.new(); _ghost.texture = tex; _ghost.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE; _ghost.scale = Vector2(u, u); _ghost.modulate.a = 0.0
	add_child(_ghost)
	_move_ghost()

func _move_ghost() -> void:
	if _ghost == null or _ghost.texture == null: return
	_ghost.position = get_global_mouse_position() - _ghost.texture.get_size() * u * 0.5

func dragging() -> bool: return not _drag.is_empty()

func _input(e: InputEvent) -> void:
	if _drag.is_empty(): return
	if e is InputEventMouseMotion:
		if not _drag["moved"] and e.position.distance_to(_drag["start"]) > 4.0 * u:
			_drag["moved"] = true
			if _ghost: _ghost.modulate.a = 1.0
		_move_ghost()
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var d := _drag; _drag = {}
		if _ghost: _ghost.queue_free(); _ghost = null
		get_viewport().set_input_as_handled()
		if not d["moved"]:
			if d["id"] != puffle_item: item_tapped.emit(d["id"])
			return
		var tgt := _slot_item_at(e.position)
		if tgt >= 0:
			if tgt != d["id"]: items_combined.emit(d["id"], tgt)
			return
		item_dropped.emit(d["id"], e.position)

## ---- objective banner (the DS top screen's mission line) ----
func show_objective(text: String) -> void:
	objective = text
	if _top != null: refresh()
	if _objective_lbl == null: return
	_objective_lbl.text = text
	if _objective_tw: _objective_tw.kill()
	_objective_lbl.modulate.a = 1.0
	_objective_tw = create_tween()
	_objective_tw.tween_interval(4.0)
	_objective_tw.tween_property(_objective_lbl, "modulate:a", 0.0, 0.8)

func set_items(inv: Dictionary) -> void:
	var keep: Array = []
	for i in items:
		if int(inv.get(i, 0)) > 0: keep.append(i)
	for k in inv:
		if int(inv[k]) > 0 and not keep.has(int(k)) and item_defs.has(int(k)): keep.append(int(k))
	items = keep
	if inv_open: _build_strip()


## ---- DS top screen as a drop-down (bg/MissionHUD_BG: mission + objective, coins, location picture and name) ----
var top_open := false
var _top: Control
var _top_tw: Tween
var room_prefix := ""
var mission_title := ""
var coins := 0
var game_text
const ROOM_NAME := {"commandroom0": 98, "gadgetroom0": 99, "gadgetroom1": 99, "skihill0": 101, "town0": 102, "snowforts0": 103,
	"tallestmountaintop0": 104, "tallestmountaintop1": 104, "beach0": 105, "coffeeshop0": 106, "dock0": 107, "dojo0": 108,
	"garysroom0": 109, "headquarters0": 110, "mineshack0": 111, "plaza0": 112, "petshop0": 113, "puffletraining0": 114,
	"skivillage0": 115, "lodge0": 116, "sportshop0": 117, "lighthouse0": 118, "pizzaparlor0": 119, "forest0": 132,
	"icerink0": 121, "boilerroom0": 122, "pool0": 123, "nightclub0": 124, "stage0": 125, "stage1": 125, "beacon0": 126,
	"giftshop0": 127, "fishing0": 128, "giftoffice0": 129, "iceberg0": 131, "bookroom0": 133, "lounge0": 134, "giftroof0": 135,
	"attic0": 116, "wildernessclearing0": 120, "wildernesscave0": 120, "wildernesscliff0": 120, "wildernessriver0": 120,
	"wildernessberry0": 120, "wildernesspuffle0": 120}

func _top_size() -> Vector2:
	var s := minf(win.y * 0.72 / 192.0, win.x * 0.6 / 256.0)
	return Vector2(256, 192) * s

func _build_top() -> void:
	var sz := _top_size(); var k := sz.x / 256.0
	_top = Control.new(); _top.size = sz; _top.mouse_filter = Control.MOUSE_FILTER_STOP
	_top.position = Vector2((win.x - sz.x) * 0.5, 0.0 if top_open else -sz.y)
	add_child(_top); move_child(_top, 0)          # slides down from behind the top border
	# The DS top screen, composed as one 256x192 picture (as the DS layers it) and scaled as a whole:
	var img := _top_image()
	if img != null:
		var bg := TextureRect.new(); bg.texture = ImageTexture.create_from_image(img); bg.size = sz
		bg.stretch_mode = TextureRect.STRETCH_SCALE; bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE; bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top.add_child(bg)
	# pull tab under the panel (UI/arrowDown / arrowUp)
	var a := _t("UI/arrowUp_up" if top_open else "UI/arrowDown_up")
	var tab := TextureButton.new(); tab.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	tab.ignore_texture_size = true; tab.stretch_mode = TextureButton.STRETCH_SCALE
	if not a.is_empty():
		tab.texture_normal = a["tex"]; tab.size = a["rect"].size * u * 0.8
	else:
		tab.size = Vector2(24, 12) * u
	tab.position = Vector2((sz.x - tab.size.x) * 0.5, sz.y + 1.0 * u)
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.pressed.connect(func() -> void:
		if sfx: sfx.play(SfxPlayerRef.UI_BUTTON)
		toggle_top())
	_top.add_child(tab)

var player_doll: Image

## DS top screen during play (DeSmuME, Town0): bg/MissionHUD_BG; no-badge star top-left; the player's penguin centred
## in the card's dark box; coin + count (faceFront) under it; room name (DSdigital) on the monitor's top bar, the room's
## UI/HUDlocation picture, and the objective (DSdigital, wrapped, centred) in the lower green box, both (160,216,168).
## The bg's outer 1-pixel black ring sits under the DS bezel; here the panel floats, so that ring is made transparent.
const TOP_TEXT := Color8(160, 216, 168)
var _fonts := {}
func _font(n: String):
	if not _fonts.has(n): _fonts[n] = EpfFont.load_font(world.fs, "fonts/%s.fnt" % n)
	return _fonts[n]

func _blend(dst: Image, src: Image, at: Vector2i) -> void:
	if src == null: return
	var s2 := src.duplicate(); s2.convert(Image.FORMAT_RGBA8)
	dst.blend_rect(s2, Rect2i(Vector2i.ZERO, s2.get_size()), at)

## The DS draws HUD text as scaled quads: DSdigital at 0.8, faceFront at 0.875 (glyph sizes and line pitch measured).
func _text_img(font: String, t: String, col: Color, wrap := 0, align := 0, sc := 1.0) -> Image:
	var f = _font(font)
	if f == null or t == "": return null
	var im: Image = f.render(t, col, wrap, align) if sc == 1.0 else f.render_scaled(t, col, sc, wrap, align)
	var ur := im.get_used_rect()
	return im.get_region(ur) if ur.size.x > 0 else null

func _top_image() -> Image:
	var bgimg = EpfNbfc.load_bg(world, "bg/MissionHUD_BG")
	if bgimg == null: return null
	var img: Image = bgimg.duplicate(); img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width(); var h := img.get_height()
	# clear the black outer ring and any black that touches it (corners outside the rounded rims)
	var stack: Array = []
	for x in w: stack.append(Vector2i(x, 0)); stack.append(Vector2i(x, h - 1))
	for y in h: stack.append(Vector2i(0, y)); stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var q: Vector2i = stack.pop_back()
		if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h: continue
		var c := img.get_pixelv(q)
		if c.a == 0.0 or c.r8 > 8 or c.g8 > 8 or c.b8 > 8: continue
		img.set_pixelv(q, Color(0, 0, 0, 0))
		stack.append(q + Vector2i.LEFT); stack.append(q + Vector2i.RIGHT); stack.append(q + Vector2i.UP); stack.append(q + Vector2i.DOWN)
	for key in ["UI/HUDlocation/" + room_prefix.to_lower(), "UI/noBadge", "UI/coin"]:
		var d := _sprite(key)
		if d.is_empty() or not d.has("frames") or d["frames"].is_empty(): continue
		_blend(img, d["frames"][0]["image"], Vector2i(0, 5) if key == "UI/coin" else Vector2i.ZERO)
	if player_doll != null:
		var ur := player_doll.get_used_rect()
		_blend(img, player_doll, Vector2i(roundi(59 - ur.position.x - ur.size.x * 0.5), 50 - ur.position.y))
	var name_id := int(ROOM_NAME.get(room_prefix.to_lower(), 100))
	var nm := _text_img("DSdigital", (game_text.get_text(name_id) if game_text != null else room_prefix).to_upper(), TOP_TEXT, 0, 0, 0.8)
	if nm != null: _blend(img, nm, Vector2i(170 - nm.get_width() / 2, 17))
	var ob := _text_img("DSdigital", objective.to_upper(), TOP_TEXT, 112, 1, 0.8)
	if ob != null: _blend(img, ob, Vector2i(183 - ob.get_width() / 2, 147 - ob.get_height() / 2))
	var cn := _text_img("faceFront", str(coins), Color.WHITE, 0, 0, 0.875)
	if cn != null: _blend(img, cn, Vector2i(41, 152))
	return img
func _top_label(t: String, r: Rect2, k: float, fs: int, ha, va, col := Color.WHITE) -> void:
	var l := Label.new(); l.text = t; l.position = r.position * k; l.size = r.size * k
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = ha; l.vertical_alignment = va
	l.add_theme_font_size_override("font_size", maxi(8, int(fs * k)))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(r.size.x * k, 0)
	_top.add_child(l)
	l.size = r.size * k; l.position = r.position * k

func toggle_top() -> void:
	top_open = not top_open
	var sz := _top_size()
	if _top_tw: _top_tw.kill()
	_top_tw = create_tween()
	_top_tw.tween_property(_top, "position:y", 0.0 if top_open else -sz.y, SLIDE_TIME)
	_top_tw.tween_callback(func() -> void: refresh())

func set_room(prefix: String, mission_line: String, coin_count: int) -> void:
	room_prefix = prefix; mission_title = mission_line; coins = coin_count
	refresh()
