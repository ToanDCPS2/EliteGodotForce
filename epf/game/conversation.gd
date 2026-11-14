extends RefCounted
## Runs the dialogue a script queued: lines, one/two-button conversations, looping option lists, and the
## dialog-event actions every line ends with (CHANGE_DIALOG / END_DIALOG / CHANGE_NPC / CHANGE_ROOM / END_MISSION).
## Semantics (from every call shape in the 592 scripts):
##   AddDialog(text, EV, p..)          line, then EV(p..) when dismissed
##   AddMonologue(text, tbl, EV, p..)  same (player thought)
##   AddConversation(text, a, b, EV, p..)  line with up to two buttons (text ids, <0 none); a button performs EV(p..)
##   AddLoopingConv(text) + AddLoopingOption(label, reply, EV, p)*  NPC line + choices; reply (>=0) is the NPC answer;
##       UPDATE_LOOP re-shows the choices, CHANGE_DIALOG(p) sets the count to p and re-runs TOUCHED, END_DIALOG(p) sets count p and closes
##   CHANGE_NPC(npcId, n) sets another NPC's conversation count; CHANGE_DIALOG(n) re-runs the script with count n.

var main: Node
var rt: ObjectRuntime
var name := ""
var oid := 0
var head := Vector2(-1, -1)
var items: Array = []        # [{text, kind, end:[ev,p1,p2], buttons:[labels], options:[{text,reply,ev,p}], loop:bool}]
var pos := 0
var active := false
var showing_options := false
var _after_reply: Callable = Callable()
var _depth := 0
var C := {}                  # _const names -> values

func start(m: Node, nm: String, runtime: ObjectRuntime, id: int, head_pos: Vector2, evs: Array) -> void:
	main = m; name = nm; rt = runtime; oid = id; head = head_pos
	var consts = rt.vm.G.get_v("_const")
	C = {}
	for k in ["CHANGE_DIALOG", "END_DIALOG", "CHANGE_NPC", "CHANGE_ROOM", "END_MISSION", "UPDATE_LOOP", "PLAY_CUTSCENE", "START_MISSION"]:
		C[k] = consts.get_v(k) if consts != null else -999
	_depth = 0
	load_events(evs)

## Parse queued API events into dialogue items and show the first one. Returns false if nothing to show.
func load_events(evs: Array) -> bool:
	items = []; pos = 0
	var cur_conv = null
	for e in evs:
		var a: Array = e["args"]
		var fn: String = e["fn"]
		match fn:
			"AddDialog":                       # AddDialog(text, EV, p..) - speech bubble at the NPC
				items.append(_line(a, 1, 2)); cur_conv = null
			"AddMonologue":                    # AddMonologue(text, ["DialogStrings",] EV, p..) - player's thought
				var evi := 2 if a.size() > 1 and a[1] is String else 1
				items.append(_line(a, evi, 1)); cur_conv = null
			"AddConversation":
				var it3 := {"text": _txt(a, 0), "kind": 2, "end": _ev_at(a, 3), "buttons": [], "options": [], "loop": false}
				for bi in [1, 2]:
					if bi < a.size() and int(a[bi]) >= 0: it3["buttons"].append(_txt(a, bi))
				items.append(it3); cur_conv = null
			"AddLoopingConv":
				cur_conv = {"text": _txt(a, 0), "kind": 2, "end": [-1, 0, 0], "buttons": [], "options": [], "loop": true}
				items.append(cur_conv)
			"AddLoopingOption":
				var opt := {"text": _txt(a, 0), "reply": int(a[1]) if a.size() > 1 else -1, "ev": int(a[2]) if a.size() > 2 else -1, "p": int(a[3]) if a.size() > 3 else 0}
				if cur_conv != null: cur_conv["options"].append(opt)
				elif not items.is_empty():
					items[items.size() - 1]["options"].append(opt); items[items.size() - 1]["loop"] = true
	if items.is_empty():
		active = false; return false
	active = true
	_show()
	return true

func _txt(a: Array, i: int) -> String:
	if i >= a.size() or not (a[i] is int or a[i] is float): return ""
	return main.fmt(main.en.get_text(int(a[i])))

func _ev_at(a: Array, i: int) -> Array:
	var ev := int(a[i]) if i < a.size() and (a[i] is int or a[i] is float) else -1
	return [ev, int(a[i + 1]) if i + 1 < a.size() and (a[i + 1] is int or a[i + 1] is float) else 0, int(a[i + 2]) if i + 2 < a.size() and (a[i + 2] is int or a[i + 2] is float) else 0]

