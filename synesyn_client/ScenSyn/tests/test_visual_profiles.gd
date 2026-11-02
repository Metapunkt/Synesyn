extends SceneTree

const ResolverScript = preload(
	"res://addons/synesyn_visual_profiles/runtime/visual_profile_resolver.gd"
)
const BridgeScript = preload(
	"res://addons/synesyn_visual_profiles/runtime/visual_profile_bridge.gd"
)
const DiagnosticsScript = preload(
	"res://addons/synesyn_visual_profiles/diagnostics/visual_profile_diagnostics.gd"
)

var _failures: Array[String] = []


func _init() -> void:
	var synesyn_profile: SynesynVisualProfileDefinition = load(
		"res://ScenSyn/themes/profiles/synesyn_compatibility.tres"
	)
	var readymade_profile: SynesynVisualProfileDefinition = load(
		"res://readymade/ui/readymade_compatibility.tres"
	)
	_expect(synesyn_profile != null, "Synesyn compatibility profile did not load")
	_expect(readymade_profile != null, "ReadyMade compatibility profile did not load")
	var resolver: SynesynVisualProfileResolver = ResolverScript.new()
	_expect_ok(resolver.register_profile(synesyn_profile), "Synesyn profile was rejected")
	_expect_ok(resolver.register_profile(readymade_profile), "ReadyMade profile was rejected")
	_expect(
		resolver.set_default_profile("synesyn_compatibility"),
		"Default profile could not be selected"
	)
	var resolved_synesyn: SynesynVisualProfileDefinition = resolver.resolve_profile(
		"",
		"synesyn",
		PackedStringArray(["reduced_motion", "projector"])
	)
	_expect(
		resolved_synesyn == synesyn_profile,
		"Resolver did not select Synesyn by family and capability"
	)
	var resolved_readymade: SynesynVisualProfileDefinition = resolver.resolve_profile(
		"readymade_compatibility"
	)
	_expect(
		resolved_readymade == readymade_profile,
		"Resolver did not select ReadyMade by profile ID"
	)
	_expect(
		resolver.resolve_control_theme(synesyn_profile, "utility", "light")
		== synesyn_profile.utility_light,
		"Utility light theme did not resolve"
	)
	_expect(
		resolver.resolve_control_theme(synesyn_profile, "unknown", "projector")
		== synesyn_profile.base_dark,
		"Unknown/projector theme did not use dark base fallback"
	)
	_expect(
		resolver.resolve_semantic_color(synesyn_profile, "committed", "dark")
		== Color(0.357, 0.788, 0.549, 1),
		"Committed semantic color did not resolve"
	)
	_expect(
		resolver.resolve_semantic_color(readymade_profile, "danger", "dark")
		!= Color.MAGENTA,
		"Missing compatibility color did not use safe fallback"
	)
	_expect(
		resolver.resolve_metric(synesyn_profile, "spacing", "section") == 16.0,
		"Semantic spacing metric did not resolve"
	)
	_expect(
		resolver.activate_profile("synesyn_compatibility", "projector"),
		"Projector profile activation failed"
	)
	_expect(
		resolver.get_active_profile_mode() == "projector",
		"Supported projector profile mode was not retained"
	)
	_test_bridge_propagation(synesyn_profile)
	_test_diagnostics_and_gallery(synesyn_profile, readymade_profile)
	_finish()


func _test_bridge_propagation(
	synesyn_profile: SynesynVisualProfileDefinition
) -> void:
	var bridge: SynesynVisualProfileBridge = BridgeScript.new()
	_expect_ok(
		bridge.initialize([synesyn_profile], "synesyn_compatibility"),
		"Compatibility bridge failed to initialize"
	)
	var root_node: Control = Control.new()
	var canvas_layer_node: CanvasLayer = CanvasLayer.new()
	var canvas_root_node: Control = Control.new()
	var subviewport_node: SubViewport = SubViewport.new()
	var subviewport_root_node: Control = Control.new()
	root_node.add_child(canvas_layer_node)
	canvas_layer_node.add_child(canvas_root_node)
	root_node.add_child(subviewport_node)
	subviewport_node.add_child(subviewport_root_node)
	_expect(
		bridge.apply_to_root(root_node, "utility", "light"),
		"Compatibility bridge did not apply a profile"
	)
	_expect(root_node.theme == synesyn_profile.utility_light, "Root theme was not applied")
	_expect(
		canvas_root_node.theme == synesyn_profile.utility_light,
		"CanvasLayer root did not receive explicit profile propagation"
	)
	_expect(
		subviewport_root_node.theme == synesyn_profile.utility_light,
		"SubViewport root did not receive explicit profile propagation"
	)
	_expect(
		synesyn_profile.utility_light.get_type_variation_base(
			&"SynesynPrimaryAction"
		) == &"Button",
		"Primary action theme variation was not registered"
	)
	_expect(
		synesyn_profile.utility_light.get_type_variation_base(
			&"LabelMuted"
		) == &"Label",
		"Muted label theme variation was not registered"
	)
	_expect(
		int(synesyn_profile.radius_roles.get("control", 0)) == 10,
		"Compatibility profile control radius should match Base theme (10)"
	)
	root_node.free()


