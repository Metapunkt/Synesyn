# res://ScenSyn/session_types/story_catalyst/sustainability/sustainability_meter.gd
extends Control

const COLOR_LOW = Color(0.9, 0.3, 0.3, 1.0)    # Red
const COLOR_MED = Color(0.9, 0.9, 0.3, 1.0)    # Yellow
const COLOR_HIGH = Color(0.3, 0.9, 0.3, 1.0)   # Green

@onready var energy_bar = %EnergyBar
@onready var community_bar = %CommunityBar
@onready var innovation_bar = %InnovationBar
@onready var environment_bar = %EnvironmentBar
@onready var equity_bar = %EquityBar
@onready var info_button = %InfoButton
@onready var details_panel = %DetailsPanel
@onready var details_container = %DetailsContainer
@onready var details_label = %DetailsLabel
@onready var close_button = %CloseButton
@onready var tips_label = %TipsLabel

# Store current metrics and influence for combined display
var current_metrics = {}
var current_influence = {}

func _ready():
	details_label.visible = false
#	details_container.visible = false
	info_button.pressed.connect(_on_info_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	print("SustainabilityMeter: Ready and connected signals")

func update_metrics(metrics: Dictionary):
	print("SustainabilityMeter: Received metrics update: ", metrics)
	current_metrics = metrics
	
	energy_bar.value = metrics[0] * 100  # Convert 0-1 range to 0-100 for ProgressBar
	community_bar.value = metrics[1] * 100
	innovation_bar.value = metrics[2] * 100
	environment_bar.value = metrics[3] * 100
	equity_bar.value = metrics[4] * 100
	
	energy_bar.self_modulate = _get_color_for_value(metrics[0])
	community_bar.self_modulate = _get_color_for_value(metrics[1])
	innovation_bar.self_modulate = _get_color_for_value(metrics[2])
	environment_bar.self_modulate = _get_color_for_value(metrics[3])
	equity_bar.self_modulate = _get_color_for_value(metrics[4])
	
	update_details_display()
	print("SustainabilityMeter: Updated progress bars and colors")

func update_influence(influence: Dictionary):
	print("SustainabilityMeter: Received influence update: ", influence)
	current_influence = influence
	update_details_display()

func update_details_display():
	var details = ""
	
	# Sustainability Metrics Section
	if not current_metrics.is_empty():
		details += """Sustainability Focus Metrics:
	
	Energy: {0}%
	Community: {1}%
	Innovation: {2}%
	Environment: {3}%
	Equity: {4}%
	
	Overall Score: {5}%

	""".format([
			int(current_metrics.get(0, 0) * 100),
			int(current_metrics.get(1, 0) * 100),
			int(current_metrics.get(2, 0) * 100),
			int(current_metrics.get(3, 0) * 100),
			int(current_metrics.get(4, 0) * 100),
			int((current_metrics.get(0, 0) + current_metrics.get(1, 0) + current_metrics.get(2, 0) + current_metrics.get(3, 0) + current_metrics.get(4, 0)) * 20)
	])
	
	# Influence Values Section
	if not current_influence.is_empty():
		details += """Player Influence Aggregate:

Story Engagement: {0}
Sustainability Focus: {1}
Creative Solutions: {2}
Character Interaction: {3}
Community Engagement: {4}
Content Depth: {5}
Energy & Urban Focus: {6}
Narrative Quality: {7}
""".format([
			current_influence.get("fun", 0),
			current_influence.get("critical_engagement", 0),
			current_influence.get("ai_creativity", 0),
			current_influence.get("ai_collaboration", 0),
			current_influence.get("public_engagement", 0),
			current_influence.get("ai_content_quality", 0),
			current_influence.get("energy_and_city", 0),
			current_influence.get("storytelling", 0)
		])
	else:
		details += """Player Influence Aggregate:

No influence values submitted yet.
Use the influence sliders and click
'Submit Influence' to see values here.
"""
	
	details_label.text = details

func _get_color_for_value(value: float) -> Color:
	if value < 0.3:
		return COLOR_LOW
	elif value < 0.7:
		return COLOR_MED
	else:
		return COLOR_HIGH

func _on_info_button_pressed():
	details_label.visible = true
	tips_label.visible = false
	info_button.text = "Info"
	close_button.text = "Switch to Tips"
#	details_container.visible = true

func _on_close_button_pressed():
	details_label.visible = false
	tips_label.visible = true
	info_button.text = "Switch to Info"
	close_button.text = "Tips"
#	details_container.visible = false
