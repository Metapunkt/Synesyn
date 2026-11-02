# workplan_task_card.gd
extends PanelContainer

@onready var core_idea_label = $MarginContainer/VBoxContainer/CoreIdeaLabel
@onready var status_label = $MarginContainer/VBoxContainer/HBoxContainer/StatusLabel
@onready var channel_label = $MarginContainer/VBoxContainer/HBoxContainer/ChannelLabel
@onready var completion_checkbox = $MarginContainer/VBoxContainer/HBoxContainer/CompletionCheckbox
@onready var priority_label = $MarginContainer/VBoxContainer/DetailsContainer/PriorityLabel
@onready var format_label = $MarginContainer/VBoxContainer/DetailsContainer/FormatLabel
@onready var progress_bar = $MarginContainer/VBoxContainer/ProgressBar
@onready var content_preview = $MarginContainer/VBoxContainer/ContentPreview
@onready var action_buttons = $MarginContainer/VBoxContainer/ActionButtons
@onready var start_button = $MarginContainer/VBoxContainer/ActionButtons/StartButton
@onready var review_button = $MarginContainer/VBoxContainer/ActionButtons/ReviewButton
@onready var complete_button = $MarginContainer/VBoxContainer/ActionButtons/CompleteButton
@onready var edit_button = $MarginContainer/VBoxContainer/ActionButtons/EditButton
@onready var delete_button = $MarginContainer/VBoxContainer/ActionButtons/DeleteButton

var current_task: WorkplanTask
var refresh_timer: Timer

signal task_updated(task: WorkplanTask)
signal task_action_requested(action: String, task: WorkplanTask)

func _ready():
	# Set up refresh timer for real-time updates
	refresh_timer = Timer.new()
	add_child(refresh_timer)
	refresh_timer.wait_time = 1.0  # Update every second
	refresh_timer.timeout.connect(_refresh_display)
	refresh_timer.start()
	
	# Connect action buttons
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if review_button:
		review_button.pressed.connect(_on_review_pressed)
	if complete_button:
		complete_button.pressed.connect(_on_complete_pressed)
	if edit_button:
		edit_button.pressed.connect(_on_edit_pressed)
	if delete_button:
		delete_button.pressed.connect(_on_delete_pressed)
	if completion_checkbox:
		completion_checkbox.toggled.connect(_on_completion_toggled)

func setup_task(task: WorkplanTask):
	current_task = task
	_refresh_display()

func setup(task: WorkplanTask):
	current_task = task
	_refresh_display()

func _refresh_display():
	if not current_task:
		return
	
	# Update basic info - use title for display
	core_idea_label.text = current_task.title
	status_label.text = "Status: %s" % current_task.status
	channel_label.text = "Channel: %s" % current_task.channel
	
	# Update completion checkbox
	if completion_checkbox:
		completion_checkbox.button_pressed = (current_task.status == "Done")
		completion_checkbox.text = "✅ Completed" if current_task.status == "Done" else "☐ Mark Complete"
	
	# Update details
	if priority_label:
		priority_label.text = "Priority: %d" % current_task.priority
	if format_label:
		format_label.text = "Format: %s" % current_task.format
	
	# Update status color
	status_label.add_theme_color_override("font_color", current_task.get_status_color())
	
	# Update progress bar
	if progress_bar:
		var progress_value = _get_progress_value()
		progress_bar.value = progress_value
		progress_bar.modulate = current_task.get_status_color()
	
	# Update content preview
	if content_preview:
		if current_task.generated_content and not current_task.generated_content.is_empty():
			var preview_text = current_task.generated_content
			if preview_text.length() > 200:
				preview_text = preview_text.substr(0, 200) + "..."
			
			var preview_content = "Content Preview:\n" + preview_text
			
			# Add deliverable path if available
			if current_task.deliverable_path and not current_task.deliverable_path.is_empty():
				preview_content += "\n\n📄 Saved to: " + current_task.deliverable_path
			
			content_preview.text = preview_content
			content_preview.show()
		else:
			content_preview.hide()
	
	# Update action buttons visibility
	_update_action_buttons()
	
	# Update panel style based on status
	_update_panel_style()

func _get_progress_value() -> float:
	match current_task.status:
		"To Do":
			return 0.0
		"In Progress":
			return 50.0
		"Review":
			return 75.0
		"Done":
			return 100.0
		_:
			return 0.0

func _update_action_buttons():
	if not action_buttons:
		return
	
	# Show/hide buttons based on current status
	if start_button:
		start_button.visible = current_task.status == "To Do"
	if review_button:
		review_button.visible = current_task.status == "In Progress"
	if complete_button:
		complete_button.visible = current_task.status == "Review"
	if edit_button:
		edit_button.visible = true  # Always allow editing
	if delete_button:
		delete_button.visible = true  # Always allow deletion

func _update_panel_style():
	# Add visual indicators based on status
	match current_task.status:
		"In Progress":
			modulate = Color(1.0, 1.0, 0.8)  # Slight yellow tint
		"Review":
			modulate = Color(1.0, 0.9, 0.7)  # Slight orange tint
		"Done":
			modulate = Color(0.8, 1.0, 0.8)  # Slight green tint
		_:
			modulate = Color.WHITE

# Action button handlers
func _on_start_pressed():
	current_task.start_task()
	task_action_requested.emit("start", current_task)
	task_updated.emit(current_task)

func _on_review_pressed():
	current_task.send_for_review()
	task_action_requested.emit("review", current_task)
	task_updated.emit(current_task)

func _on_complete_pressed():
	current_task.complete_task()
	task_action_requested.emit("complete", current_task)
	task_updated.emit(current_task)

func _on_edit_pressed():
	task_action_requested.emit("edit", current_task)

func _on_delete_pressed():
	task_action_requested.emit("delete", current_task)

func _on_completion_toggled(button_pressed: bool):
	if button_pressed:
		current_task.complete_task()
		task_action_requested.emit("complete", current_task)
		task_updated.emit(current_task)
	else:
		current_task.status = "To Do"
		current_task.completion_date = ""
		task_action_requested.emit("uncomplete", current_task)
		task_updated.emit(current_task)

func get_task() -> WorkplanTask:
	return current_task 
