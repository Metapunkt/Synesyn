#influence_ui.gd
extends Control

var feedback_manager: FeedbackManager

# Store influence values locally until submitted
var current_influence = {
	"fun": 0.0,
	"critical_engagement": 0.0,
	"ai_creativity": 0.0,
	"ai_collaboration": 0.0,
	"public_engagement": 0.0,
	"ai_content_quality": 0.0,
	"energy_and_city": 0.0,
	"storytelling": 0.0
}

@onready var fun_slider = %FunSlider
@onready var critical_engagement_slider = %CriticalEngagementSlider
@onready var ai_creativity_slider = %AICreativitySlider
@onready var ai_collaboration_slider = %AICollaborationSlider
@onready var public_engagement_slider = %PublicEngagementSlider
@onready var ai_content_quality_slider = %AIContentQualitySlider
@onready var energy_and_city_slider = %EnergyAndCitySlider
@onready var storytelling_slider = %StoryTellingSlider
@onready var submit_influence_btn = %Submit_Influence_Btn

func _ready():	
	# Connect sliders to local value tracking (not immediate submission)
	fun_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("fun"))
	critical_engagement_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("critical_engagement"))
	ai_creativity_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("ai_creativity"))
	ai_collaboration_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("ai_collaboration"))
	public_engagement_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("public_engagement"))
	ai_content_quality_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("ai_content_quality"))
	energy_and_city_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("energy_and_city"))
	storytelling_slider.connect("value_changed", Callable(self, "_on_slider_changed").bind("storytelling"))
	
	# Connect submit button
	submit_influence_btn.connect("pressed", Callable(self, "_on_submit_influence_pressed"))
	
func _on_slider_changed(value: float, key: String):
	# Store value locally, don't submit immediately
	current_influence[key] = value
	print("Influence updated locally - ", key, ": ", value)

func _on_submit_influence_pressed():
	# Submit all current influence values when button is pressed
	if feedback_manager:
		var player_id = multiplayer.get_unique_id()
		print("Submitting influence values: ", current_influence)
		feedback_manager.update_player_influence(player_id, current_influence)
	else:
		print("Error: feedback_manager is null in InfluenceUI")
	
func set_feedback_manager(manager: FeedbackManager):
	feedback_manager = manager
