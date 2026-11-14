extends CanvasLayer
## Room-change iris wipe, as the DS does it (measured in DeSmuME, Town -> Dock): a circle centred on the screen closes at
## 6 DS pixels per frame (60 fps) leaving the menu blue (0,104,160), the screen stays covered while the next room loads,
## then the circle opens again at the same speed. Both DS screens wipe together, so here it covers the whole window.

signal closed      # fully covered: load the next room now
signal opened      # wipe finished

const COLOR := Color8(0, 104, 160)
const SPEED := 6.0 * 60.0        # DS pixels per second
const MIN_HOLD := 0.1             # the DS stays covered while it loads (about 20 frames in the emulator)

var px_scale := 1.0               # window pixels per DS pixel (set by main from the room scale)
var phase := 0                    # 0 idle, 1 closing, 2 covered, 3 opening
var radius := 0.0
var hold := 0.0
var rect: ColorRect
var mat: ShaderMaterial

func _ready() -> void:
	layer = 29
	rect = ColorRect.new(); rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec2 size = vec2(256.0, 192.0);
uniform float radius = 1000.0;
uniform vec4 col : source_color;
void fragment() {
	vec2 p = (UV - 0.5) * size;
	COLOR = length(p) > radius ? col : vec4(0.0);
}"""
	mat = ShaderMaterial.new(); mat.shader = sh
	mat.set_shader_parameter("col", COLOR)
	rect.material = mat; rect.visible = false
	add_child(rect)

func busy() -> bool: return phase != 0

func _full() -> float:
	return rect.size.length() * 0.5 + 2.0

func close() -> void:
	if phase == 1 or phase == 2: return
	if phase == 0: radius = _full()
	phase = 1; rect.visible = true

var _loaded := false

func _process(dt: float) -> void:
	if phase == 0: return
	var step := SPEED * px_scale * dt
	match phase:
		1:
			radius -= step
			if radius <= 0.0:
				radius = 0.0; phase = 2; hold = 0.0; _loaded = false
				closed.emit()
		2:
			hold += dt
			if _loaded and hold >= MIN_HOLD: phase = 3
		3:
			radius += step
			if radius >= _full():
				phase = 0; rect.visible = false; opened.emit()
	mat.set_shader_parameter("size", rect.size)
	mat.set_shader_parameter("radius", radius)

## main calls this after loading the room while covered
func room_ready() -> void:
	_loaded = true
