class_name AnalyticsManager
extends Node

var feedback_history = []
var feedback_manager = null

func _ready():
	pass
	#var feedback_manager = get_node("/root/FeedbackManager")
	#feedback_manager.connect("feedback_updated", Callable(self, "_on_feedback_updated"))

func setup_feedback_manager(manager):
	feedback_manager = manager
	if feedback_manager:
		feedback_manager.connect("feedback_updated", Callable(self, "_on_feedback_updated"))
	else:
		print("Warning: FeedbackManager not provided to AnalyticsManager")
		
func _on_feedback_updated(feedback: Dictionary):
	feedback_history.append({
		"timestamp": Time.get_unix_time_from_system(),
		"feedback": feedback
	})

func generate_report() -> String:
	var report = "Feedback Analytics Report\n\n"
	
	# Calculate averages
	var averages = {}
	for entry in feedback_history:
		for key in entry["feedback"].keys():
			if not averages.has(key):
				averages[key] = 0
			averages[key] += entry["feedback"][key]
	
	for key in averages.keys():
		averages[key] /= feedback_history.size()
		report += key + " average: " + str(averages[key]) + "\n"
	
	# Add more complex analytics here...
	
	return report
