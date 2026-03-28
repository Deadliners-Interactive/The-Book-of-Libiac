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
# Exports - Key Icon
# ==============================================================================

@export var key_texture: Texture2D

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
const NOTIFICATION_COOLDOWN: float = 0.5

# ==============================================================================
# Member Variables
# ==============================================================================

var _heart_nodes: Array[TextureRect] = []
var _notification_queue: Array[String] = []
var _is_showing_notification: bool = false
var _last_notification_message: String = ""
var _last_notification_time: float = 0.0

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _hearts_container: HBoxContainer = $HeartsContainer
@onready var _key_icon: TextureRect = $KeysContainer/TextureRect
@onready var _key_label: Label = $KeysContainer/Label
@onready var _notification_container: PanelContainer = $Notification
@onready var _notification_label: Label = $Notification/NotificationLabel

var _player_ref: CharacterBody3D = null


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	add_to_group("ui")

	_key_icon.visible = true
	_key_icon.texture = key_texture if key_texture else _key_icon.texture
	_key_icon.custom_minimum_size = Vector2(32, 32)
	_key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	_key_label.text = "x0"

	_notification_container.visible = false
	_notification_label.text = ""

	# Position notification panel (bottom left)
	_notification_container.position = Vector2(20, get_viewport().size.y - 100)

	# Listen for viewport resize
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	# Clear hearts
	for child in _hearts_container.get_children():
		child.queue_free()
	_heart_nodes.clear()

	call_deferred("_find_player")


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

	var current_hp: int = _player_ref.current_health
	var num_containers: int = _heart_nodes.size()

	for i in range(num_containers):
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

	var max_hp: int = _player_ref.max_health
	var needed_containers: int = int(ceil(max_hp / HP_PER_CONTAINER))
	var current_containers: int = _heart_nodes.size()

	# Create missing containers
	if current_containers < needed_containers:
		for i in range(needed_containers - current_containers):
			var new_heart: TextureRect = TextureRect.new()
			new_heart.texture = full_heart
			new_heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			new_heart.custom_minimum_size = Vector2(32, 32)
			_hearts_container.add_child(new_heart)
			_heart_nodes.append(new_heart)

	# Remove excess containers
	elif current_containers > needed_containers:
		for i in range(current_containers - needed_containers):
			var heart_to_remove: TextureRect = _heart_nodes.pop_back()
			heart_to_remove.queue_free()

	update_hearts_display()


# ==============================================================================
# Public Methods - Keys
# ==============================================================================

func update_keys_display() -> void:
	if not is_instance_valid(_player_ref):
		return

	_key_label.text = "x" + str(_player_ref.key_count)


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
