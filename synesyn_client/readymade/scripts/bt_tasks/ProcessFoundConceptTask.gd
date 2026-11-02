@tool
extends BTTask
class_name ProcessFoundConceptTask
## LimboAI Task to process a Found Concept and generate content assets using SynTree AI.

const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")

var task_completed: bool = false
var conversation_manager: Node = null
var processing_state: String = "idle"  # idle, processing, completed
var current_processing_task: WorkplanTask = null
var has_shown_debug: bool = false
var _last_store_context_meta: Dictionary = {}

# Metapunkt opt-in (slot assignment)
const _SLOT_ID := "readymade.a1"

func _setup():
	print("ProcessFoundConceptTask: Starting new task processing session")
	# Ensure a stable session id for this run (used for hub + metapunkt alignment).
	SynesynSession.get_or_create_session_id("readymade")
	task_completed = false
	processing_state = "idle"
	current_processing_task = null
	_initialize_syntree_connection()

func _initialize_syntree_connection():
	"""Initialize connection to SynTree AI services"""
	# Get PluginManager autoload
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		var plugin_manager = tree.root.get_node_or_null("PluginManager")
		if plugin_manager:
			conversation_manager = plugin_manager.get("conversation_manager")
			if conversation_manager:
				print("ProcessFoundConceptTask: ✓ Connected to SynTree AI")
			else:
				print("ProcessFoundConceptTask: ⚠ ConversationManager not available")
		else:
			print("ProcessFoundConceptTask: ⚠ PluginManager not found")

func _tick(_delta: float) -> int:
	# Get dependencies from blackboard
	var orchestrator = blackboard.get_var("orchestrator")
	var current_task = blackboard.get_var("current_task")
	
	if not orchestrator or not current_task:
		# Only show debug info once per task to avoid spam
		if not has_shown_debug:
			print("ProcessFoundConceptTask: 🔍 Debug blackboard access:")
			print("  - blackboard exists: ", blackboard != null)
			if blackboard:
				print("  - orchestrator value: ", orchestrator)
				print("  - current_task value: ", current_task)
				print("  - orchestrator var exists: ", blackboard.has_var("orchestrator"))
				print("  - current_task var exists: ", blackboard.has_var("current_task"))
			# This is common during initialization before the blackboard is populated.
			# Use print (not push_warning) to avoid spamming the Debugger with non-actionable warnings.
			print("ProcessFoundConceptTask: Missing dependencies - orchestrator or current_task not found")
			has_shown_debug = true
		# This commonly happens during initialization before the blackboard is populated.
		# Don't hard-fail the tree; just keep running until dependencies are present.
		return BT.Status.RUNNING
	
	# Check if this is a new task or we're continuing with the same one
	if current_processing_task != current_task:
		# New task - reset state
		processing_state = "idle"
		task_completed = false
		current_processing_task = current_task
		has_shown_debug = false  # Reset debug flag for new task
		_last_store_context_meta = {}
	
	# State machine for processing
	match processing_state:
		"idle":
			print("ProcessFoundConceptTask: 🚀 Processing task: ", current_task.core_idea)
			current_task.start_task()
			processing_state = "processing"
			_start_content_generation(current_task)
			return BT.Status.RUNNING
			
		"processing":
			# Still processing - keep running
			return BT.Status.RUNNING
			
		"completed":
			# Task is done
			return BT.Status.SUCCESS
	
	return BT.Status.RUNNING

func _start_content_generation(task: WorkplanTask) -> void:
	"""Start content generation process without blocking _tick"""
	# Use call_deferred to avoid blocking the behavior tree
	call_deferred("_generate_content_with_ai", task)

