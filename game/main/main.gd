extends Node
## Entry point. Parses command-line user args (after "--") for headless simulation.

var args: Dictionary = {}

func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	print("KOTM main ready; args=%s" % [args])

static func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
