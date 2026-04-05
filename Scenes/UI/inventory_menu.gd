## Inventory menu with retro open/close frame transition.
extends Control

signal weapon_assign_requested(slot_name: StringName, weapon_id: StringName, icon: Texture2D)

# ==============================================================================
# Exports
# ==============================================================================

@export var frame_1: Texture2D
@export var frame_2: Texture2D
@export var frame_3: Texture2D
@export var frame_step_seconds: float = 0.05
@export var sword_icon: Texture2D
@export var selector_offset: Vector2 = Vector2(0, 0)


# ==============================================================================
# Onready
# ==============================================================================

@onready var _frame_texture: TextureRect = $InventoryMenu/FrameTexture
@onready var _weapons_grid: GridContainer = $InventoryMenu/FrameTexture/WeaponsGrid
@onready var _weapon_select: TextureRect = $InventoryMenu/FrameTexture/WeaponSelect


# ==============================================================================
# Member variables
# ==============================================================================

var _is_open: bool = false
var _is_busy: bool = false
var _player_ref: Node = null
var _selected_index: int = -1
var _slot_weapon_ids: Array[StringName] = []

const TOTAL_WEAPON_SLOTS: int = 8
const SLOT_ICON_SIZE: Vector2 = Vector2(16, 16)


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if _frame_texture:
		_frame_texture.texture = frame_3
	if _weapon_select:
		_weapon_select.visible = false
	_set_content_visible(false)
	_refresh_weapons_grid()


