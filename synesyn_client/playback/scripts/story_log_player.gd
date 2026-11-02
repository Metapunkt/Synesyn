extends Control

## Plays a saved story log on a Story Stage, with no session, model or hub behind it.
## The stage holds each line for as long as its voice, or its reading time, takes; the
## player decides when the next entry may follow: straight after (reading pace), after
## the gap it originally had (original timing), or when asked (manual).
##
## Open a log from the command line with `-- --story-log=<path>` to start playing at
## once, which is how an exhibition machine can boot straight into a looping log.

const StoryStageScene = preload("res://addons/story_stage/scenes/story_stage.tscn")
const LAUNCHER_SCENE := "res://scenes/synesyn_launcher.tscn"
const STORY_LOG_ARG := "--story-log="
const LOOP_ARG := "--loop"

enum Pace { READING, ORIGINAL, MANUAL }

const PACE_NAMES := {Pace.READING: "reading", Pace.ORIGINAL: "original", Pace.MANUAL: "manual"}
const SPEEDS: Array[float] = [0.5, 1.0, 1.5, 2.0, 4.0]
## Longest wait original timing keeps; a session idle for minutes plays as a pause.
const MAX_ORIGINAL_GAP_S := 20.0
## Rest between the last line of a pass and the first line of the next, when looping.
const LOOP_REST_S := 4.0

@onready var _stage_slot: Node = %StageSlot
@onready var _open_button: Button = %OpenButton
@onready var _play_button: Button = %PlayButton
@onready var _step_button: Button = %StepButton
@onready var _pace_option: OptionButton = %PaceOption
@onready var _speed_option: OptionButton = %SpeedOption
@onready var _loop_toggle: CheckButton = %LoopToggle
@onready var _sprites_button: Button = %SpritesButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel

const PlayIcon: Texture2D = preload("res://Synesyn_icons/synesyn-button-icons/icon_play_triangle.svg")
const PauseIcon: Texture2D = preload("res://Synesyn_icons/synesyn-button-icons/icon_pause_bars.svg")

var host: StoryLogPlaybackHost = StoryLogPlaybackHost.new()
var stage: Node = null
var pace: Pace = Pace.READING
var speed: float = 1.0
var loop: bool = false
var playing: bool = false

## Lines the stage has shown since the player started, across every pass of a loop.
var lines_displayed: int = 0
var passes_completed: int = 0
var _displayed_this_pass: int = 0
var _pass_finished: bool = false
var _reveal_at_ms: int = -1
var _loop_at_ms: int = -1


func _ready() -> void:
	stage = StoryStageScene.instantiate()
	stage.host = host
	_stage_slot.add_child(stage)
	stage.line_displayed.connect(_on_line_displayed)

	_open_button.pressed.connect(_on_open_pressed)
	_play_button.pressed.connect(toggle_play)
	_step_button.pressed.connect(step)
	_back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(LAUNCHER_SCENE))
	_sprites_button.pressed.connect(_on_sprites_pressed)
	for pace_id: int in PACE_NAMES:
		_pace_option.add_item(String(PACE_NAMES[pace_id]).capitalize(), pace_id)
	_pace_option.item_selected.connect(func(index: int) -> void: set_pace(_pace_option.get_item_id(index) as Pace))
	for s: float in SPEEDS:
		_speed_option.add_item("%s×" % String.num(s))
	_speed_option.select(SPEEDS.find(speed))
	_speed_option.item_selected.connect(func(index: int) -> void: set_speed(SPEEDS[index]))
	_loop_toggle.toggled.connect(set_loop)
	_apply_read_pause()
	_refresh_controls()
	_status("Open a story log to play it.")
	_open_from_command_line.call_deferred()


func _open_from_command_line() -> void:
	var path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(STORY_LOG_ARG):
			path = arg.substr(STORY_LOG_ARG.length()).strip_edges()
		elif arg == LOOP_ARG:
			set_loop(true)
	if not path.is_empty():
		open_log(path)


## Loads a story log and plays it from its first line. Returns whether it loaded.
func open_log(path: String) -> bool:
	var error: String = host.load_log(path)
	if not error.is_empty():
		_status(error)
		return false
	passes_completed = 0
	playing = pace != Pace.MANUAL
	StoryStageCharacter.clear_all_characters()
	if stage.background_controller:
		stage.background_controller.restage_scenario_background()
	_restart_pass()
	var note: String = "" if not host.stage_info().is_empty() else " (no stage record: dialogue only)"
	_status("%s: %d lines%s" % [path.get_file(), host.entry_count(), note])
	return true


func _restart_pass() -> void:
	host.rewind()
	_displayed_this_pass = 0
	_pass_finished = false
	_loop_at_ms = -1
	_reveal_at_ms = Time.get_ticks_msec() if pace != Pace.MANUAL else -1
	stage.replay_story_log()
	_refresh_controls()


func toggle_play() -> void:
	set_playing(not playing)

func set_playing(value: bool) -> void:
	if host.entry_count() == 0:
		return
	playing = value
	if playing and _pass_finished and _loop_at_ms == 0:
		_restart_pass()
		return
	if stage.voice:
		if playing:
			stage.voice.resume()
		else:
			stage.voice.pause()
	if playing and pace != Pace.MANUAL and _reveal_at_ms < 0 and _all_revealed_shown():
		_reveal_at_ms = Time.get_ticks_msec()
	_refresh_controls()

