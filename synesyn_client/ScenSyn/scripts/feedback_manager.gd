class_name FeedbackManager
extends Node

signal influence_updated(aggregate_influence)

var players_influence = {}
var aggregate_influence = {
	"fun": 0.0,
	"critical_engagement": 0.0,
	"ai_creativity": 0.0,
	"ai_collaboration": 0.0,
	"public_engagement": 0.0,
	"ai_content_quality": 0.0,	
	"energy_and_city": 0.0,
	"storytelling": 0.0
}

# Legacy feedback support (keep for backward compatibility)
var players_feedback = {}
var aggregate_feedback = {
	"fun": 0.5,
	"critical_engagement": 0.5,
	"ai_creativity": 0.5,
	"ai_collaboration": 0.5,
	"public_engagement": 0.5,
	"ai_content_quality": 0.5,	
	"energy_and_city": 0.5,
	"storytelling": 0.5,
	"future_thinking": 0.5
}

func update_player_influence(player_id: int, influence: Dictionary):
	players_influence[player_id] = influence
	_calculate_aggregate_influence()
	print("Player ", player_id, " influence updated: ", influence)

func _calculate_aggregate_influence():
	aggregate_influence = {
		"fun": 0.0,
		"critical_engagement": 0.0,
		"ai_creativity": 0.0,
		"ai_collaboration": 0.0,
		"public_engagement": 0.0,
		"ai_content_quality": 0.0,
		"energy_and_city": 0.0,
		"storytelling": 0.0
	}
	
	for player_id in players_influence:
		var player_data = players_influence[player_id]
		for key in aggregate_influence:
			aggregate_influence[key] += player_data.get(key, 0.0)
	
	print("FeedbackManager: Calculated aggregate influence: ", aggregate_influence)
	influence_updated.emit(aggregate_influence)
	
	# Also send to MetapromptManager if available
	if Global.get_metaprompt_manager():
		Global.get_metaprompt_manager()._on_player_values_updated(aggregate_influence)

func get_aggregate_influence() -> Dictionary:
	return aggregate_influence

# Legacy feedback methods (keep for backward compatibility)
func update_player_feedback(player_id: int, feedback: Dictionary):
	players_feedback[player_id] = feedback
	calculate_aggregate_feedback()

func calculate_aggregate_feedback():
	for key in aggregate_feedback.keys():
		var total = 0.0
		var count = 0
		for player_feedback in players_feedback.values():
			if player_feedback.has(key):
				total += player_feedback[key]
				count += 1
		if count > 0:
			aggregate_feedback[key] = total / count
				
	emit_signal("feedback_updated", aggregate_feedback)
	if Global.get_metaprompt_manager():
		Global.get_metaprompt_manager()._on_feedback_updated(aggregate_feedback)

func get_aggregate_feedback() -> Dictionary:
	return aggregate_feedback
	