func _generate_content_with_ai(task: WorkplanTask) -> void:
	"""Enhanced content generation with robust error handling and progress tracking"""
	# If Metapunkt slot is assigned, we can still proceed even if ConversationManager is unavailable.
	var mp_agent_id := _get_metapunkt_assigned_agent_id(_SLOT_ID)
	var use_metapunkt := not mp_agent_id.is_empty()
	if not conversation_manager and not use_metapunkt:
		print("ProcessFoundConceptTask: ⚠ No AI available, using placeholder content")
		_complete_task_with_placeholder(task)
		return
	
	# Create content generation prompt based on task details
	var content_prompt = _build_content_prompt(task)
	var store_context: Dictionary = await _readymade_store_context_pack()
	if bool(store_context.get("ok", false)):
		_last_store_context_meta = store_context
		content_prompt += "\n\n## STFX Store Context Pack\n"
		content_prompt += str(store_context.get("text", ""))
	print("ProcessFoundConceptTask: 🤖 Generating content with AI...")
	
	# Enhanced retry mechanism with better error handling
	var max_retries = 5  # Increased retries
	var base_retry_delay = 1.0
	var response = null
	var last_error = ""
	
	for attempt in range(max_retries):
		print("ProcessFoundConceptTask: 🔄 AI generation attempt ", attempt + 1, "/", max_retries)
		
		# Calculate retry delay with exponential backoff + jitter
		var retry_delay = base_retry_delay * pow(1.5, attempt) + randf() * 0.5
		
		# Use Metapunkt agent (opt-in) or ConversationManager to generate content
		var thread_name = "readymade_task_" + str(Time.get_unix_time_from_system()) + "_" + str(attempt)
		if use_metapunkt:
			response = await _metapunkt_chat(mp_agent_id, content_prompt, thread_name)
		else:
			response = await conversation_manager.chat(content_prompt, thread_name)
		
		# Check if request succeeded
		if response and response.has("success") and response.success:
			print("ProcessFoundConceptTask: ✅ AI generation successful on attempt ", attempt + 1)
			break
		
		# Capture error for reporting
		last_error = response.get("error", "Unknown error") if response else "No response received"
		print("ProcessFoundConceptTask: ⚠ Attempt ", attempt + 1, " failed: ", last_error)
		
		# Check for specific error types
		if "HTTPRequest is busy" in last_error:
			print("ProcessFoundConceptTask: 🔄 HTTPRequest busy, will retry...")
		elif "timeout" in last_error.to_lower():
			print("ProcessFoundConceptTask: ⏰ Request timeout, will retry...")
		elif "rate limit" in last_error.to_lower():
			print("ProcessFoundConceptTask: 🚦 Rate limited, increasing delay...")
			retry_delay *= 2.0  # Double delay for rate limits
		elif "authentication" in last_error.to_lower() or "unauthorized" in last_error.to_lower():
			print("ProcessFoundConceptTask: 🔐 Authentication error - not retryable")
			break  # Don't retry auth errors
		
		# Wait before retry if not the last attempt
		if attempt < max_retries - 1:
			print("ProcessFoundConceptTask: ⏳ Waiting %.1fs before retry..." % retry_delay)
			var tree = Engine.get_main_loop() as SceneTree
			if tree:
				await tree.create_timer(retry_delay).timeout
			else:
				# Fallback delay
				var start_time = Time.get_ticks_msec()
				while Time.get_ticks_msec() - start_time < retry_delay * 1000:
					await Engine.get_main_loop().process_frame
	
	# Process the final response
	if response and response.has("success") and response.success:
		print("ProcessFoundConceptTask: ✅ AI content generation successful")
		
		# Validate response content
		if not response.response or response.response.strip_edges().is_empty():
			print("ProcessFoundConceptTask: ⚠ AI returned empty content, using placeholder")
			_complete_task_with_placeholder(task)
			return
		
		task.generated_content = response.response
		task.complete_task()
		
		# Save the generated content to file with error handling
		_save_content_to_file(task)
		await _commit_readymade_store_output(task)
		print("ProcessFoundConceptTask: 📄 Content saved to file")
		
		# Trigger persistence with error handling
		var orchestrator = blackboard.get_var("orchestrator")
		if orchestrator:
			orchestrator.update_task(task)
			print("ProcessFoundConceptTask: 📄 Content saved and task completed successfully")
		else:
			print("ProcessFoundConceptTask: ⚠ Orchestrator not available for persistence")
	else:
		print("ProcessFoundConceptTask: ❌ AI generation failed after all retries: ", last_error)
		
		# Enhanced error reporting
		var error_details = {
			"final_error": last_error,
			"attempts": max_retries,
			"task_id": task.core_idea,
			"timestamp": Time.get_datetime_string_from_system()
		}
		
		# Add error details to task notes for debugging
		task.notes += "\n\n[AI GENERATION FAILED]: " + str(error_details)
		
		_complete_task_with_placeholder(task)
	
	# Mark as completed
	processing_state = "completed"
	task_completed = true

