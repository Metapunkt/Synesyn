extends RefCounted
class_name WorkshopMapLayoutUtils

## Thinking Map column sizing for Workshop responsive layout.
## Columns stay side-by-side; they shrink instead of stacking vertically.

const SynesynUiTokensScript = preload(
	"res://ScenSyn/scripts/core/synesyn_ui_tokens.gd"
)

const COLUMN_MIN_WIDTH := 120.0

## A zero vertical minimum let the columns collapse to a strip of headings as soon as a taller
## sibling claimed the space, which is what opening the Closure audit did: the map's own cards
## were left with no height and no way to scroll back to them. So the columns keep a floor.
##
## Lowered from 132 once the Custom drawer gained a switch that hides the claims pane outright.
## The floor exists to stop the columns collapsing by accident; hiding them on purpose is now a
## separate control, so the floor only has to stay above "heading and nothing else" and can let
## the split divider travel much further than it used to.
const COLUMN_MIN_HEIGHT := 96.0

const _MAP_COLUMN_FILL_LIGHT := Color(0.93, 0.952, 0.98, 1)
const _MAP_COLUMN_FILL_DARK := Color(0.12, 0.17, 0.24, 1)

## Resolved under the `%MapColumns` unique name rather than by a path from the panel root, so
## re-parenting the grid — as introducing the body/lower split did — cannot silently detach the
## theme override. A path from the root would have returned null and simply skipped the
## restyle, which is invisible until someone notices the columns stopped following the theme.
const _MAP_COLUMN_NAMES: Array[String] = [
	"CausesColumn",
	"EffectsColumn",
	"OpportunitiesColumn",
	"OutcomesColumn",
]


## Repaints the four claim columns for the active light/dark mode. Lives here rather than in the
## map controller because it is styling keyed to the same nodes this file already sizes, and the
## controller had no other reason to know the column names.
static func apply_column_styles(map_root_node: Control, is_dark_mode: bool) -> void:
	if not is_instance_valid(map_root_node):
		return
	var columns_node: Node = map_root_node.get_node_or_null("%MapColumns")
	if columns_node == null:
		return
	var column_style := StyleBoxFlat.new()
	column_style.content_margin_left = 10.0
	column_style.content_margin_top = 8.0
	column_style.content_margin_right = 10.0
	column_style.content_margin_bottom = 8.0
	column_style.bg_color = (
		_MAP_COLUMN_FILL_DARK if is_dark_mode else _MAP_COLUMN_FILL_LIGHT
	)
	column_style.corner_radius_top_left = 12
	column_style.corner_radius_top_right = 12
	column_style.corner_radius_bottom_right = 12
	column_style.corner_radius_bottom_left = 12
	for column_name: String in _MAP_COLUMN_NAMES:
		var column_node: PanelContainer = (
			columns_node.get_node_or_null(column_name) as PanelContainer
		)
		if column_node:
			column_node.add_theme_stylebox_override("panel", column_style)


## Gives the audit a share of the split's height while it is open, and hands it back when it
## closes.
##
## The lower pane holds the footer and the audit host. It must not expand while the audit is
## shut, or the footer would float in the middle of the panel; it must expand while the audit
## is open, or the host would sit at its minimum and the panel would look like the toggle did
## nothing. Switching the flag is what makes both true, and it leaves the divider draggable in
## both directions afterwards — down to nothing, since the host itself has no vertical
## minimum, which is the point.
##
## The stored offset is cleared on close so a drag made during one audit does not decide the
## layout of the next.
static func apply_audit_split(shell_root_node: Control, is_audit_active: bool) -> void:
	if not is_instance_valid(shell_root_node):
		return
	var split_node: VSplitContainer = (
		shell_root_node.get_node_or_null("%MapBodySplit") as VSplitContainer
	)
	var lower_pane_node: Control = (
		shell_root_node.get_node_or_null("%MapLowerPane") as Control
	)
	if split_node == null or lower_pane_node == null:
		return
	lower_pane_node.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL if is_audit_active else Control.SIZE_FILL
	)
	if not is_audit_active:
		split_node.split_offset = 0


static func apply_responsive_map_columns(
	shell_root_node: Control,
	_viewport_width: float,
	_left_rail_node: Control,
	_right_rail_node: Control,
	_center_workspace_node: Control
) -> void:
	if not is_instance_valid(shell_root_node):
		return
	var map_grid_node: GridContainer = (
		shell_root_node.find_child("MapColumns", true, false) as GridContainer
	)
	if map_grid_node == null:
		return
	map_grid_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_grid_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# One row, always, per this file's contract. The count follows the actual columns rather
	# than a constant: a hardcoded 3 wrapped the Outcomes column onto a second row the moment
	# it was added, because the scene said four and this said three, and the runtime value
	# wins. Deriving it means the next column cannot reintroduce the same bug.
	map_grid_node.columns = maxi(1, _column_count(map_grid_node))
	# Share width across the columns; the split pane distributes height above this floor.
	var column_min_size := Vector2(COLUMN_MIN_WIDTH, COLUMN_MIN_HEIGHT)
	for column_node: Node in map_grid_node.get_children():
		var column_control: Control = column_node as Control
		if column_control == null:
			continue
		column_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column_control.custom_minimum_size = column_min_size


## Control children only, so a non-visual helper node parented to the grid could never be
## counted as a column.
static func _column_count(map_grid_node: GridContainer) -> int:
	var total: int = 0
	for column_node: Node in map_grid_node.get_children():
		if column_node is Control:
			total += 1
	return total


static func request_header_banner_refit(from_node: Node) -> void:
	var ancestor_node: Node = from_node
	while ancestor_node:
		if ancestor_node.has_method("_fit_header_banner"):
			ancestor_node.call_deferred("_fit_header_banner")
			return
		ancestor_node = ancestor_node.get_parent()
