class_name GameApi
extends RefCounted
## Native implementation of the `_util` table the game's Lua scripts call (61 distinct calls seen across all 645 chunks).
## State lives here; presentation-facing calls (dialogue, popups, SFX, camera...) are queued as events for the UI layer.
## Semantics marked (guess) are inferred from call shapes only and get refined as the engine code is read.

var vars: Dictionary = {}              # GetVar/SetVar/IncVar (scope: global (guess), may become per-object)
var inventory: Dictionary = {}         # AddInventoryItem / AddItem / DelItem
var exits_locked: Dictionary = {}
var exit_default: Callable   # id -> ROM start lock of that exit (set by main)
var suitcase_enabled: Dictionary = {}
var suitcase_equipped: Dictionary = {}
var active_mission := 0
var active_chapter := 0
var game_state := 7                  # _const.MISSION: world play (a running microgame puts its own id here)
var minigame_output1 := 0            # GetMinigameOutput1: 1 = the last microgame was completed
var conversation_count := 0
var input_enabled := true
var popup_visible := false
var events: Array = []                 # [{fn, args, self_id}] consumed by UI/world
var current_reason := 0
var current_source := 0
var current_self := 0
var anim_playing: Dictionary = {}
var positions: Dictionary = {}         # object id -> Vector2 (GetX/GetY)
var rooms_of: Dictionary = {}          # object id -> room id (IsInRoom)
var states: Dictionary = {}            # object id -> state name (SwitchState)
var unknown_calls: Dictionary = {}

var globals_: Dictionary = {}
var interests: Dictionary = {}      # object id -> 6-bit interest mask
var visible_flags: Dictionary = {}
var spawn_flags: Dictionary = {}
var success_flags: Dictionary = {}
var popup_text: Dictionary = {}     # object id -> string id (SetItemPopUpText)
var conv_counts: Dictionary = {}    # object id -> conversation count
var coins := 0
const NO_PUFFLE := 2000007
var puffle := -1                    # SetPuffle: the puffle item the puffle button drags
var puffles_enabled: Dictionary = {}
var map_shown := true              # the MAP button is there unless a script hides it (HideMap, e.g. chapter 1.01's start)
var map_alerts: Dictionary = {}      # alert id -> [type, x, y] (AddMapAlert / RemoveMapAlert)
var next_room := -1

## optional object-id argument at index i (defaults to the running script's object)
func _obj(a: Array, i: int) -> int:
	return _i(a, i) if i < a.size() and _i(a, i) > 0 else current_self

func _a(a: Array, i: int):
	return a[i] if i < a.size() else 0

func _i(a: Array, i: int) -> int:
	return int(a[i]) if i < a.size() and (a[i] is int or a[i] is float or a[i] is bool) else 0

func _ev(fn: String, args: Array) -> void:
	events.append({"fn": fn, "args": args, "self": current_self})