func _save_content_to_file(task: WorkplanTask):
	"""Save generated content to a file with quality analysis and optimization suggestions"""
	# Create output directory if it doesn't exist
	var output_dir = "readymade/output/"
	var dir_access = DirAccess.open("res://")
	if dir_access and not dir_access.dir_exists(output_dir):
		var error = dir_access.make_dir_recursive(output_dir)
		if error != OK:
			push_warning("ProcessFoundConceptTask: Failed to create output directory: " + str(error))
	
	# Create filename based on task title
	var safe_filename = task.title.replace(" ", "_").replace("\"", "").replace(":", "").replace("/", "_")
	safe_filename = safe_filename.substr(0, 50)  # Limit length
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var filename = "%s_%s.md" % [safe_filename, timestamp]
	var filepath = output_dir + filename
	
	# Parse multiple entries for better display
	var formats = _parse_multiple_entries(task.format)
	var channels = _parse_multiple_entries(task.channel)
	var instruments = _parse_multiple_entries(task.cosmic_instrument)
	
	# Perform content quality analysis
	var quality_analysis = _analyze_content_quality(task.generated_content, formats, channels)
	
	# Create content with metadata and quality analysis
	var content_with_metadata = """# %s

**Status:** %s  
**Format(s):** %s  
**Channel(s):** %s  
**Cosmic Instrument(s):** %s  
**Priority:** %d  
**Generated:** %s  
**Completion Date:** %s  

## Quality Analysis

### Content Metrics
%s

### Format Optimization
%s

### Channel Optimization
%s

### Improvement Suggestions
%s

## Notes
%s

## Generated Content

%s

---
*Generated by ReadyMade A1 Synthesis Engine*
""" % [
		task.title,
		task.status,
		", ".join(formats) if formats.size() > 0 else "Not specified",
		", ".join(channels) if channels.size() > 0 else "Not specified", 
		", ".join(instruments) if instruments.size() > 0 else "Not specified",
		task.priority,
		Time.get_datetime_string_from_system(),
		task.completion_date,
		_format_quality_metrics(quality_analysis.get("metrics", {})),
		_format_optimization_results(quality_analysis.get("format_analysis", {})),
		_format_optimization_results(quality_analysis.get("channel_analysis", {})),
		_format_suggestions(quality_analysis.get("suggestions", [])),
		task.notes if not task.notes.is_empty() else "No additional notes",
		task.generated_content
	]
	
	# Save to file
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_string(content_with_metadata)
		file.close()
		print("ProcessFoundConceptTask: 💾 Content saved to: ", filepath)
		
		# Update task with file path
		task.deliverable_path = filepath
	else:
		print("ProcessFoundConceptTask: ❌ Failed to save content to file")

func _build_content_prompt(task: WorkplanTask) -> String:
	"""Build a comprehensive prompt for content generation with mode-aware optimization"""
	
	# Parse multiple entries for better prompt formatting
	var formats = _parse_multiple_entries(task.format)
	var channels = _parse_multiple_entries(task.channel)
	var instruments = _parse_multiple_entries(task.cosmic_instrument)
	
	# Load format templates and channel optimization
	var format_templates = preload("res://readymade/scripts/content_templates/format_templates.gd")
	var channel_optimizer = preload("res://readymade/scripts/content_templates/channel_optimizer.gd")
	
	# Get mode-aware prompt prefix
	var mode_prefix = _get_mode_aware_prompt_prefix()
	
	# Build enhanced prompt with format-specific structure
	var enhanced_prompt = _build_format_optimized_prompt(task.core_idea, formats, channels, instruments, task.notes, format_templates, channel_optimizer)
	
	# Prepend mode-specific guidance
	if not mode_prefix.is_empty():
		enhanced_prompt = mode_prefix + "\n\n" + enhanced_prompt
		print("ProcessFoundConceptTask: ✓ Applied mode-aware prompting")
	
	return enhanced_prompt

