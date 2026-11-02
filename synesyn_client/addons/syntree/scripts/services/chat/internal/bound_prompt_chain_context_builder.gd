## Purpose: Compile one explicitly bound Prompt Chain context without globals.
extends RefCounted

const PromptChainContextResolverScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_context_resolver.gd"
)
const ContextCompilerBridgeScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/conversation_context_compiler_bridge.gd"
)

var _resolver: RefCounted = PromptChainContextResolverScript.new()
var _compiler_bridge: RefCounted = ContextCompilerBridgeScript.new()


func resolve(
	manager: Object,
	chain: Dictionary,
	slot_values: Dictionary,
	prefix_text: String = ""
) -> Dictionary:
	var binding: Dictionary = chain.get("context_binding", {})
	if binding.is_empty():
		return {"handled": false, "text": prefix_text}
	var hub_client: Object = manager.get("_hub")
	if not bool(_resolver.call("setup", hub_client)):
		manager.set_meta("last_prompt_binding_warning", "hub_client_unavailable")
		return {"handled": true, "text": prefix_text}
	var resolved: Dictionary = await _resolver.call(
		"resolve",
		chain,
		str(binding.get("owner_source_id", "")),
		{
			"thread_scope": str(manager.get("thread_scope")),
			"app_scope": "syntree_editor",
			"prompt_chain_id": str(chain.get("id", "")),
			"slots": slot_values,
		}
	)
	if not bool(resolved.get("ok", false)):
		manager.set_meta(
			"last_prompt_binding_warning",
			resolved.duplicate(true)
		)
		push_warning(
			"Prompt Chain context binding was not injected: %s"
			% str(resolved.get("error", "resolution_failed"))
		)
		return {"handled": true, "text": prefix_text}
	var compile_result: Dictionary = resolved.get("compile_result", {})
	manager.set_meta("last_context_compile_result", compile_result)
	manager.remove_meta("last_prompt_binding_warning")
	var compiled_context: String = _compiler_bridge.call(
		"wrap_for_chat",
		compile_result
	)
	var combined_text: String = compiled_context
	if not prefix_text.is_empty() and not compiled_context.is_empty():
		combined_text = prefix_text + "\n\n" + compiled_context
	elif not prefix_text.is_empty():
		combined_text = prefix_text
	return {"handled": true, "text": combined_text}
