# bt_get_next_task.gd
class_name BTGetNextTask extends BTAction

@export var output_task_var: String = "next_task"

var orchestrator

func _setup():
	orchestrator = agent.get_node("/root/ReadyMadeOrchestrator")

func _tick(delta):
	print("BTGetNextTask: Searching for the next available task...")
	var all_months = orchestrator.get_all_tasks()

	for month_name in all_months.keys():
		var tasks_for_month = all_months[month_name]
		for task in tasks_for_month:
			if task.status == "To Do":
				print("BTGetNextTask: Found task: ", task.core_idea)
				# Store the found task on the blackboard
				blackboard.set(output_task_var, task)
				return SUCCESS
	
	print("BTGetNextTask: No 'To Do' tasks found.")
	return FAILURE 
