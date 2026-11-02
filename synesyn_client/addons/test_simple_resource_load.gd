@tool
extends Node

func _ready():
	print("=== Simple Resource Loading Test ===")
	
	# Test 1: Load AgentDefinition script directly
	print("\n1. Testing AgentDefinition script loading...")
	var agent_def_script = load("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")
	if agent_def_script:
		print("✅ AgentDefinition script loaded: " + str(agent_def_script))
		var test_instance = agent_def_script.new()
		print("✅ Created instance: " + str(test_instance))
		print("  - Instance class: " + test_instance.get_class())
		test_instance.agent_id = "test"
		print("  - Set agent_id: " + test_instance.agent_id)
	else:
		print("❌ Failed to load AgentDefinition script")
	
	# Test 2: Check if file exists
	print("\n2. Testing file existence...")
	var chaplin_path = "res://addons/metapunkt/resources/agent_chaplin.tres"
	if FileAccess.file_exists(chaplin_path):
		print("✅ File exists: " + chaplin_path)
	else:
		print("❌ File does not exist: " + chaplin_path)
	
	# Test 3: Try to load the resource
	print("\n3. Testing resource loading...")
	var resource = load(chaplin_path)
	print("📋 Load result: " + str(resource))
	print("📋 Load result type: " + type_string(typeof(resource)))
	
	if resource:
		print("✅ Resource loaded successfully")
		print("  - Resource class: " + resource.get_class())
		print("  - Has script: " + str(resource.get_script() != null))
		if resource.get_script():
			print("  - Script class: " + str(resource.get_script()))
		
		# Try to access properties
		if resource.has_method("get") and "agent_id" in resource:
			print("  - Agent ID: " + str(resource.agent_id))
		else:
			print("  - Cannot access agent_id property")
	else:
		print("❌ Resource loading failed")
	
	print("\n=== Test Complete ===")
	
	# Exit after test
	get_tree().quit() 