extends SceneTree
## Compact Lua 5.1 listing of an object script: opcodes with constants shown as numbers or short identifiers
## (longer strings, i.e. dialogue, are masked). godot -s tests/luals.gd -- <chunk stem>
const OPS := ["MOVE","LOADK","LOADBOOL","LOADNIL","GETUPVAL","GETGLOBAL","GETTABLE","SETGLOBAL","SETUPVAL","SETTABLE",
	"NEWTABLE","SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT","JMP","EQ","LT","LE","TEST",
	"TESTSET","CALL","TAILCALL","RETURN","FORLOOP","FORPREP","TFORLOOP","SETLIST","CLOSE","CLOSURE","VARARG"]
func _init() -> void:
	var w := RomWorld.open(ProjectSettings.globalize_path("res://game.epf"))
	var chunks := EpfArc.parse(w.rom.file("chunks.arc"))
	var fn := LuaVM.load_chunk(chunks.get_chunk(OS.get_cmdline_user_args()[0]))
	_list(fn.p, "main")
	quit()
func _k(K: Array, i: int) -> String:
	if i < 0 or i >= K.size(): return "?"
	var v = K[i]
	if v is String: return ("\"" + v + "\"") if v.length() <= 28 and not " " in v else "<text>"
	return str(v)
func _rk(K: Array, x: int) -> String:
	return _k(K, x - 256) if x >= 256 else "r%d" % x
func _list(p, name: String) -> void:
	print("== function ", name)
	var K: Array = p.consts
	for pc in p.code.size():
		var ins: int = p.code[pc]
		var op := ins & 0x3F; var a := (ins >> 6) & 0xFF; var c := (ins >> 14) & 0x1FF; var b := (ins >> 23) & 0x1FF
		var bx := ins >> 14; var sbx := bx - 131071
		var o: String = OPS[op] if op < OPS.size() else str(op)
		var t := ""
		match o:
			"LOADK", "GETGLOBAL", "SETGLOBAL": t = "r%d %s" % [a, _k(K, bx)]
			"GETTABLE": t = "r%d = r%d[%s]" % [a, b, _rk(K, c)]
			"SETTABLE": t = "r%d[%s] = %s" % [a, _rk(K, b), _rk(K, c)]
			"SELF": t = "r%d = r%d:%s" % [a, b, _rk(K, c)]
			"EQ", "LT", "LE": t = "%d %s %s" % [a, _rk(K, b), _rk(K, c)]
			"JMP": t = "-> %d" % (pc + 1 + sbx)
			"FORLOOP", "FORPREP": t = "r%d -> %d" % [a, pc + 1 + sbx]
			"CALL": t = "r%d args %d ret %d" % [a, b - 1, c - 1]
			"CLOSURE": t = "r%d fn%d" % [a, bx]
			_: t = "%d %d %d" % [a, b, c]
		print("%4d %-9s %s" % [pc, o, t])
	for i in p.protos.size(): _list(p.protos[i], name + "." + str(i))
