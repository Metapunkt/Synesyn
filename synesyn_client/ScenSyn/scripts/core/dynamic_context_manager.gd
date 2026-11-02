# DynamicContextManager.gd
extends Node
class_name DynamicContextManager

# This function calls the LLM with a creative prompt to generate specific,
# actionable dilemmas for the current situation.
func generate_narrative_catalyst(situation_description: String) -> Array:
	var prompt = """
You are a creative narrative designer. Your task is to generate compelling, specific, and conflicting technical problems for a story, based on a given situation. For each problem, also generate two potential solutions that have clear benefits and risks.

**Situation:** {situation}

**Instructions:**
1. Generate **three** distinct, specific, and conflicting problems.
2. For each problem, provide **two** potential solutions.
3. Each solution must have a clear 'Benefit' and a clear 'Risk'.
4. Format the output STRICTLY as a JSON array of objects, with no other text.

**JSON Format Example:**
[
  {
    "problem": "Cascading overload at the N-4 substation.",
    "solutions": [
      {
        "name": "Reroute power through industrial lines.",
        "benefit": "Fastest way to restore partial power.",
        "risk": "May overload the backup grid, causing a wider failure."
      },
      {
        "name": "Send a team for a manual restart.",
        "benefit": "Safest method for a full system restart.",
        "risk": "Hazardous for the team and will take at least 30 minutes."
      }
    ]
  },
  {
    "problem": "Physical damage to the main undersea power cable from a recent tremor.",
    "solutions": [
      {
        "name": "Activate the emergency offshore generator.",
        "benefit": "Provides immediate power to critical infrastructure.",
        "risk": "The generator has a limited fuel supply (12 hours max)."
      },
      {
        "name": "Deploy a remote submersible to assess the damage.",
        "benefit": "Provides crucial data for a long-term repair plan.",
        "risk": "Takes several hours and does not solve the immediate power shortage."
      }
    ]
  }
]
""".format({"situation": situation_description})

	var conversation_manager = Global.get_conversation_manager()
	if not conversation_manager:
		print("DynamicContextManager: ConversationManager not found!")
		return []

	# Use a one-off call to the AI.
	var response = await conversation_manager.chat(prompt, "catalyst_generator")

	if response.success:
		var response_text = response.response
		# The AI might wrap the JSON in markdown, so we need to extract it.
		var json_start = response_text.find("[")
		var json_end = response_text.rfind("]")
		if json_start != -1 and json_end != -1:
			var json_string = response_text.substr(json_start, json_end - json_start + 1)
			var parsed_json = JSON.parse_string(json_string)
			if typeof(parsed_json) == TYPE_ARRAY:
				return parsed_json
			else:
				print("DynamicContextManager: Failed to parse JSON response. Result was not an array.")
		else:
			print("DynamicContextManager: Could not find valid JSON in the AI response.")
	else:
		print("DynamicContextManager: AI call failed. Error: " + response.error)

	return [] 