func _input(event: InputEvent) -> void:
	if not _is_open or _is_busy:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode == KEY_F:
				_assign_selected_to_slot(&"A")
				get_viewport().set_input_as_handled()
				return
			if key_event.physical_keycode == KEY_G:
				_assign_selected_to_slot(&"B")
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("move_left"):
		_move_selection(-1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_move_selection(1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_up"):
		_move_selection(0, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_move_selection(0, 1)
		get_viewport().set_input_as_handled()


# ==============================================================================
# Public methods
# ==============================================================================

func is_open() -> bool:
	return _is_open


func is_busy() -> bool:
	return _is_busy


func open_with_transition() -> void:
	if _is_busy or _is_open:
		return

	_is_busy = true
	_refresh_weapons_grid()
	visible = true
	await _play_open_frames()
	_is_open = true
	_is_busy = false


func close_with_transition() -> void:
	if _is_busy or not _is_open:
		return

	_is_busy = true
	await _play_close_frames()
	visible = false
	_is_open = false
	_is_busy = false


# ==============================================================================
# Private methods
# ==============================================================================

func _play_open_frames() -> void:
	_set_content_visible(false)
	_set_frame_texture(frame_1)
	await get_tree().create_timer(frame_step_seconds, true).timeout
	_set_frame_texture(frame_2)
	await get_tree().create_timer(frame_step_seconds, true).timeout
	_set_frame_texture(frame_3)
	_set_content_visible(true)


func _play_close_frames() -> void:
	_set_content_visible(false)
	_set_frame_texture(frame_3)
	await get_tree().create_timer(frame_step_seconds, true).timeout
	_set_frame_texture(frame_2)
	await get_tree().create_timer(frame_step_seconds, true).timeout
	_set_frame_texture(frame_1)


func _set_frame_texture(texture_value: Texture2D) -> void:
	if _frame_texture == null or texture_value == null:
		return
	_frame_texture.texture = texture_value


func _set_content_visible(is_visible: bool) -> void:
	if _frame_texture == null:
		return

	for child: Node in _frame_texture.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = is_visible


func _refresh_weapons_grid() -> void:
	if _weapons_grid == null:
		return

	for child: Node in _weapons_grid.get_children():
		child.free()
	_slot_weapon_ids.clear()

	_player_ref = _resolve_player_ref()
	if _player_ref == null:
		return

	if not _player_ref.has_method("get_owned_weapons_for_save"):
		return

	var owned_weapons: Array = _player_ref.get_owned_weapons_for_save()
	var sorted_ids: Array[String] = []
	for item in owned_weapons:
		sorted_ids.append(String(item))
	sorted_ids.sort()

	# Build fixed slots so keyboard navigation always works over the 4x2 grid.
	for i in range(TOTAL_WEAPON_SLOTS):
		var slot_icon: TextureRect = TextureRect.new()
		slot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot_icon.custom_minimum_size = SLOT_ICON_SIZE
		slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_icon.texture = null
		_weapons_grid.add_child(slot_icon)
		_slot_weapon_ids.append(&"none")

	var write_index: int = 0
	for weapon_id in sorted_ids:
		if write_index >= TOTAL_WEAPON_SLOTS:
			break

		var icon: Texture2D = _get_weapon_icon(StringName(weapon_id))
		if icon == null:
			continue

		var slot_icon: TextureRect = _weapons_grid.get_child(write_index) as TextureRect
		if slot_icon:
			slot_icon.texture = icon
			_slot_weapon_ids[write_index] = StringName(weapon_id)
			write_index += 1

	var item_count: int = _weapons_grid.get_child_count()
	if item_count <= 0:
		_selected_index = -1
		_update_selector_visual()
		return

	if _selected_index < 0 or _selected_index >= item_count:
		_selected_index = 0

	_update_selector_visual()


func _resolve_player_ref() -> Node:
	if is_instance_valid(_player_ref):
		return _player_ref

	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null

	return players[0]


func _get_weapon_icon(weapon_id: StringName) -> Texture2D:
	match weapon_id:
		&"sword":
			return sword_icon
		_:
			return null


func _move_selection(delta_x: int, delta_y: int) -> void:
	var item_count: int = _weapons_grid.get_child_count()
	if item_count <= 0:
		_selected_index = -1
		_update_selector_visual()
		return

	if _selected_index < 0:
		_selected_index = 0
		_update_selector_visual()
		return

	var cols: int = max(_weapons_grid.columns, 1)
	var row: int = _selected_index / cols
	var col: int = _selected_index % cols

	if delta_x < 0 and col > 0 and _selected_index - 1 >= 0:
		_selected_index -= 1
	elif delta_x > 0 and col < cols - 1 and _selected_index + 1 < item_count:
		_selected_index += 1
	elif delta_y < 0 and _selected_index - cols >= 0:
		_selected_index -= cols
	elif delta_y > 0 and _selected_index + cols < item_count:
		_selected_index += cols

	_update_selector_visual()


func _update_selector_visual() -> void:
	if _weapon_select == null:
		return

	if _selected_index < 0 or _selected_index >= _weapons_grid.get_child_count():
		_weapon_select.visible = false
		return

	var selected_node: Node = _weapons_grid.get_child(_selected_index)
	if not (selected_node is Control):
		_weapon_select.visible = false
		return

	var selected_control: Control = selected_node as Control
	var parent_control: Control = _weapon_select.get_parent() as Control
	if parent_control == null:
		_weapon_select.visible = false
		return

	_weapon_select.visible = true
	var local_pos: Vector2 = selected_control.global_position - parent_control.global_position
	var icon_size: Vector2 = selected_control.size
	var selector_size: Vector2 = _weapon_select.size
	if selector_size == Vector2.ZERO and _weapon_select.texture:
		selector_size = _weapon_select.texture.get_size()

	var center_offset: Vector2 = (icon_size - selector_size) * 0.5
	_weapon_select.position = local_pos + center_offset + selector_offset


func _assign_selected_to_slot(slot_name: StringName) -> void:
	if _selected_index < 0 or _selected_index >= _slot_weapon_ids.size():
		return

	var weapon_id: StringName = _slot_weapon_ids[_selected_index]
	if weapon_id == &"none":
		return

	var selected_icon: Texture2D = null
	var selected_node: Node = _weapons_grid.get_child(_selected_index)
	if selected_node is TextureRect:
		selected_icon = (selected_node as TextureRect).texture

	weapon_assign_requested.emit(slot_name, weapon_id, selected_icon)
