class_name CutsceneScreen
extends CanvasLayer
## Plays a ROM FLC movie the way the DS mission-intro overlays do (ov37 = M1C1INTRO, measured in DeSmuME):
##  - the room fades to white (15 frames), then the movie and the text screen fade in from black (15 frames)
##  - the FLC header speed (2500 ms) is not used: the overlay steps the movie itself, ~5 DS frames per FLC frame,
##    with long holds on some frames (schedule), and loops the tail until the player taps
##  - the text screen is bg/Menus/Menus_bottom with the line in fonts/faceFront, white, centred
##  - any tap ends it: fade to white, then the mission starts
## Single 16:9 screen: the text panel is a strip across the top, the movie fills the rest of the height under it.
signal finished
const VIEW := Vector2(384, 216)
const FRAME := 1.0 / 60.0
const FADE := 15.0 * FRAME
const STRIP_H := 66.0                  # text panel height in DS px (3 caption lines + the 12-px frame)
const STEP := 5.0                      # DS frames per FLC frame when the schedule gives none
var flc: FlcPlayer
var tex: ImageTexture
var rect := TextureRect.new()
var shown := -1                        # FLC frame on screen
var t := 0.0                           # DS frames into the current FLC frame
var fin := false
var ending := false
var schedule: Dictionary = {}          # FLC frame -> hold in DS frames
var loop_from := -1                    # after the last frame, continue here (-1 = end)
var _fade: ColorRect
var _panel: TextureRect

func setup(bytes: PackedByteArray, sched: Dictionary = {}, loop_at := -1) -> bool:
	layer = 6
	flc = FlcPlayer.open(bytes)
	if flc == null: return false
	schedule = sched; loop_from = loop_at
	var bg := ColorRect.new(); bg.color = Color.BLACK; bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(rect)
	_fade = ColorRect.new(); _fade.color = Color.BLACK; _fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	get_tree().root.size_changed.connect(_layout)
	_show(0)
	_layout()
	var tw := create_tween(); tw.tween_property(_fade, "color:a", 0.0, FADE)
	return true

## Text screen: the Menus_bottom art cut down to a strip (top and bottom borders kept) with the caption on it.
func set_caption(panel: Image, text: Image) -> void:
	if panel == null: return
	var w := 256; var h := int(STRIP_H); var m := 12
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sw := panel.get_width(); var sh := panel.get_height()
	var src := panel.duplicate(); src.convert(Image.FORMAT_RGBA8)
	out.blit_rect(src, Rect2i(0, 0, sw, m), Vector2i(0, 0))
	out.blit_rect(src, Rect2i(0, sh - m, sw, m), Vector2i(0, h - m))
	out.blit_rect(src, Rect2i(0, (sh - (h - 2 * m)) / 2, sw, h - 2 * m), Vector2i(0, m))
	if text != null:
		var ur := text.get_used_rect()
		if ur.size.x > 0:
			var tr := text.get_region(ur); tr.convert(Image.FORMAT_RGBA8)
			out.blend_rect(tr, Rect2i(Vector2i.ZERO, tr.get_size()), Vector2i((w - ur.size.x) / 2, (h - ur.size.y) / 2))
	_panel = TextureRect.new(); _panel.texture = ImageTexture.create_from_image(out)
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_panel.stretch_mode = TextureRect.STRETCH_SCALE; _panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel); move_child(_panel, rect.get_index() + 1)
	_layout()

func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	var u := minf(win.x / VIEW.x, win.y / VIEW.y)
	var y0 := floorf((win.y - VIEW.y * u) * 0.5)
	var top := 0.0
	if _panel != null:
		_panel.size = Vector2(256, STRIP_H) * u
		_panel.position = Vector2(floorf((win.x - _panel.size.x) * 0.5), y0)
		top = STRIP_H * u
	var h := VIEW.y * u - top
	var w := h * float(flc.width) / float(flc.height)
	rect.size = Vector2(w, h)
	rect.position = Vector2(floorf((win.x - w) * 0.5), y0 + top)

## FLC frames are deltas: rewind and replay up to frame i when going back
func _show(i: int) -> void:
	if i < flc.frame_no - 1: flc.rewind()
	while flc.frame_no <= i: flc.next_frame()
	shown = i
	var im := flc.image()
	if tex == null: tex = ImageTexture.create_from_image(im); rect.texture = tex
	else: tex.update(im)

func _hold(i: int) -> float:
	return float(schedule.get(i, STEP))

func _process(dt: float) -> void:
	if fin or ending: return
	t += dt / FRAME
	while t >= _hold(shown):
		t -= _hold(shown)
		var nx := shown + 1
		if nx >= flc.frame_count:
			if loop_from < 0: _end(); return
			nx = loop_from
		_show(nx)

func _end() -> void:
	if ending or fin: return
	ending = true
	_fade.color = Color(1, 1, 1, 0)
	var tw := create_tween(); tw.tween_property(_fade, "color:a", 1.0, FADE)
	tw.tween_callback(func() -> void:
		fin = true
		finished.emit())

func _input(e: InputEvent) -> void:
	if fin or ending: return
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]):
		get_viewport().set_input_as_handled()
		_end()
