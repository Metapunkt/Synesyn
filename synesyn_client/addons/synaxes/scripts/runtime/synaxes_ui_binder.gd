extends RefCounted
## Resolves SynAxes main-scene UI nodes once via find_child.
##
## Shared by the editor plugin path and the runtime controller so both avoid
## duplicating long find_child blocks for the same controls.

## Scene node names resolved on every call to resolve().
const COMMON_NODE_NAMES: Array[String] = [
	# Core analysis controls (shared by plugin + runtime)
	"ImportButton",
	"DiscoverButton",
	"ReloadLastAnalysisButton",
	"ClearButton",
	"RefreshButton",
	"SourceList",
	"PatternViewer",
	"DimReductionMethod",
	"DiscoveryMethod",
	"ClustersSlider",
	"ClustersValue",
	# Camera / viewer controls (shared)
	"ResetViewButton",
	"FocusSelectionButton",
	"RotateLeft",
	"RotateRight",
	"RotateUp",
	"RotateDown",
	"ZoomIn",
	"ZoomOut",
	# Runtime status / embedding controls also present in the main scene
	"DebugInfo",
	"PersistentStatusLabel",
	"StepSpineLabel",
	"AdvancedToggle",
	"AdvancedPanel",
	"UseHubJobs",
	"UseHubEmbeddings",
	"EmbeddingTierLabel",
	"CacheStatsLabel",
	"BottomTabs",
	"WorkOnThisButton",
	# Phase B default-path controls
	"ImportLatestContextGraphButton",
	"ThemesStatusLabel",
	"UseModelThemesButton",
	"ModelThemesConsentDialog",
	"PostCommitActions",
	"CommitAnotherButton",
	"OpenSynPunktClosuresButton",
]


static func resolve(root: Node) -> Dictionary:
	## Find each common control under root once. Missing nodes map to null.
	var refs: Dictionary = {}
	if root == null:
		return refs
	for node_key in COMMON_NODE_NAMES:
		refs[node_key] = root.find_child(node_key, true, false)
	return refs


static func resolve_named(root: Node, node_names: Array) -> Dictionary:
	## Resolve an explicit list of node names (in addition to / instead of COMMON).
	var refs: Dictionary = {}
	if root == null:
		return refs
	for name_any in node_names:
		var node_key: String = str(name_any)
		if node_key.is_empty():
			continue
		refs[node_key] = root.find_child(node_key, true, false)
	return refs
