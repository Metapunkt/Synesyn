extends SceneTree
## Ground-truth drop-in check: compile every product-addon script with no
## autoloads live, which is the state a fresh drop-in project (or headless
## tooling) starts from.
##
## `check_addon_autoloads.py` catches bare autoload identifiers by pattern; this
## catches everything else the compiler objects to (type inference, missing
## preloads, renamed symbols). Run both.
##
## Usage — copy to the project root and run with the configured Godot 4 binary:
##   <godot> --headless --quit-after 3 --path synesyn_client \
##           --script res://addon_compile_sweep.gd
##
## Exits non-zero if any script fails to compile.

const ADDON_ROOTS := [
	"res://addons/syntree",
	"res://addons/syntree_voice",
	"res://addons/synaxes",
	"res://addons/synesyn_core",
	"res://addons/synpunkt",
	"res://addons/metapunkt",
]

func _init() -> void:
	print("--- ADDON COMPILE SWEEP ---")
	var paths: Array[String] = []
	for base in ADDON_ROOTS:
		_collect(base, paths)

	var failed: Array[String] = []
	for path in paths:
		if load(path) == null:
			failed.append(path)

	print("scripts scanned: %d" % paths.size())
	if failed.is_empty():
		print("PASS: every addon script compiles with no autoloads live.")
	else:
		print("FAIL: %d script(s) did not compile:" % failed.size())
		for path in failed:
			print("  %s" % path)
		print("Scroll up for the compiler's reason on each.")
	print("--- SWEEP END ---")
	call_deferred("quit", 0 if failed.is_empty() else 1)

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