func _test_diagnostics_and_gallery(
	synesyn_profile: SynesynVisualProfileDefinition,
	readymade_profile: SynesynVisualProfileDefinition
) -> void:
	_expect(
		bool(DiagnosticsScript.inspect_profile(synesyn_profile).get("ok", false)),
		"Synesyn compatibility profile has unresolved semantic roles"
	)
	_expect(
		not bool(DiagnosticsScript.inspect_profile(readymade_profile).get("ok", true)),
		"ReadyMade compatibility profile should report unresolved roles before migration"
	)
	var bridge: SynesynVisualProfileBridge = BridgeScript.new()
	_expect_ok(
		bridge.initialize(
			[synesyn_profile, readymade_profile],
			"synesyn_compatibility"
		),
		"Diagnostics bridge failed to initialize"
	)
	var root_node: Control = Control.new()
	var canvas_layer_node: CanvasLayer = CanvasLayer.new()
	var isolated_root_node: Control = Control.new()
	root_node.add_child(canvas_layer_node)
	canvas_layer_node.add_child(isolated_root_node)
	_expect(
		not bool(DiagnosticsScript.inspect_tree(root_node).get("ok", true)),
		"Unregistered CanvasLayer root was not diagnosed"
	)
	bridge.apply_to_root(root_node, "base", "dark")
	_expect(
		bool(DiagnosticsScript.inspect_tree(root_node).get("ok", false)),
		"Profile propagation did not resolve isolated-root diagnostic"
	)
	root_node.free()
	var gallery_scene: PackedScene = load(
		"res://addons/synesyn_visual_profiles/gallery/scenes/visual_profile_gallery.tscn"
	)
	_expect(gallery_scene != null, "Visual profile gallery scene did not load")
	if gallery_scene != null:
		var gallery_node: Node = gallery_scene.instantiate()
		_expect(
			gallery_node.get_node_or_null(
				"PageMargin/MainVBox/SurfaceSection/SectionMargin/SectionVBox/SemanticGrid"
			) != null,
			"Visual profile gallery is missing its semantic grid"
		)
		var primary_action_node: Button = gallery_node.get_node(
			"PageMargin/MainVBox/SurfaceSection/SectionMargin/SectionVBox/ActionRow/PrimaryAction"
		)
		_expect(
			primary_action_node.theme_type_variation == &"SynesynPrimaryAction",
			"Gallery primary action does not use the shared semantic component"
		)
		var committed_badge_node: PanelContainer = gallery_node.get_node(
			"PageMargin/MainVBox/SurfaceSection/SectionMargin/SectionVBox/BadgeRow/CommittedBadge"
		)
		_expect(
			committed_badge_node.theme_type_variation == &"SynesynBadgeCommitted",
			"Gallery committed badge does not use the shared semantic component"
		)
		var selected_navigation_node: Button = gallery_node.get_node(
			"PageMargin/MainVBox/SurfaceSection/SectionMargin/SectionVBox/NavigationRow/OverviewNavigation"
		)
		_expect(
			selected_navigation_node.theme_type_variation == &"SynesynNavigationSelected",
			"Gallery selected navigation does not expose its state"
		)
		var field_node: LineEdit = gallery_node.get_node(
			"PageMargin/MainVBox/SurfaceSection/SectionMargin/SectionVBox/FieldAndPanelRow/SemanticField"
		)
		_expect(
			field_node.theme_type_variation == &"SynesynField",
			"Gallery field does not use the shared semantic variation"
		)
		gallery_node.free()
	for component_path in [
		"res://addons/synesyn_visual_profiles/components/scenes/semantic_dialog.tscn",
		"res://addons/synesyn_visual_profiles/components/scenes/semantic_drawer.tscn",
		"res://addons/synesyn_visual_profiles/components/scenes/semantic_status_strip.tscn",
		"res://addons/synesyn_visual_profiles/components/scenes/orientation_indicator.tscn",
		"res://addons/synesyn_visual_profiles/components/scenes/attention_loading_indicator.tscn",
		"res://addons/synesyn_visual_profiles/components/scenes/keyboard_hint.tscn",
	]:
		_expect(load(component_path) is PackedScene, "Component did not load: %s" % component_path)


func _expect_ok(result: Dictionary, failure_message: String) -> void:
	_expect(
		bool(result.get("ok", false)),
		"%s: %s" % [failure_message, result.get("errors", [])]
	)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
		push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Visual profile tests: all passed")
		quit(0)
		return
	for failure_message: String in _failures:
		print("FAIL: " + failure_message)
	push_error("Visual profile tests: %d failure(s)" % _failures.size())
	quit(1)
