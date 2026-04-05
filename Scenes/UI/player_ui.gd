## Player HUD UI displaying health, keys, and notifications.
## Manages heart container display, key counter, and notification queue system.
extends CanvasLayer

# ==============================================================================
# Exports - Heart Icons
# ==============================================================================

@export var full_heart: Texture2D
@export var half_heart: Texture2D
@export var empty_heart: Texture2D

# ==============================================================================
# Exports - Notifications
# ==============================================================================

@export var notification_duration: float = 3.0
@export var notification_fade_speed: float = 0.5
@export var max_notifications: int = 5

# ==============================================================================
# Constants
# ==============================================================================

const HP_PER_CONTAINER: float = 10.0
const HALF_CONTAINER_HP: float = 5.0
const DEFAULT_VISIBLE_CONTAINERS: int = 3
const NOTIFICATION_COOLDOWN: float = 0.5
const MIN_KEYS: int = 0
const MAX_KEYS: int = 99
const INVENTORY_TOGGLE_ACTION: StringName = &"inventory_toggle"

# ==============================================================================
# Member Variables
# ==============================================================================

var _heart_nodes: Array[TextureRect] = []
var _notification_queue: Array[String] = []
var _is_showing_notification: bool = false
var _last_notification_message: String = ""
var _last_notification_time: float = 0.0
var _slot_a_weapon_id: StringName = &"none"
var _slot_b_weapon_id: StringName = &"none"

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _life_container: HBoxContainer = get_node_or_null("%LifeContainer") as HBoxContainer
@onready var _keys_container: HBoxContainer = get_node_or_null("%KeysContainer") as HBoxContainer
@onready var _key_label: Label = _keys_container.get_node_or_null("Label") as Label if _keys_container else null
@onready var _notification_container: PanelContainer = $Notification
@onready var _notification_label: Label = $Notification/NotificationLabel
@onready var _inventory_menu: Control = get_node_or_null("Inventory_Menu") as Control
@onready var _slot_a: TextureRect = $Player_status_bar/GridContainer/Slot_A
@onready var _slot_b: TextureRect = $Player_status_bar/GridContainer/Slot_B

