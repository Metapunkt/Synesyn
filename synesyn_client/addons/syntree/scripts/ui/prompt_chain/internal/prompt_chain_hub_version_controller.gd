## Purpose: Commit immutable Prompt Chain versions and binding provenance.
extends RefCounted

const PromptChainStoreScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_store.gd"
)
const PromptChainArtifactPayloadBuilderScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_artifact_payload_builder.gd"
)

var _payload_builder: RefCounted = (
	PromptChainArtifactPayloadBuilderScript.new()
)


func save_version(panel: Object) -> void:
	var thread_settings: Dictionary = panel.call("_ensure_thread_defaults")
	var mode_id: String = str(
		thread_settings.get("mode", "asset")
	).to_lower()
	if mode_id != "asset":
		push_warning("PromptChainPanel: Switch to Asset mode before Hub save.")
		return
	if bool(panel.call("_has_pending_proposal", thread_settings)):
		push_warning("PromptChainPanel: Commit proposed changes before Hub save.")
		return
	var chain_id: String = str(panel.call("_get_selected_chain_id"))
	if chain_id.is_empty():
		push_warning("PromptChainPanel: Select a chain to save.")
		return
	var scope_id: String = str(panel.get("_scope"))
	var chain: Dictionary = PromptChainStoreScript.get_chain(
		scope_id,
		chain_id
	)
	if chain.is_empty():
		push_warning("PromptChainPanel: Selected chain is empty.")
		return
	var binding: Dictionary = chain.get("context_binding", {})
	if (
		not binding.is_empty()
		and panel.get_meta("last_prompt_binding_preview", {}) != binding
	):
		push_warning(
			"PromptChainPanel: Preview the exact context binding before saving."
		)
		return
	var hub_client: Object = panel.get("_hub")
	if not is_instance_valid(hub_client):
		push_warning("PromptChainPanel: Hub client not available.")
		return
	if hub_client.has_method("check_health"):
		var health: Dictionary = await hub_client.call("check_health")
		if not bool(health.get("ok", false)):
			push_warning("PromptChainPanel: Hub not reachable.")
			return
	var info: Dictionary = PromptChainStoreScript.get_chain_hub_info(
		scope_id,
		chain_id
	)
	var previous_id: String = str(
		info.get("latest_artifact_id", "")
	).strip_edges()
	var payload: Dictionary = _payload_builder.call(
		"build",
		chain,
		chain_id,
		scope_id,
		previous_id,
		float(Time.get_unix_time_from_system())
	)
	var result: Dictionary = await hub_client.call(
		"create_artifact_inline_json",
		"ui.prompt_chain",
		payload.get("inline_json", {}),
		payload.get("metadata", {})
	)
	var artifact_id: String = str(
		result.get("id", result.get("artifact_id", ""))
	).strip_edges()
	if artifact_id.is_empty():
		push_warning(
			"PromptChainPanel: Unexpected Hub response: %s" % str(result)
		)
		return
	PromptChainStoreScript.record_chain_hub_version(
		scope_id,
		chain_id,
		artifact_id
	)
	panel.call("_refresh_hub_info")
