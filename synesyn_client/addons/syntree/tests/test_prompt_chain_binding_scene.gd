extends SceneTree

const SynTreePanelScene = preload("res://addons/syntree/scenes/syntree_panel.tscn")


func _init() -> void:
	var panel: Control = SynTreePanelScene.instantiate()
	var prompt_chain_panel: Control = panel.get_node(
		"MarginContainer/ScrollContainer/Main_VBoxContainer/"
		+ "ConversationTabs/Prompt Chains/PromptChainsScroll/"
		+ "PromptChainPanel"
	)
	var binding_panel: Control = prompt_chain_panel.get_node(
		"PromptChainBindingPanel"
	)
	var is_valid: bool = is_instance_valid(binding_panel)
	panel.free()
	if is_valid:
		print("Prompt chain binding scene tests: all passed")
		quit(0)
		return
	push_error("Prompt Chain binding panel is missing from the static scene")
	quit(1)