var _player_ref: CharacterBody3D = null


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	add_to_group("ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_inventory_input_action()

	if _key_label:
		_key_label.text = "00"
	else:
		push_warning("No se encontro Label del contador de llaves en Player_status_bar/KeysContainer")

	_notification_container.visible = false
	_notification_label.text = ""
	_inventory_menu.visible = false

	# Position notification panel (bottom left)
	_notification_container.position = Vector2(20, get_viewport().size.y - 100)

	# Listen for viewport resize
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	_collect_life_nodes()
	_initialize_default_life_display()

	if _inventory_menu and _inventory_menu.has_signal("weapon_assign_requested"):
		if not _inventory_menu.weapon_assign_requested.is_connected(_on_inventory_weapon_assign_requested):
			_inventory_menu.weapon_assign_requested.connect(_on_inventory_weapon_assign_requested)

	call_deferred("_find_player")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(String(INVENTORY_TOGGLE_ACTION)):
		await _toggle_inventory_menu()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(get_tree()) and _inventory_menu and _inventory_menu.visible:
		get_tree().paused = false


# ==============================================================================
# Public Methods - Notifications
# ==============================================================================

func show_notification(message: String) -> void:
	var current_time: float = Time.get_unix_time_from_system()

	# Check for duplicate notification
	if message == _last_notification_message and current_time - _last_notification_time < NOTIFICATION_COOLDOWN:
		return

	# Save notification
	_last_notification_message = message
	_last_notification_time = current_time

	# Add to queue
	_notification_queue.append(message)

	# Show if not already showing
	if not _is_showing_notification and _notification_queue.size() > 0:
		_show_next_notification()


func show_immediate_notification(message: String) -> void:
	# Clear queue and stop current notification
	_notification_queue.clear()
	_is_showing_notification = false

	# Show immediately
	show_notification(message)


# ==============================================================================
# Public Methods - Hearts
# ==============================================================================

func update_hearts_display() -> void:
	if not is_instance_valid(_player_ref):
		return

	if _heart_nodes.is_empty():
		_collect_life_nodes()

	var current_hp: int = _player_ref.current_health
	var num_containers: int = _heart_nodes.size()

	for i in range(num_containers):
		if not _heart_nodes[i].visible:
			continue

		var container_index: int = i
		var container_start_hp: float = container_index * HP_PER_CONTAINER
		var container_end_hp: float = (container_index + 1) * HP_PER_CONTAINER

		if current_hp >= container_end_hp:
			_heart_nodes[i].texture = full_heart
		elif current_hp >= container_start_hp + HALF_CONTAINER_HP:
			_heart_nodes[i].texture = half_heart
		else:
			_heart_nodes[i].texture = empty_heart


func update_max_hearts_display() -> void:
	if not is_instance_valid(_player_ref):
		return

	if _heart_nodes.is_empty():
		_collect_life_nodes()

	if _heart_nodes.is_empty():
		return

	var max_hp: int = _player_ref.max_health
	var needed_containers: int = clampi(int(ceil(max_hp / HP_PER_CONTAINER)), 0, _heart_nodes.size())

	for i in range(_heart_nodes.size()):
		var life_node: TextureRect = _heart_nodes[i]
		life_node.visible = i < needed_containers
		if life_node.visible:
			life_node.texture = empty_heart

	update_hearts_display()


# ==============================================================================
# Public Methods - Keys
# ==============================================================================

func update_keys_display() -> void:
	if not is_instance_valid(_player_ref) or _key_label == null:
		return

	var display_keys: int = clampi(int(_player_ref.key_count), MIN_KEYS, MAX_KEYS)
	_key_label.text = "%02d" % display_keys


# ==============================================================================
# Private Methods
# ==============================================================================

func _show_next_notification() -> void:
	if _notification_queue.size() == 0:
		return

	_is_showing_notification = true

	# Get next message from queue
	var message: String = _notification_queue.pop_front()
	_notification_label.text = message

	# Show with fade in animation
	_notification_container.visible = true
	_notification_container.modulate = Color(1, 1, 1, 0)

	var tween_in: Tween = create_tween()
	tween_in.tween_property(_notification_container, "modulate",
							Color(1, 1, 1, 1), notification_fade_speed)
	tween_in.set_ease(Tween.EASE_OUT)

	# Wait for notification duration
	await get_tree().create_timer(notification_duration).timeout

	# Fade out animation
	var tween_out: Tween = create_tween()
	tween_out.tween_property(_notification_container, "modulate",
							 Color(1, 1, 1, 0), notification_fade_speed)
	tween_out.set_ease(Tween.EASE_IN)

	await tween_out.finished

	# Hide container
	_notification_container.visible = false
	_is_showing_notification = false

	# Show next notification if available
	if _notification_queue.size() > 0:
		await get_tree().create_timer(0.2).timeout
		_show_next_notification()


func _on_viewport_size_changed() -> void:
	_notification_container.position = Vector2(20, get_viewport().size.y - 100)


func _toggle_inventory_menu() -> void:
	if _inventory_menu == null:
		push_warning("No se encontro nodo Inventory_Menu en player_ui.tscn")
		return

	if _inventory_menu.has_method("is_busy") and _inventory_menu.call("is_busy"):
		return

	var should_open: bool = not _inventory_menu.visible
	if _inventory_menu.has_method("is_open"):
		should_open = not bool(_inventory_menu.call("is_open"))

	if should_open:
		get_tree().paused = true
		if _inventory_menu.has_method("open_with_transition"):
			await _inventory_menu.call("open_with_transition")
		else:
			_inventory_menu.visible = true
		return

	if _inventory_menu.has_method("close_with_transition"):
		await _inventory_menu.call("close_with_transition")
	else:
		_inventory_menu.visible = false

	get_tree().paused = false


func _ensure_inventory_input_action() -> void:
	if InputMap.has_action(String(INVENTORY_TOGGLE_ACTION)):
		return

	InputMap.add_action(String(INVENTORY_TOGGLE_ACTION))
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_I
	InputMap.action_add_event(String(INVENTORY_TOGGLE_ACTION), key_event)


func _find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player_ref = players[0]
		_connect_player_signals()

		update_max_hearts_display()
		update_hearts_display()
		update_keys_display()
	else:
		await get_tree().create_timer(0.5).timeout
		_find_player()


func _collect_life_nodes() -> void:
	_heart_nodes.clear()

	if _life_container == null:
		push_warning("No se encontro LifeContainer en player_ui.tscn")
		return

	var found_nodes: Array[Node] = _life_container.find_children("Life*", "TextureRect", true, false)
	for node: Node in found_nodes:
		if node is TextureRect:
			_heart_nodes.append(node as TextureRect)

	_heart_nodes.sort_custom(func(a: TextureRect, b: TextureRect) -> bool:
		return _extract_life_index(a.name) < _extract_life_index(b.name)
	)


func _initialize_default_life_display() -> void:
	if _heart_nodes.is_empty():
		return

	var default_visible: int = clampi(DEFAULT_VISIBLE_CONTAINERS, 0, _heart_nodes.size())
	for i in range(_heart_nodes.size()):
		var life_node: TextureRect = _heart_nodes[i]
		life_node.visible = i < default_visible
		life_node.texture = full_heart if i < default_visible else empty_heart


func _extract_life_index(node_name: String) -> int:
	if not node_name.begins_with("Life"):
		return 9999

	var index_text: String = node_name.substr(4)
	if index_text.is_valid_int():
		return index_text.to_int()

	return 9999


func _connect_player_signals() -> void:
	if not is_instance_valid(_player_ref):
		return

	if _player_ref.has_signal("health_changed") and not _player_ref.health_changed.is_connected(_on_player_health_changed):
		_player_ref.health_changed.connect(_on_player_health_changed)

	if _player_ref.has_signal("max_health_changed") and not _player_ref.max_health_changed.is_connected(_on_player_max_health_changed):
		_player_ref.max_health_changed.connect(_on_player_max_health_changed)

	if _player_ref.has_signal("keys_changed") and not _player_ref.keys_changed.is_connected(_on_player_keys_changed):
		_player_ref.keys_changed.connect(_on_player_keys_changed)

	if _player_ref.has_signal("notification_requested") and not _player_ref.notification_requested.is_connected(_on_player_notification_requested):
		_player_ref.notification_requested.connect(_on_player_notification_requested)

	if _player_ref.has_signal("immediate_notification_requested") and not _player_ref.immediate_notification_requested.is_connected(_on_player_immediate_notification_requested):
		_player_ref.immediate_notification_requested.connect(_on_player_immediate_notification_requested)


func _on_player_health_changed(_current: float, _max_value: float) -> void:
	update_hearts_display()


func _on_player_max_health_changed(_max_value: float) -> void:
	update_max_hearts_display()


func _on_player_keys_changed(_count: int) -> void:
	update_keys_display()


func _on_player_notification_requested(message: String) -> void:
	show_notification(message)


func _on_player_immediate_notification_requested(message: String) -> void:
	show_immediate_notification(message)


func _on_inventory_weapon_assign_requested(slot_name: StringName, weapon_id: StringName, icon: Texture2D) -> void:
	match slot_name:
		&"A":
			# Zelda-like behavior: one weapon can only live in one quick slot.
			if _slot_b_weapon_id == weapon_id:
				_slot_b_weapon_id = &"none"
				if _slot_b:
					_slot_b.texture = null

			_slot_a_weapon_id = weapon_id
			if _slot_a:
				_slot_a.texture = icon
			show_notification("%s -> Slot A" % String(weapon_id).capitalize())
		&"B":
			# Zelda-like behavior: one weapon can only live in one quick slot.
			if _slot_a_weapon_id == weapon_id:
				_slot_a_weapon_id = &"none"
				if _slot_a:
					_slot_a.texture = null

			_slot_b_weapon_id = weapon_id
			if _slot_b:
				_slot_b.texture = icon
			show_notification("%s -> Slot B" % String(weapon_id).capitalize())