## Returns an Array of results, as the VM expects for a native call.
func call_api(fn: String, a: Array) -> Array:
	match fn:
		"GetReason": return [current_reason]
		"GetSource": return [current_source]
		"GetSelf": return [current_self]
		# vars/globals are keyed by string name; Inc/Dec return the new value (ARM: 0x211bb75..0x211bd71)
		"GetVar": return [vars.get(str(_a(a, 0)), 0)]
		"SetVar": vars[str(_a(a, 0))] = _a(a, 1); return [_a(a, 1)]
		"IncVar": vars[str(_a(a, 0))] = int(vars.get(str(_a(a, 0)), 0)) + 1; return [vars[str(_a(a, 0))]]
		"DecVar": vars[str(_a(a, 0))] = int(vars.get(str(_a(a, 0)), 0)) - 1; return [vars[str(_a(a, 0))]]
		"GetGlobal": return [globals_.get(str(_a(a, 0)), 0)]
		"SetGlobal": globals_[str(_a(a, 0))] = _a(a, 1); return [_a(a, 1)]
		"IncGlobal": globals_[str(_a(a, 0))] = int(globals_.get(str(_a(a, 0)), 0)) + 1; return [globals_[str(_a(a, 0))]]
		"DecGlobal": globals_[str(_a(a, 0))] = int(globals_.get(str(_a(a, 0)), 0)) - 1; return [globals_[str(_a(a, 0))]]
		"SetSource": current_source = _i(a, 0); return []
		# interests: bits 0..5 in the object's bitmask (default object = self)
		"AddInterest":
			var o := _obj(a, 1); var i := _i(a, 0)
			if i < 0 or i > 5: return [false]
			interests[o] = int(interests.get(o, 0)) | (1 << i); _ev(fn, a); return [true]
		"DelInterest":
			var o2 := _obj(a, 1); var i2 := _i(a, 0)
			if i2 < 0 or i2 > 5: return [false]
			interests[o2] = int(interests.get(o2, 0)) & ~(1 << i2); return [true]
		"HasInterest":
			var i3 := _i(a, 0)
			return [i3 >= 0 and i3 <= 5 and (int(interests.get(_obj(a, 1), 0)) & (1 << i3)) != 0]
		"SetVisible": visible_flags[_obj(a, 1)] = bool(_a(a, 0)); _ev(fn, a); return []
		"SetSpawn": spawn_flags[_obj(a, 1)] = bool(_a(a, 0)); _ev(fn, a); return []
		"SetSuccess": success_flags[_i(a, 0)] = bool(_a(a, 1)); return []
		"SetItemPopUpText": popup_text[_i(a, 0)] = _i(a, 1); return []
		"AddCoins": coins += _i(a, 0); return []
		"SubtractCoins": coins -= _i(a, 0); return []
		"ChangeRoom", "SetNextRoom": next_room = _i(a, 0); _ev(fn, a); return []
		"GetActiveMission": return [active_mission]
		"GetActiveChapter": return [active_chapter]
		"GetGameState": return [game_state]
		"GetMinigameOutput1": return [minigame_output1]
		"GetConversationCount": return [int(conv_counts.get(current_self, conversation_count))]
		"SetConversationCount": conv_counts[_obj(a, 1) if a.size() > 1 and _i(a, 1) >= 0 else current_self] = _i(a, 0); return []
		"IsPopUpVisible": return [popup_visible]
		"DisplayPopUp": popup_visible = true; _ev(fn, a); return []
		"IsAnimPlaying": return [anim_playing.get(_i(a, 0) if a.size() > 0 else current_self, false)]
		"GetX": return [int(positions.get(_i(a, 0), Vector2.ZERO).x)]
		"GetY": return [int(positions.get(_i(a, 0), Vector2.ZERO).y)]
		"IsInRoom": return [rooms_of.get(_i(a, 0), -1) == _i(a, 1)]
		"SwitchState":
			var so := _obj(a, 1)
			states[so] = _a(a, 0); anim_playing[so] = true; _ev(fn, a); return []
		"AddInventoryItem":
			# the item's zoom picture is a pop-up: set here, at once, because a script that waits on IsPopUpVisible
			# (Dot's pin, Dojo M1C2) runs on before the picture is drawn
			inventory[_i(a, 0)] = 1; popup_visible = true; _ev(fn, a); return []
		"RemoveInventoryItem":
			inventory.erase(_i(a, 0)); _ev(fn, a); return []
		"HasInventoryItem", "IsInInventory": return [inventory.has(_i(a, 0))]
		"AddItem":
			_ev(fn, a); return []
		"SetPuffle":                       # _id.Inventory_NoPuffle (2000007): no puffle follows the player
			puffle = _i(a, 0)
			if puffle == NO_PUFFLE: puffle = -1
			_ev(fn, a); return []
		"GetPuffle": return [puffle]
		"EnablePuffle": puffles_enabled[_i(a, 0)] = true; _ev(fn, a); return []
		"AddMapAlert":
			# (type, map x, map y, alert id, top-screen flag x, y)
			if a.size() >= 4: map_alerts[int(_a(a, 3))] = [int(_a(a, 0)), int(_a(a, 1)), int(_a(a, 2)), int(_a(a, 4)) if a.size() > 4 else -1, int(_a(a, 5)) if a.size() > 5 else -1]
			return []
		"RemoveMapAlert": map_alerts.erase(int(_a(a, 0))); return []
		"HideMap": map_shown = false; _ev(fn, a); return []
		"ShowMap": map_shown = true; _ev(fn, a); return []
		"DelItem":
			_ev(fn, a); return []
		"GetExitLocked": return [exits_locked.get(_i(a, 0), exit_default.call(_i(a, 0)) if exit_default.is_valid() else false)]
		"SetExitLocked": exits_locked[_i(a, 0)] = bool(_a(a, 1)); return []
		"SetSuitcaseItemEnabled": suitcase_enabled[_i(a, 0)] = bool(_a(a, 1)); return []
		"IsSuitcaseItemEnabled": return [suitcase_enabled.get(_i(a, 0), false)]
		"IsSuitcaseItemEquipped": return [suitcase_equipped.get(_i(a, 0), false)]
		"DisableInput": input_enabled = false; return []
		"EnableInput": input_enabled = true; return []
		"IsCommandCoachActive", "GetTouchValid": return [false]
		"GetActiveItemCount": return [vars.get("_active_items", 0)]
		"SetActiveItemCount": vars["_active_items"] = _a(a, 0); return []
		"GetComCount": return [0]
		"GetContext", "GetContextAttribute": return [0]
		# presentation / world-building calls: queued for the UI layer
		"AddDialog", "AddMonologue", "AddConversation", "AddLoopingOption", "AddLoopingConv", \
		"AddDialogButton", "AddComText", "AddComOption", "AddExit", "AddRoom", \
		"PlaySFX", "SetCursorPos", "ActivateNpc", "SetObjective", "SetupParticleEffects", \
		"PushCamera", "PopCamera", "StartMiniGame", "OpenCatalog", "StartMission", "EndMission":
			_ev(fn, a); return []
	unknown_calls[fn] = unknown_calls.get(fn, 0) + 1
	_ev(fn, a)
	return [0]

## Build the `_util` table for a VM; every field is a native callable routed to call_api.
func make_util(vm: LuaVM) -> LuaVM.LuaTable:
	var U := LuaVM.LuaTable.new()
	var me := self
	U.meta = {"__index": func(a: Array) -> Array:
		var name: String = a[1]
		return [func(args: Array) -> Array: return me.call_api(name, args)]}
	return U