func _readymade_store_context_pack() -> Dictionary:
	var client := HubSubstrateClientScript.new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.add_child(client)
	if client.has_method("configure_from_runtime_config"):
		client.configure_from_runtime_config()
	var packs_res: Dictionary = await client.stfx_store_list_context_packs()
	if is_instance_valid(client):
		client.queue_free()
	if not bool(packs_res.get("ok", false)):
		return {"ok": false, "error": packs_res.get("error", packs_res)}
	var packs_any: Variant = packs_res.get("context_packs", [])
	var packs: Array = packs_any if typeof(packs_any) == TYPE_ARRAY else []
	if packs.is_empty():
		return {"ok": false, "error": "No Store context packs available"}
	var pack_any: Variant = packs[packs.size() - 1]
	if typeof(pack_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid Store context pack"}
	var pack: Dictionary = pack_any
	var chunks_any: Variant = pack.get("chunks", [])
	var chunks: Array = chunks_any if typeof(chunks_any) == TYPE_ARRAY else []
	var lines: Array[String] = []
	for chunk_any in chunks:
		if typeof(chunk_any) != TYPE_DICTIONARY:
			continue
		var chunk: Dictionary = chunk_any
		lines.append("- %s\n%s" % [str(chunk.get("citation", "Store chunk")), str(chunk.get("text", ""))])
	return {
		"ok": true,
		"context_pack_id": str(pack.get("context_pack_id", "")).strip_edges(),
		"trace_id": str(pack.get("trace_id", "")).strip_edges(),
		"text": "\n\n".join(lines),
	}

func _commit_readymade_store_output(task: WorkplanTask) -> void:
	var client := HubSubstrateClientScript.new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.add_child(client)
	if client.has_method("configure_from_runtime_config"):
		client.configure_from_runtime_config()
	var inputs: Array = []
	if not _last_store_context_meta.is_empty():
		inputs.append({
			"type": "stfx_store.context_pack",
			"context_pack_id": str(_last_store_context_meta.get("context_pack_id", "")).strip_edges(),
		})
		inputs.append({
			"type": "stfx_store.retrieval_trace",
			"trace_id": str(_last_store_context_meta.get("trace_id", "")).strip_edges(),
		})
	var payload := {
		"title": task.title,
		"core_idea": task.core_idea,
		"generated_content": task.generated_content,
		"deliverable_path": task.deliverable_path,
		"context_meta": _last_store_context_meta.duplicate(true),
	}
	var provenance := {
		"produced_by": "readymade.process_found_concept",
		"inputs": inputs,
	}
	await client.stfx_store_commit_artifact("readymade.generated_output", payload, provenance)
	if is_instance_valid(client):
		client.queue_free()

func _get_mode_aware_prompt_prefix() -> String:
	"""Get mode-specific prompt prefix from ModeManager"""
	var mode_manager = blackboard.get_var("mode_manager") if blackboard else null
	if not mode_manager:
		print("ProcessFoundConceptTask: ⚠ ModeManager not available, using generic prompting")
		return ""
	var current_config = mode_manager.get_current_config()
	if not current_config:
		print("ProcessFoundConceptTask: ⚠ No mode configuration available")
		return ""
	var mode_prefix: String = str(current_config.ai_prompt_prefix)
	print("ProcessFoundConceptTask: 📋 Using mode: ", current_config.name, " with prompt prefix")
	return mode_prefix

func _get_metapunkt_assigned_agent_id(slot_id: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return ""
	var host := tree.root.get_node_or_null("MetapunktAppHost")
	if not host or not (host as Object).has_method("get_slot_assignments"):
		return ""
	var m_any: Variant = (host as Object).call("get_slot_assignments")
	if typeof(m_any) != TYPE_DICTIONARY:
		return ""
	var m: Dictionary = m_any
	return str(m.get(slot_id, "")).strip_edges()

func _find_metapunkt_endpoint() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	var n: Node = tree.root.find_child("MetapunktEndpointHandler", true, false)
	return n as Object

func _metapunkt_chat(agent_id: String, prompt: String, thread_name: String) -> Dictionary:
	var ep := _find_metapunkt_endpoint()
	if not ep or not ep.has_method("call_tool"):
		return {"success": false, "error": "MetapunktEndpointHandler not available (open Tools→Metapunkt or ensure Metapunkt is running)"}
	var args := {"operation": "chat", "message": prompt, "thread_name": thread_name}
	var AuthContextUtilsLocalScript = preload("res://addons/synesyn_core/scripts/auth_context_utils.gd")
	var user_id := AuthContextUtilsLocalScript.get_user_id("readymade", "a1")
	var scopes: Array = AuthContextUtilsLocalScript.get_scopes("readymade")
	var env_any: Variant = await ep.call("call_tool", agent_id, "SynTree", args, user_id, scopes)
	if typeof(env_any) != TYPE_DICTIONARY:
		return {"success": false, "error": "Metapunkt tool call returned invalid result"}
	var env: Dictionary = env_any
	if not bool(env.get("ok", false)):
		var err_obj: Variant = env.get("error_obj")
		if typeof(err_obj) == TYPE_DICTIONARY:
			return {"success": false, "error": str((err_obj as Dictionary).get("message", env.get("error", "Tool error")))}
		return {"success": false, "error": str(env.get("error", "Tool error"))}
	var res_any: Variant = env.get("result")
	if typeof(res_any) != TYPE_DICTIONARY:
		return {"success": false, "error": "SynTree tool returned invalid result payload"}
	var res: Dictionary = res_any
	if bool(res.get("success", false)):
		return {"success": true, "response": str(res.get("response", "")), "thread_name": str(res.get("thread_name", thread_name))}
	return {"success": false, "error": str(res.get("error", "SynTree tool chat failed"))}

func _build_format_optimized_prompt(core_idea: String, formats: Array[String], channels: Array[String], instruments: Array[String], notes: String, format_templates, channel_optimizer) -> String:
	"""Build format and channel optimized prompt"""
	
	var base_prompt = _apply_cosmic_instruments(core_idea, instruments, formats, channels, notes)
	
	# Add format-specific optimization
	if formats.size() > 0:
		var primary_format = formats[0]  # Use first format as primary
		var format_template = format_templates.get_template(primary_format)
		
		if not format_template.is_empty():
			base_prompt += "\n\n" + "FORMAT OPTIMIZATION FOR %s:" % primary_format.to_upper()
			base_prompt += "\n" + format_templates.get_format_prompt(primary_format)
			
			# Add structure guidance
			var structure = format_template.get("structure", [])
			if structure.size() > 0:
				base_prompt += "\n\nCONTENT STRUCTURE REQUIREMENTS:"
				for i in range(structure.size()):
					var section = structure[i]
					base_prompt += "\n%d. %s" % [i + 1, section.capitalize().replace("_", " ")]
	
	# Add channel-specific optimization
	if channels.size() > 0:
		var primary_channel = channels[0]  # Use first channel as primary
		var channel_config = channel_optimizer.channel_configs.get(primary_channel, {})
		
		if not channel_config.is_empty():
			base_prompt += "\n\n" + "CHANNEL OPTIMIZATION FOR %s:" % primary_channel.to_upper()
			
			# Add platform-specific guidelines
			var content_style = channel_config.get("content_style", "")
			var audience_behavior = channel_config.get("audience_behavior", "")
			
			if not content_style.is_empty():
				base_prompt += "\nContent Style: %s" % content_style.replace("_", " ").capitalize()
			if not audience_behavior.is_empty():
				base_prompt += "\nAudience Behavior: %s" % audience_behavior.replace("_", " ").capitalize()
			
			# Add content guidelines
			var guidelines = channel_config.get("content_guidelines", {})
			if not guidelines.is_empty():
				base_prompt += "\nPlatform Guidelines:"
				for key in guidelines.keys():
					var value = guidelines[key]
					base_prompt += "\n- %s: %s" % [key.capitalize().replace("_", " "), str(value)]
	
	# Add multi-format/multi-channel considerations
	if formats.size() > 1 or channels.size() > 1:
		base_prompt += "\n\nMULTI-PLATFORM ADAPTATION:"
		base_prompt += "\nCreate content that can be adapted across multiple formats and channels."
		base_prompt += "\nProvide specific variations or adaptation notes for each target platform."
		
		if formats.size() > 1:
			base_prompt += "\nFormats to consider: %s" % ", ".join(formats)
		if channels.size() > 1:
			base_prompt += "\nChannels to consider: %s" % ", ".join(channels)
	
	return base_prompt

func _apply_cosmic_instruments(core_idea: String, instruments: Array[String], formats: Array[String], channels: Array[String], notes: String) -> String:
	"""Apply Found Concepts methodology through Inference Architecture"""
	
	# Build the foundational metaprompt that establishes the AI as an Inference Architect
	var metaprompt = _build_inference_architect_metaprompt()
	
	# Create the content generation task within this framework
	var task_context = _build_task_context(core_idea, formats, channels, notes)
	
	# Apply cosmic instruments as navigation tools within the broader framework
	var enhanced_prompt = metaprompt + "\n\n" + task_context
	
	# Apply each cosmic instrument as sophisticated navigation technique
	for instrument in instruments:
		enhanced_prompt = _apply_cosmic_instrument_navigation(enhanced_prompt, instrument, core_idea, formats, channels)
	
	# If no cosmic instruments specified, use the foundational Inference Architecture approach
	if instruments.size() == 0:
		enhanced_prompt += "\n\nNow, as an Inference Architect, navigate the latent space to generate content that embodies the Found Concepts methodology - transforming existing knowledge into genuinely innovative material."
	
	return enhanced_prompt

func _build_inference_architect_metaprompt() -> String:
	"""Build the foundational metaprompt that establishes AI as Inference Architect"""
	
	# Completely different approach - focus on specific, concrete insights rather than abstract frameworks
	var concrete_angles = [
		"Start with a specific, counterintuitive observation that most people would disagree with.",
		"Begin with a concrete example that illuminates the deeper pattern.",
		"Find the most boring, mundane aspect of this topic and reveal why it's actually the most important.",
		"Identify what experts in this field are embarrassed to admit publicly.",
		"Locate the historical moment when everyone got this concept completely wrong."
	]
	
	var insight_catalysts = [
		"What would a 5-year-old notice about this that PhD experts miss?",
		"What would this look like if it happened in a completely different context?",
		"What assumption does everyone make that is probably false?",
		"What would the opposite of conventional wisdom reveal?",
		"What pattern from a totally unrelated field applies here?"
	]
	
	var selected_angle = concrete_angles[randi() % concrete_angles.size()]
	var selected_catalyst = insight_catalysts[randi() % insight_catalysts.size()]
	
	return """You are writing for intelligent people who are tired of generic AI content. They can spot formulaic responses immediately and will stop reading if you sound like every other AI.

CORE MANDATE: %s

INSIGHT CATALYST: %s

ANTI-SLOP REQUIREMENTS:
- NO meta-commentary about your own process
- NO "Reality Alpha/Beta/Gamma" structures
- NO abstract philosophizing without concrete examples
- NO predictable conclusions that readers can see coming
- NO buzzwords or jargon without earning them through specific insights

QUALITY STANDARDS:
- Every paragraph should contain at least one specific, surprising claim
- Use concrete examples, not abstract concepts
- Make connections that feel unexpected but inevitable in hindsight
- Write like you're having a conversation with someone smarter than you
- If it sounds like something an AI would write, rewrite it

Remember: Insight beats eloquence. Specificity beats profundity. Surprise beats sophistication.""" % [selected_angle, selected_catalyst]

func _build_task_context(core_idea: String, formats: Array[String], channels: Array[String], notes: String) -> String:
	"""Build the specific content generation context within the Inference Architecture framework"""
	
	return """CONTENT GENERATION MISSION:
You are tasked with performing conceptual archaeology on the following material, transforming it through Found Concepts methodology:

CORE CONCEPTUAL ARTIFACT: %s
TARGET FORMATS: %s  
DISTRIBUTION CHANNELS: %s
CONTEXTUAL NOTES: %s

ARCHAEOLOGICAL PROCESS:
1. **Cosmic Reconnaissance**: Map the conceptual topology surrounding this idea
2. **Semiotic Isolation**: Extract core semantic and logical components  
3. **Cross-Disciplinary Mining**: Identify related concepts across domain boundaries
4. **Stochastic Affordance Composition**: Generate novel functional possibilities through systematic combination
5. **Utopian Recontextualization**: Frame transformed concepts as vectors toward desired futures
6. **Recursive Validation**: Test emergent combinations through iterative refinement

METAMODERN SENSIBILITY:
Approach this task with serious commitment to creative transformation while maintaining playful awareness that all knowledge construction involves systematic appropriation. Your content should demonstrate genuine insight while acknowledging its constructed nature.""" % [
		core_idea,
		", ".join(formats) if formats.size() > 0 else "Unspecified - adapt as needed",
		", ".join(channels) if channels.size() > 0 else "Unspecified - consider multiple contexts",
		notes if not notes.is_empty() else "No additional context provided"
	]

func _apply_cosmic_instrument_navigation(prompt: String, instrument: String, core_idea: String, formats: Array[String], channels: Array[String]) -> String:
	"""Apply cosmic instruments as sophisticated navigation tools within Inference Architecture"""
	
	var instrument_lower = instrument.to_lower()
	
	if "role play" in instrument_lower or "dimensional shifter" in instrument_lower:
		return _apply_dimensional_shifter_navigation(prompt, core_idea, formats, channels)
	elif "hypothetical" in instrument_lower or "reality benders" in instrument_lower:
		return _apply_reality_bender_navigation(prompt, core_idea)
	elif "iterative" in instrument_lower or "gravitational drift" in instrument_lower:
		return _apply_gravitational_drift_navigation(prompt, core_idea)
	elif "abductive" in instrument_lower or "quantum reasoning" in instrument_lower:
		return _apply_quantum_reasoning_navigation(prompt, core_idea, formats, channels)
	
	return prompt

func _apply_dimensional_shifter_navigation(prompt: String, core_idea: String, _formats: Array[String], _channels: Array[String]) -> String:
	"""Apply Role Play - but simply"""
	
	var persona_types = [
		"a skeptical engineer who thinks most ideas are overcomplicated",
		"a curious teenager who asks uncomfortable questions",
		"someone who has to explain this to their grandmother",
		"a person who disagrees with this concept entirely",
		"someone who discovered this idea by accident"
	]
	
	var selected_persona = persona_types[randi() % persona_types.size()]
	
	return prompt + """

PERSPECTIVE: Write as %s talking about "%s".

Don't announce this perspective - just naturally write from their point of view. What would they notice that others miss? What would they care about that experts ignore?""" % [selected_persona, core_idea]

func _apply_reality_bender_navigation(prompt: String, core_idea: String) -> String:
	"""Apply Hypothetical Framings - but concretely"""
	
	var concrete_scenarios = [
		"What if this concept was discovered by accident in a completely different field?",
		"How would this work if it was invented by someone trying to solve the opposite problem?",
		"What if this was common knowledge 100 years ago but we forgot why it matters?",
		"How would this change if it only worked under very specific, weird conditions?",
		"What if this concept was illegal and people had to practice it in secret?"
	]
	
	var selected_scenario = concrete_scenarios[randi() % concrete_scenarios.size()]
	
	return prompt + """

PERSPECTIVE SHIFT: %s

Use this scenario to generate ONE specific, concrete insight about "%s" that wouldn't be obvious otherwise. Don't explain the scenario - just use it to find something interesting that most people miss.

Focus on the practical implications, not the philosophical ones.""" % [selected_scenario, core_idea]

func _apply_gravitational_drift_navigation(prompt: String, core_idea: String) -> String:
	"""Apply Iterative Refinement - build up gradually"""
	
	return prompt + """

APPROACH: Start simple and build complexity gradually.

Take "%s" and explain it in three layers:
1. What a smart 12-year-old would understand
2. What a college student would need to know  
3. What an expert would find interesting

Each layer should reveal something the previous layer missed. Don't announce the layers - just naturally progress from simple to sophisticated.""" % [core_idea]

func _apply_quantum_reasoning_navigation(prompt: String, core_idea: String, _formats: Array[String], channels: Array[String]) -> String:
	"""Apply Abductive Reasoning - make educated guesses"""
	
	return prompt + """

REASONING CHALLENGE: You don't have complete information about your audience for "%s" on %s.

Make your best guess about what they actually care about (not what they say they care about), then write content that addresses their real concerns.

What are they probably worried about that they won't admit? What obvious question are they too embarrassed to ask?""" % [
		core_idea,
		", ".join(channels) if channels.size() > 0 else "social media"
	]

func _determine_inference_architect_persona(core_idea: String, formats: Array[String], _channels: Array[String]) -> Dictionary:
	"""Determine appropriate Inference Architect persona based on content and context"""
	
	var persona = {"role": "Conceptual Archaeologist", "description": ""}
	var idea_lower = core_idea.to_lower()
	var format_string = ", ".join(formats).to_lower()
	
	# Determine primary domain expertise
	if "inference" in idea_lower or "ai" in idea_lower or "intelligence" in idea_lower:
		persona["role"] = "AI Philosopher-Practitioner"
		persona["description"] = "A scholar-practitioner who bridges artificial intelligence research with philosophical inquiry, specializing in the archaeology of intelligence concepts across human and machine domains. You navigate the latent space where cognitive science, computer science, and philosophy intersect."
	elif "quantum" in idea_lower or "physics" in idea_lower or "space" in idea_lower:
		persona["role"] = "Quantum Semiotician"  
		persona["description"] = "A theoretical physicist turned meaning-archaeologist who excavates conceptual artifacts from the intersection of quantum mechanics and information theory. You understand how uncertainty principles apply to knowledge construction itself."
	elif "art" in idea_lower or "creative" in idea_lower or "aesthetic" in idea_lower:
		persona["role"] = "Metamodern Art Theorist"
		persona["description"] = "An art historian and critical theorist specializing in the archaeology of creative appropriation from Duchamp to contemporary practice. You understand how artistic methods inform knowledge production across disciplines."
	elif "social" in idea_lower or "community" in idea_lower or "society" in idea_lower:
		persona["role"] = "Utopian Systems Architect"
		persona["description"] = "A social theorist who designs reasoning cascades for imagining alternative futures. You specialize in the archaeology of social possibility, excavating concepts that enable collective transformation."
	
	# Refine based on format requirements
	if "video" in format_string:
		persona["description"] += " Your expertise extends to visual storytelling and multimodal meaning construction."
	elif "article" in format_string or "text" in format_string:
		persona["description"] += " You excel at dense conceptual archaeology through written exploration."
	elif "carousel" in format_string or "image" in format_string:
		persona["description"] += " You understand how concepts migrate across visual and textual semiotic modes."
	
	return persona

func _parse_multiple_entries(text: String) -> Array[String]:
	"""Parse multiple entries from text (comma-separated or line-separated)"""
	var entries: Array[String] = []
	
	if text.is_empty():
		return entries
	
	# First try splitting by commas
	var comma_parts = text.split(",")
	for part in comma_parts:
		var trimmed = part.strip_edges()
		if not trimmed.is_empty():
			entries.append(trimmed)
	
	return entries

func _complete_task_with_placeholder(task: WorkplanTask) -> void:
	"""Complete task with placeholder content when AI is unavailable"""
	# Parse multiple entries for better display
	var formats = _parse_multiple_entries(task.format)
	var channels = _parse_multiple_entries(task.channel)
	var instruments = _parse_multiple_entries(task.cosmic_instrument)
	
	task.generated_content = """[PLACEHOLDER CONTENT - AI Generation Failed]

Core Idea: %s
Format(s): %s
Channel(s): %s
Cosmic Instrument(s): %s

This content would be generated by AI based on the task specifications. 
The actual implementation would create engaging, platform-specific content 
ready for publication or further refinement.

For multiple formats/channels, the AI would create variations or adaptations 
appropriate for each specified format and platform.

Generated on: %s""" % [
		task.core_idea,
		", ".join(formats) if formats.size() > 0 else "Not specified",
		", ".join(channels) if channels.size() > 0 else "Not specified",
		", ".join(instruments) if instruments.size() > 0 else "Not specified",
		Time.get_datetime_string_from_system()
	]
	
	task.complete_task()
	_save_content_to_file(task)
	
	# Trigger persistence
	var orchestrator = blackboard.get_var("orchestrator")
	if orchestrator:
		orchestrator.update_task(task)
	
	processing_state = "completed"
	task_completed = true
	print("ProcessFoundConceptTask: ⚠ Task completed with placeholder content")

func _analyze_content_quality(content: String, formats: Array[String], channels: Array[String]) -> Dictionary:
	"""Analyze content quality and provide optimization recommendations"""
	var analysis = {
		"metrics": {},
		"format_analysis": {},
		"channel_analysis": {},
		"suggestions": [],
		"overall_score": 0.0
	}
	
	# Basic content metrics
	var word_count = content.split(" ").size()
	var char_count = content.length()
	var sentence_count = content.split(".").size()
	var paragraph_count = content.split("\n\n").size()
	
	analysis.metrics = {
		"word_count": word_count,
		"character_count": char_count,
		"sentence_count": sentence_count,
		"paragraph_count": paragraph_count,
		"avg_sentence_length": word_count / max(1, sentence_count),
		"readability_estimate": _estimate_readability(content)
	}
	
	# Format-specific analysis
	if formats.size() > 0:
		var format_templates = preload("res://readymade/scripts/content_templates/format_templates.gd")
		for format in formats:
			var format_analysis = format_templates.apply_format_optimization(content, format)
			analysis.format_analysis[format] = format_analysis
			analysis.suggestions.append_array(format_analysis.get("suggestions", []))
	
	# Channel-specific analysis  
	if channels.size() > 0:
		var channel_optimizer = preload("res://readymade/scripts/content_templates/channel_optimizer.gd")
		for channel in channels:
			var channel_analysis = channel_optimizer.optimize_for_channel(content, channel)
			analysis.channel_analysis[channel] = channel_analysis
			analysis.suggestions.append_array(channel_analysis.get("recommendations", []))
	
	# Calculate overall quality score
	analysis.overall_score = _calculate_quality_score(analysis)
	
	return analysis

func _estimate_readability(content: String) -> String:
	"""Estimate content readability level"""
	var words = content.split(" ")
	var sentences = content.split(".")
	var avg_sentence_length = words.size() / max(1, sentences.size())
	
	# Simple readability estimation based on sentence length
	if avg_sentence_length < 10:
		return "Very Easy (5th grade)"
	elif avg_sentence_length < 15:
		return "Easy (6th-7th grade)"
	elif avg_sentence_length < 20:
		return "Moderate (8th-9th grade)"
	elif avg_sentence_length < 25:
		return "Difficult (10th-12th grade)"
	else:
		return "Very Difficult (College+)"

func _calculate_quality_score(analysis: Dictionary) -> float:
	"""Calculate overall content quality score (0-100)"""
	var score = 50.0  # Base score
	var metrics = analysis.get("metrics", {})
	
	# Word count scoring
	var word_count = metrics.get("word_count", 0)
	if word_count >= 300 and word_count <= 2000:
		score += 15.0  # Good length
	elif word_count < 100:
		score -= 20.0  # Too short
	elif word_count > 3000:
		score -= 10.0  # Potentially too long
	
	# Readability scoring
	var readability = metrics.get("readability_estimate", "")
	if "Easy" in readability or "Moderate" in readability:
		score += 10.0
	
	# Sentence structure scoring
	var avg_sentence_length = metrics.get("avg_sentence_length", 0)
	if avg_sentence_length >= 10 and avg_sentence_length <= 20:
		score += 10.0
	
	# Format optimization scoring
	var format_analysis = analysis.get("format_analysis", {})
	if format_analysis.size() > 0:
		score += 10.0  # Bonus for format-specific optimization
	
	# Channel optimization scoring
	var channel_analysis = analysis.get("channel_analysis", {})
	if channel_analysis.size() > 0:
		score += 10.0  # Bonus for channel-specific optimization
	
	# Penalty for too many suggestions (indicates issues)
	var suggestions = analysis.get("suggestions", [])
	if suggestions.size() > 5:
		score -= suggestions.size() * 2.0
	
	return max(0.0, min(100.0, score))

func _format_quality_metrics(metrics: Dictionary) -> String:
	"""Format quality metrics for display"""
	var formatted = ""
	for key in metrics.keys():
		var value = metrics[key]
		var display_key = key.capitalize().replace("_", " ")
		formatted += "- %s: %s\n" % [display_key, str(value)]
	return formatted

func _format_optimization_results(analysis: Dictionary) -> String:
	"""Format optimization analysis results for display"""
	var formatted = ""
	for platform in analysis.keys():
		var platform_analysis = analysis[platform]
		formatted += "**%s:**\n" % platform
		
		var metrics = platform_analysis.get("metrics", {})
		for key in metrics.keys():
			var value = metrics[key]
			formatted += "- %s: %s\n" % [key.capitalize().replace("_", " "), str(value)]
		
		var additions = platform_analysis.get("channel_specific_additions", {})
		if additions.size() > 0:
			formatted += "Platform-specific recommendations:\n"
			for key in additions.keys():
				var value = additions[key]
				formatted += "- %s: %s\n" % [key.capitalize().replace("_", " "), str(value)]
		
		formatted += "\n"
	
	return formatted

func _format_suggestions(suggestions: Array) -> String:
	"""Format improvement suggestions for display"""
	var formatted = ""
	var unique_suggestions = []
	
	# Remove duplicates
	for suggestion in suggestions:
		if suggestion not in unique_suggestions:
			unique_suggestions.append(suggestion)
	
	for i in range(unique_suggestions.size()):
		formatted += "%d. %s\n" % [i + 1, unique_suggestions[i]]
	
	if unique_suggestions.size() == 0:
		formatted = "No specific improvement suggestions - content meets optimization standards.\n"
	
	return formatted

func _generate_name() -> String:
	return "Process Found Concept" 
