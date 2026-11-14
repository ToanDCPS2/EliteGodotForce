class_name DialogBox
extends Control
## Conversation UI laid out as the DS draws it (measured in DeSmuME, M1C1 Coffee Shop), in DS pixels on a 256x192 screen
## that sits centred along the bottom of the port's view (u = window pixels per DS pixel):
##   NPC line        UI/ConversationSystem/npcChatBubbleBottom at (2,97), tail up at the speaker (camera centres the speaker)
##   reply options   UI/DialogButton_up/_down at (2, 2 + 62*i), over the room darkened to half
##   thought         UI/ConversationSystem/thoughtbubble (DS: bottom of the top screen at (-2,97)); here at the top of the view
##   text            ROM font bigUI, black (its own grey anti-aliasing), centred, wrapped to the bubble
## Text is rendered with the ROM bitmap font at DS size and scaled by u with nearest filtering, like the rest of the UI.
var lines: Array = []
var idx := 0
var who := ""
var kind := 2
var anchor := Vector2(-1, -1)
var bubbles: Dictionary = {}       # "chat" "bottom" "talk" "thought" -> Texture2D
var font                           # EpfFont (bigUI), set by main
var sfx                            # SfxPlayer, set by main (option pick = sound 2, DeSmuME)
var speaker_feet := Vector2(-1, -1)  # the talking NPC's feet in window px (set by main; picks top or bottom bubble)
var _u := 1.0
var _win := Vector2(1152, 648)
var _bub: TextureRect
var _txt: TextureRect
var _dim: ColorRect

func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## top-left of the DS bottom screen inside the window
func _ds() -> Vector2:
	return Vector2(floorf((_win.x - 256.0 * _u) * 0.5), _win.y - 192.0 * _u)

func build(u: float, win: Vector2) -> void:
	_u = u; _win = win
	for c in get_children(): c.queue_free()
	opt_nodes.clear(); item_rect = null
	_dim = ColorRect.new(); _dim.color = Color(0, 0, 0, 0.5); _dim.size = win; _dim.visible = false
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_dim)
	_bub = TextureRect.new(); _bub.stretch_mode = TextureRect.STRETCH_SCALE; _bub.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bub.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE; _bub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bub)
	_txt = TextureRect.new(); _txt.stretch_mode = TextureRect.STRETCH_SCALE; _txt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_txt.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE; _txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_txt)
	_refresh()

## ROM-font text as a texture at DS pixel size
func _text_tex(t: String, wrap_px: int) -> ImageTexture:
	if font == null or t == "": return null
	var im: Image = font.render(t, Color.BLACK, wrap_px, 1)
	var ur := im.get_used_rect()
	if ur.size.x <= 0: return null
	return ImageTexture.create_from_image(im.get_region(Rect2i(0, ur.position.y, im.get_width(), ur.size.y)))

## put text centred in a DS-pixel rect (relative to `origin` in window px)
const WRAP := 235     # DS wrap width in px for every bubble (fits a 235-px line: Dojo M1C2 "So puffles can be part of the EPF too?"; breaks 236-px ones, M1C1)
func _put_text(tr: TextureRect, t: String, origin: Vector2, r: Rect2) -> void:
	var tex := _text_tex(t, mini(WRAP, int(r.size.x)))
	tr.texture = tex
	if tex == null: tr.visible = false; return
	tr.visible = true
	var sz := Vector2(tex.get_width(), tex.get_height())
	tr.size = sz * _u
	tr.position = origin + (r.position + (r.size - sz) * 0.5).floor() * _u

func _place() -> void:
	if _bub == null: return
	var t: Texture2D = bubbles.get("thought" if kind == 1 else "bottom", null)
	_bub.visible = t != null
	if t == null: return
	_bub.texture = t
	var o := _ds()
	var bsz := Vector2(t.get_width(), t.get_height())
	var text := str(lines[idx]) if idx < lines.size() else ""
	if kind == 1:
		# thought: the cloud sits at the top of the view (on the DS it is at the bottom of the top screen)
		var bo := Vector2(o.x - 2.0 * _u, 2.0 * _u)
		_bub.position = bo; _bub.size = bsz * _u
		var body := _body_rows(t)
		_put_text(_txt, text, bo, Rect2(6, body.x + 4, bsz.x - 12, body.y - body.x - 8))
	else:
		# NPC line: npcChatBubbleBottom at (2,97) under a speaker standing high on the screen, npcChatBubble at (2,0)
		# (tail down) over one standing low - barista feet y 109 -> bottom, Snow Forts NPC feet y 148 -> top (DeSmuME)
		var top := speaker_feet.y >= 0.0 and (speaker_feet.y - o.y) / _u > 128.0 and bubbles.has("chat")
		var bo := o + Vector2(2, 97) * _u
		if top:
			t = bubbles["chat"]; _bub.texture = t; bsz = Vector2(t.get_width(), t.get_height())
			bo = o + Vector2(2, 0) * _u
		_bub.position = bo; _bub.size = bsz * _u
		var body := _body_rows(t)
		_put_text(_txt, text, bo, Rect2(4, body.x + 3, bsz.x - 8, body.y - body.x - 6))

