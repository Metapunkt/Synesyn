extends Node

"""
Simple test to verify AgentDefinition resources load correctly
"""

func _ready():
	print("Testing AgentDefinition resource loading...")
	
	# Test loading Agent-Chaplin
	var chaplin_path = "res://addons/metapunkt/resources/agent_chaplin.tres"
	var chaplin_def = load(chaplin_path) as AgentDefinition
	
	if chaplin_def:
		print("✅ Agent-Chaplin loaded successfully")
		print("  - ID: %s" % chaplin_def.agent_id)
		print("  - Name: %s" % chaplin_def.agent_name) 
		print("  - Role: %s" % chaplin_def.role)
		print("  - Logic Type: %s" % chaplin_def.logic_type)
		print("  - Required Tools: %s" % str(chaplin_def.required_tools))
		print("  - Required Tools Type: %s" % type_string(typeof(chaplin_def.required_tools)))
	else:
		print("❌ Failed to load Agent-Chaplin")
	
	# Test loading Agent-Alexander
	var alexander_path = "res://addons/metapunkt/resources/agent_alexander.tres"
	var alexander_def = load(alexander_path) as AgentDefinition
	
	if alexander_def:
		print("✅ Agent-Alexander loaded successfully")
		print("  - ID: %s" % alexander_def.agent_id)
		print("  - Name: %s" % alexander_def.agent_name)
		print("  - Role: %s" % alexander_def.role)
		print("  - Logic Type: %s" % alexander_def.logic_type)
		print("  - Required Tools: %s" % str(alexander_def.required_tools))
		print("  - Required Tools Type: %s" % type_string(typeof(alexander_def.required_tools)))
	else:
		print("❌ Failed to load Agent-Alexander")
	
	print("\nResource loading test completed.")

const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd") 