## Lets the next entry onto the stage now, whatever the pace.
func step() -> void:
	if _all_revealed_shown():
		_reveal_at_ms = -1
		host.reveal_next()

func set_pace(value: Pace) -> void:
	pace = value
	_pace_option.select(_pace_option.get_item_index(pace))
	_apply_read_pause()
	if pace == Pace.MANUAL:
		_reveal_at_ms = -1
	elif _reveal_at_ms < 0 and _all_revealed_shown() and not _pass_finished:
		_reveal_at_ms = Time.get_ticks_msec()
	_refresh_controls()

func set_speed(value: float) -> void:
	speed = maxf(0.1, value)
	var index: int = SPEEDS.find(speed)
	if index >= 0:
		_speed_option.select(index)
	_apply_read_pause()

func set_loop(value: bool) -> void:
	loop = value
	_loop_toggle.set_pressed_no_signal(loop)


## A manual step should not sit through a reading pause; otherwise speed shortens it.
func _apply_read_pause() -> void:
	if stage and stage.line_feed:
		stage.line_feed.read_pause_scale = 0.0 if pace == Pace.MANUAL else 1.0 / speed


func _all_revealed_shown() -> bool:
	return _displayed_this_pass >= host.revealed_count()


func _on_line_displayed(_speaker: String, _message: String, index: int) -> void:
	lines_displayed += 1
	_displayed_this_pass = index + 1
	if index + 1 >= host.entry_count():
		_pass_finished = true
		_refresh_controls()
		return
	match pace:
		Pace.READING:
			_reveal_at_ms = Time.get_ticks_msec()
		Pace.ORIGINAL:
			var gap: float = host.original_gap_seconds(index + 1)
			var wait_s: float = 0.0 if gap < 0.0 else minf(gap, MAX_ORIGINAL_GAP_S) / speed
			_reveal_at_ms = Time.get_ticks_msec() + int(wait_s * 1000.0)
		Pace.MANUAL:
			_reveal_at_ms = -1


func _process(_delta: float) -> void:
	if host.entry_count() == 0:
		return
	var now: int = Time.get_ticks_msec()
	if playing and _reveal_at_ms >= 0 and now >= _reveal_at_ms:
		_reveal_at_ms = -1
		host.reveal_next()
	if _pass_finished and _loop_at_ms < 0 and not stage.is_displaying_message:
		passes_completed += 1
		_loop_at_ms = now + int(LOOP_REST_S * 1000.0) if loop else 0
		if not loop:
			playing = false
			_refresh_controls()
			_status("%s: finished" % host.log_path.get_file())
	if loop and _loop_at_ms > 0 and now >= _loop_at_ms:
		_restart_pass()


func _refresh_controls() -> void:
	var has_log: bool = host.entry_count() > 0
	_play_button.disabled = not has_log
	_play_button.icon = PauseIcon if playing else PlayIcon
	_play_button.text = "Pause" if playing else "Play"
	_step_button.disabled = not has_log


func _status(text: String) -> void:
	_status_label.text = text
	print("StoryLogPlayer: ", text)


func _on_open_pressed() -> void:
	_pick(FileDialog.FILE_MODE_OPEN_FILE, "Open Story Log", host.get_story_log_dir(), func(path: String) -> void: open_log(path))

func _on_sprites_pressed() -> void:
	var start_dir: String = host.get_sprite_root() if not host.get_sprite_root().is_empty() else host.get_story_log_dir()
	_pick(FileDialog.FILE_MODE_OPEN_DIR, "Choose a sprite folder (one folder per character)", start_dir, func(path: String) -> void:
		host.set_sprite_root(path)
		_status("Sprites from %s" % path)
	)

func _pick(mode: FileDialog.FileMode, title: String, start_dir: String, on_chosen: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.title = title
	if mode == FileDialog.FILE_MODE_OPEN_FILE:
		dialog.filters = PackedStringArray(["*.json ; Story logs"])
	dialog.current_dir = start_dir
	add_child(dialog)
	var chosen := func(path: String) -> void:
		dialog.queue_free()
		on_chosen.call(path)
	dialog.file_selected.connect(chosen)
	dialog.dir_selected.connect(chosen)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.6)


## What the harness asserts on: every line shown, and nothing reached for a hub.
func get_playback_report() -> Dictionary:
	return {
		"log_file": host.log_path.get_file(),
		"entry_count": host.entry_count(),
		"revealed": host.revealed_count(),
		"lines_displayed": lines_displayed,
		"displayed_this_pass": _displayed_this_pass,
		"all_lines_displayed": host.entry_count() > 0 and _displayed_this_pass >= host.entry_count(),
		"passes_completed": passes_completed,
		"pace": PACE_NAMES[pace],
		"speed": speed,
		"loop": loop,
		"has_stage_record": not host.stage_info().is_empty(),
		"voice_on": bool(stage.voice_on()),
	}


func test_apply_state(state: Dictionary) -> void:
	var hooks: Node = get_node_or_null("DevHarnessHooks")
	if hooks and hooks.has_method("apply_state"):
		hooks.apply_state(state)

func test_dump_logs(output_path: String, since_msec: int = 0) -> void:
	var hooks: Node = get_node_or_null("DevHarnessHooks")
	if hooks and hooks.has_method("dump_logs"):
		hooks.dump_logs(output_path, since_msec)