func _refresh() -> void:
	_place()

func show_lines(w: String, l: Array, k: int = 2, anch: Vector2 = Vector2(-1, -1)) -> void:
	clear_options(); show_item(null)
	lines = l; idx = 0; who = w; kind = k; anchor = anch; visible = true
	if _bub != null: _bub.visible = true
	_refresh()

func advance() -> void:
	idx += 1
	if idx >= lines.size(): visible = false; show_item(null)
	else: _refresh()

# ---- reply options: a full stack of DialogButton bubbles over the darkened room ----
var btn_up: Texture2D
var btn_down: Texture2D
var opt_nodes: Array = []

func clear_options() -> void:
	for n in opt_nodes: if is_instance_valid(n): n.queue_free()
	opt_nodes.clear()
	if _dim != null: _dim.visible = false

func show_options(labels: Array, cb: Callable) -> void:
	clear_options()
	if btn_up == null: return
	visible = true
	if _bub != null: _bub.visible = false
	if _txt != null: _txt.visible = false
	_dim.visible = true; _dim.size = _win
	var o := _ds()
	var bsz := Vector2(btn_up.get_width(), btn_up.get_height())
	for i in labels.size():
		var b := TextureButton.new()
		b.texture_normal = btn_up; b.texture_pressed = btn_down if btn_down else btn_up; b.texture_hover = btn_up
		b.ignore_texture_size = true; b.stretch_mode = TextureButton.STRETCH_SCALE
		b.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		# stacked at a 62-px pitch, centred vertically (3 options: y 2/64/126; 2 options: 34/96 - DeSmuME)
		var y0 := floorf((192.0 - 62.0 * labels.size()) * 0.5) - 1.0
		b.size = bsz * _u; b.position = o + Vector2(2, y0 + 62 * i) * _u
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var tl := TextureRect.new(); tl.stretch_mode = TextureRect.STRETCH_SCALE; tl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tl.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE; tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tl)
		var body := _body_rows(btn_up)
		_put_text(tl, str(labels[i]), Vector2.ZERO, Rect2(4, body.x + 2, bsz.x - 8, body.y - body.x - 4))
		var idx_i := i
		b.pressed.connect(func() -> void:
			if sfx: sfx.play(2)
			cb.call(idx_i))
		add_child(b); opt_nodes.append(b)

## test helper: press option i
func pick_option(i: int) -> void:
	if i < opt_nodes.size(): opt_nodes[i].pressed.emit()

# ---- item pop-up: the item's art large in the middle of the screen (DS: card flies up and grows), text as a thought ----
var item_rect: TextureRect
func show_item(t: Texture2D, from := Vector2(-1, -1)) -> void:
	if item_rect != null and is_instance_valid(item_rect): item_rect.queue_free()
	item_rect = null
	if t == null: return
	var o := _ds()
	var sz := Vector2(t.get_width(), t.get_height())
	if sz != Vector2(256, 192):                 # icon fallback: centre it
		var k := minf(1.0, minf(150.0 / sz.x, 110.0 / sz.y)); sz *= k
	item_rect = TextureRect.new(); item_rect.texture = t; item_rect.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	item_rect.stretch_mode = TextureRect.STRETCH_SCALE; item_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var end_pos := o + (Vector2(128, 96) - sz * 0.5).floor() * _u   # zoom art is a full-screen canvas: lands at (0,0)
	item_rect.size = sz * _u; item_rect.position = end_pos
	item_rect.pivot_offset = item_rect.size * 0.5
	add_child(item_rect); move_child(item_rect, 1)
	if from.x >= 0:
		# fly up from the object and grow, as the card does on the DS
		# DS (DeSmuME, M1C1 snowman's card): starts small at the giver, grows and makes one full turn on its way
		# to the middle of the screen, 32 frames in all
		var dur := 32.0 / 60.0
		item_rect.position = from - item_rect.size * 0.5; item_rect.scale = Vector2(0.08, 0.08); item_rect.rotation = -TAU
		var tw := create_tween().set_parallel(true)
		tw.tween_property(item_rect, "position", end_pos, dur)
		tw.tween_property(item_rect, "scale", Vector2.ONE, dur)
		tw.tween_property(item_rect, "rotation", 0.0, dur)

var _body_cache := {}
## rows of a bubble texture that are the bubble's body (skips the tail / thought dots)
func _body_rows(t: Texture2D) -> Vector2i:
	if _body_cache.has(t): return _body_cache[t]
	var im := t.get_image()
	var w := im.get_width(); var h := im.get_height()
	var top := 0; var bot := h
	var found := false
	for y in h:
		var n := 0
		for x in range(0, w, 2):
			if im.get_pixel(x, y).a > 0.5: n += 1
		var wide := n * 2 > w * 0.6
		if wide and not found: top = y; found = true
		if wide: bot = y
	var r := Vector2i(top, bot) if found else Vector2i(0, h)
	_body_cache[t] = r
	return r
