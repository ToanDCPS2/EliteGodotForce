class_name TitleScreen
extends CanvasLayer
## Main menu. Original = two stacked 256x192 DS screens (bg/Menus/Title_topscreen2 over Title_bottomscreen, one continuous sky).
## Single-screen 16:9 rebuild: logo screen + island strip composed into 384x216; DGamer/Wi-Fi/Microphone buttons removed (online features).
signal start_pressed
const VIEW := Vector2(384, 216)
var world: RomWorld
var root := Node2D.new()
var anims: Array = []        # {spr, tex, durs, i, t}
var play_up: Dictionary
var play_down: Texture2D
var play_rect := Rect2(133, 146, 118, 35)
var pressed := false
var hovering := false
var label: Label

## Button label in the current language; shrinks to fit beside the button's icon (French "Commencer" is long).
func set_label(t: String) -> void:
	if label == null: return
	label.text = t
	var room := play_rect.size.x - 40.0       # right of the button's badge icon, with a margin
	var fs := 14
	var f := label.get_theme_font("font")
	while fs > 8 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room: fs -= 1
	label.add_theme_font_size_override("font_size", fs)
	label.position = play_rect.position + Vector2(28, 2); label.size = Vector2(play_rect.size.x - 32, play_rect.size.y)

func setup(w: RomWorld) -> void:
	world = w
	layer = 5
	root.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	add_child(root)
	var top := EpfNbfc.load_bg(w, "bg/Menus/Title_topscreen2")
	var bot := EpfNbfc.load_bg(w, "bg/Menus/Title_bottomscreen")
	if top == null or bot == null: return
	var bg := Sprite2D.new(); bg.centered = false
	bg.texture = ImageTexture.create_from_image(_compose(top, bot)); root.add_child(bg)
	for k in ["UI/MainMenu/Title_Bottom", "UI/MainMenu/Title_JetPackguy", "UI/MainMenu/Title_GreenPuffle"]:
		_add_anim(k, Vector2(64, 24) if k.ends_with("Bottom") else Vector2(64, 0))
	play_up = _add_anim("UI/MainMenu/Title_BttnPlay_up", Vector2(63, 142))
	var dn := w.sprite("UI/MainMenu/Title_BttnPlay_down")
	if not dn.is_empty() and not dn["frames"].is_empty(): play_down = ImageTexture.create_from_image(dn["frames"][0]["image"])
	label = Label.new(); label.text = "Start"; label.size = play_rect.size; label.position = play_rect.position + Vector2(0, 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.25, 0.45)); label.add_theme_constant_override("outline_size", 4)
	root.add_child(label)
	# letterbox: keep the DS art's native 256-px width (x 64..320), black pillars on both sides
	for bx in [-4096.0, 320.0]:
		var bar := ColorRect.new(); bar.color = Color.BLACK; bar.z_index = 100
		bar.position = Vector2(bx, -4096); bar.size = Vector2(4096 if bx < 0 else 4096, 8192)
		if bx < 0: bar.size.x = 4096.0 + 64.0
		root.add_child(bar)
	get_tree().root.size_changed.connect(_layout); _layout()

func _sky_key(b: Image) -> Dictionary:
	var k := {}
	for y in range(96, 172):
		k[b.get_pixel(3, y).to_rgba32()] = true; k[b.get_pixel(250, y).to_rgba32()] = true
	return k

func _mx(x: int) -> int:   # mirror-extend a 256-wide source column index
	var p := posmod(x, 512)
	return p if p < 256 else 511 - p

func _compose(top: Image, bot: Image) -> Image:
	var img := Image.create(384, 216, false, Image.FORMAT_RGBA8)
	for y in 216:
		for x in 384:
			var inside := x >= 64 and x < 320
			var sx := x - 64 if inside else (255 if x >= 320 else 255)   # outside the art: plain sky from the right-hand edge column
			img.set_pixel(x, y, top.get_pixel(sx, y) if y < 192 else bot.get_pixel(sx, y - 192))
	# island strip: bottom rows 96.. at y 120.., sky-coloured pixels skipped so the logo screen's sky shows through
	var key := _sky_key(bot)
	for sy in range(96, 192):
		var dy := sy - 96 + 120
		for x in 384:
			var c := bot.get_pixel(clampi(x - 64, 0, 255), sy)
			if key.has(c.to_rgba32()): continue
			img.set_pixel(x, dy, c)
	return img

func _add_anim(key: String, pos: Vector2) -> Dictionary:
	var d := world.sprite(key)
	if d.is_empty() or d["frames"].is_empty(): return {}
	var tex: Array = []; var durs: Array = []
	for f in d["frames"]:
		tex.append(ImageTexture.create_from_image(f["image"])); durs.append(maxf(float(f["dur_ms"]), 16.0))
	var s := Sprite2D.new(); s.centered = false; s.texture = tex[0]; s.position = pos; root.add_child(s)
	var a := {"spr": s, "tex": tex, "durs": durs, "i": 0, "t": 0.0}
	anims.append(a); return a

func _layout() -> void:
	var win := get_tree().root.get_visible_rect().size
	var sc := minf(win.x / VIEW.x, win.y / VIEW.y)
	root.scale = Vector2(sc, sc)
	root.position = ((win - VIEW * sc) * 0.5).floor()

func _local(p: Vector2) -> Vector2:
	return (p - root.position) / maxf(root.scale.x, 0.001)

func _process(dt: float) -> void:
	for a in anims:
		if pressed and a == play_up: continue
		a["t"] += dt * 1000.0
		while a["t"] >= a["durs"][a["i"]]:
			a["t"] -= a["durs"][a["i"]]; a["i"] = (a["i"] + 1) % a["tex"].size()
			a["spr"].texture = a["tex"][a["i"]]
	hovering = play_rect.has_point(_local(get_tree().root.get_mouse_position()))

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var inside := play_rect.has_point(_local(e.position))
		if e.pressed and inside:
			pressed = true
			if play_down != null and not play_up.is_empty(): play_up["spr"].texture = play_down
			get_tree().root.set_input_as_handled()
		elif not e.pressed and pressed:
			pressed = false
			if not play_up.is_empty(): play_up["spr"].texture = play_up["tex"][play_up["i"]]
			if inside: start_pressed.emit()
			get_tree().root.set_input_as_handled()
	elif e is InputEventKey and e.pressed and (e.keycode == KEY_ENTER or e.keycode == KEY_SPACE):
		start_pressed.emit()
