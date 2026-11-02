@tool
extends EditorPlugin
## Library addon: registers shared ThemeManager autoload.
## Product addons (SynAxes, SynTree, Metapunkt, SynPunkt) depend on this folder.
## See ADR 0017.

const THEME_MANAGER_PATH := "res://addons/synesyn_core/scripts/theme_manager.gd"

func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/ThemeManager"):
		add_autoload_singleton("ThemeManager", THEME_MANAGER_PATH)
	print("Synesyn Core plugin initialized")

func _exit_tree() -> void:
	# Do not remove ThemeManager on disable while the host project still lists
	# it in project.godot — that would break ScenSyn/Tools at runtime mid-session.
	print("Synesyn Core plugin cleaned up")
