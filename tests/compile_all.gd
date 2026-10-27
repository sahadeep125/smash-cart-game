## Loads every script in the project so parse/compile errors show up in one run.
## Run: godot --headless --path . res://tests/compile_all.tscn
extends Node


func _ready() -> void:
	var failed := 0
	var total := 0
	for path in _scripts("res://scripts"):
		total += 1
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			failed += 1
			print("FAIL ", path)
	print("COMPILE RESULT: %d scripts, %d failed" % [total, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_scripts(dir + "/" + sub))
	return out
