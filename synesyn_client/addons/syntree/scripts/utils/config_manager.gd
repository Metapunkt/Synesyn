## Purpose: ConfigManager (script)
@tool
extends Node
class_name ConfigManager

# res:// is read-only in exported builds — persist under Documents/Synesyn (ADR 0014).
# On first run, migrate legacy user:// then seed from res:// if needed.
const _CONFIG_FILE_RES: String  = "res://addons/syntree/config.cfg"
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")

# Configuration sections
var _config: ConfigFile
var _default_config: Dictionary = {
	"api": {
		"anthropic_key": "",
		"openai_key": "",
		"google_key": "",
		"deepseek_key": "",
		"xai_key": "",
		"base_url": "https://api.anthropic.com/v1"
	},
	"ai": {
		"default_model": "claude-3-5-sonnet-20241022",
		"temperature": 0.7,
		"max_tokens": 2000
	},
	"ui": {
		"theme": "default",
		"font_size": 14,
		"show_timestamps": true
	}
}

func _init():
	print("ConfigManager: Initializing...")
	_config = ConfigFile.new()
	_load_config()

func _config_file_path() -> String:
	var dest: String = RuntimeConfigScript.get_syntree_config_path()
	RuntimeConfigScript.migrate_file_if_needed(dest, ["user://syntree_config.cfg"])
	return dest

func _load_config() -> void:
	# 1. Prefer Documents/Synesyn writable path (migrates legacy user:// once).
	var config_path: String = _config_file_path()
	if FileAccess.file_exists(config_path):
		var err: int = _config.load(config_path)
		if err == OK:
			print("ConfigManager: Loaded from Documents/Synesyn")
			return
		push_warning("ConfigManager: Failed to load Documents config (err=%d), falling back to res://" % err)

	# 2. Try the bundled res:// seed (read-only; works in both editor and build).
	if FileAccess.file_exists(_CONFIG_FILE_RES):
		var err: int = _config.load(_CONFIG_FILE_RES)
		if err == OK:
			print("ConfigManager: Seeded from res://; saving to Documents/Synesyn.")
			_save_to_user()
			return
		push_warning("ConfigManager: Failed to load res:// seed (err=%d); creating defaults." % err)

	# 3. Neither file found — create defaults in memory and save.
	print("ConfigManager: No config found; creating defaults.")
	_create_default_config()

func _create_default_config() -> void:
	for section in _default_config:
		for key in _default_config[section]:
			_config.set_value(section, key, _default_config[section][key])
	_save_to_user()

func _save_to_user() -> void:
	var config_path: String = _config_file_path()
	DirAccess.make_dir_recursive_absolute(config_path.get_base_dir())
	var err: int = _config.save(config_path)
	if err != OK:
		push_warning("ConfigManager: Could not write config (err=%d). Keys will not persist across sessions." % err)
	else:
		print("ConfigManager: Config saved to Documents/Synesyn")

func get_value(section: String, key: String, default = null):
	return _config.get_value(section, key, default)

func set_value(section: String, key: String, value) -> void:
	_config.set_value(section, key, value)
	_save_to_user()

func get_api_key(provider: String) -> String:
	print("ConfigManager: Getting API key for provider:", provider)
	match provider.to_lower():
		"anthropic":
			var anthropic_key = get_value("api", "anthropic_key", "")
			print("ConfigManager: Anthropic key found:", not anthropic_key.is_empty())
			return anthropic_key
		"openai":
			var openai_key = get_value("api", "openai_key", "")
			print("ConfigManager: OpenAI key found:", not openai_key.is_empty())
			return openai_key
		"google":
			var google_key = get_value("api", "google_key", "")
			print("ConfigManager: Google key found:", not google_key.is_empty())
			return google_key
		"deepseek":
			var deepseek_key = get_value("api", "deepseek_key", "")
			print("ConfigManager: Deepseek key found:", not deepseek_key.is_empty())
			return deepseek_key
		"xai":
			var xai_key = get_value("api", "xai_key", "")
			print("ConfigManager: xAI key found:", not xai_key.is_empty())
			return xai_key
		_:
			print("ConfigManager: Unknown provider:", provider)
			return ""

func set_api_key(provider: String, key: String) -> void:
	print("ConfigManager: Setting API key for provider:", provider)
	match provider.to_lower():
		"anthropic":
			set_value("api", "anthropic_key", key)
			print("ConfigManager: Anthropic key saved")
		"openai":
			set_value("api", "openai_key", key)
			print("ConfigManager: OpenAI key saved")
		"google":
			set_value("api", "google_key", key)
			print("ConfigManager: Google key saved")
		"deepseek":
			set_value("api", "deepseek_key", key)
			print("ConfigManager: Deepseek key saved")
		"xai":
			set_value("api", "xai_key", key)
			print("ConfigManager: xAI key saved")
		_:
			print("ConfigManager: Unknown provider:", provider)