func _line(a: Array, evi: int, kind: int) -> Dictionary:
	return {"text": _txt(a, 0), "kind": kind, "end": _ev_at(a, evi), "buttons": [], "options": [], "loop": false}

var _line_shown := false
var _last_reply := ""
func _show() -> void:
	var it: Dictionary = items[pos]
	# an option's reply that is also the first line of the step it jumps to is shown once on the DS
	# (barista: option "Could you take a look..." replies 14, then CHANGE_DIALOG 1 opens with AddDialog 14)
	if _last_reply != "" and it["text"] == _last_reply and it["options"].is_empty() and it["buttons"].is_empty():
		_last_reply = ""
		_finish_item(); return
	_last_reply = ""
	showing_options = false
	if int(it["kind"]) == 1: main.end_talk()      # a thought: the DS pans back off the speaker as it appears
	main.talk_target = name
	# DS: the NPC's line is shown on its own first; the next tap replaces it with the full-screen reply options
	if it["text"] != "" and (it["options"].size() > 0 or it["buttons"].size() > 0) and not _line_shown:
		main.dialog.show_lines(name, [it["text"]], int(it["kind"]), head if int(it["kind"]) != 1 else Vector2(-1, -1))
		_line_shown = true
		_after_reply = func() -> void: _show()
		return
	_line_shown = false
	if it["options"].is_empty() and it["buttons"].is_empty():
		main.dialog.show_lines(name, [it["text"]], int(it["kind"]), head if int(it["kind"]) != 1 else Vector2(-1, -1))
	if it["options"].size() > 0:
		showing_options = true
		var labels: Array = []
		for o in it["options"]: labels.append(o["text"])
		main.dialog.show_options(labels, _choose_option)
	elif it["buttons"].size() > 0:
		showing_options = true
		main.dialog.show_options(it["buttons"], func(_i: int) -> void: _finish_item())

## Tap on the bubble.
func click() -> void:
	if not active or showing_options: return
	if not _after_reply.is_null():
		var cb := _after_reply; _after_reply = Callable(); cb.call(); return
	_finish_item()

func _finish_item() -> void:
	main.dialog.clear_options(); showing_options = false
	if pos + 1 < items.size():
		pos += 1; _show(); return
	_run_end(items[pos]["end"])

func _choose_option(i: int) -> void:
	main.dialog.clear_options(); showing_options = false
	var it: Dictionary = items[pos]
	var o: Dictionary = it["options"][i]
	var done := func() -> void: _do_option_action(it, o)
	if o["reply"] >= 0:
		var rtext: String = main.fmt(main.en.get_text(int(o["reply"])))
		main.dialog.show_lines(name, [rtext], 2, head)
		_last_reply = rtext
		_after_reply = done
	else:
		done.call()

func _do_option_action(it: Dictionary, o: Dictionary) -> void:
	var ev: int = o["ev"]
	if ev == C["UPDATE_LOOP"]:
		# DS: straight back to the choices (no repeat of the NPC's line), with the option just picked taken out
		it["options"].erase(o)
		_line_shown = true
		_show()
	elif ev == C["CHANGE_DIALOG"]:
		_set_count(oid, int(o["p"])); _rerun()
	elif ev == C["END_DIALOG"]:
		_set_count(oid, int(o["p"])); _close()
	elif ev == C["START_MISSION"]:
		_close(); main.start_mission(int(o["p"]))      # Dot in the Dojo: "I want to join the EPF" -> mission 12 (1.02)
	elif ev == C["END_MISSION"]:
		_close(); main.end_mission()
	else:
		_close()

func _set_count(id: int, n: int) -> void:
	main.api.conv_counts[id] = n

func _rerun() -> void:
	_depth += 1
	if _depth > 12: _close(); return
	var before: int = main.api.events.size()
	rt.fire(main.api, "TOUCHED")
	main._track_coroutines(rt)
	var evs: Array = main.api.events.slice(before)
	main._apply_events(before)
	if not load_events(evs): _close()

func _run_end(end: Array) -> void:
	var ev: int = end[0]
	if ev == C["CHANGE_DIALOG"]:
		_set_count(oid, end[1]); _rerun()
	elif ev == C["END_DIALOG"]:
		_set_count(oid, end[1]); _close()
	elif ev == C["CHANGE_NPC"]:
		_set_count(end[1], end[2]); _close()
	elif ev == C["END_MISSION"]:
		_close(); main.end_mission()
	elif ev == C["START_MISSION"]:
		_close(); main.start_mission(int(end[1]))
	else:
		_close()

func _close() -> void:
	active = false; showing_options = false; _after_reply = Callable()
	main.dialog.clear_options()
	main.dialog.visible = false
	main.end_talk()
