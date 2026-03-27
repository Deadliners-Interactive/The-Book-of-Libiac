## Level transition trigger that detects player and changes scenes.
## Supports optional key requirement, prompts, and auto-trigger behavior.
extends Area3D

# ==============================================================================
# Exports
# ==============================================================================

@export_file("*.tscn")
var _target_level: String = ""

@export var _spawn_point_id: String = "default"
@export var _show_prompt: bool = true
@export var _auto_trigger: bool = false
@export var _require_key: bool = false

# ==============================================================================
# Member Variables
# ==============================================================================

var _player_inside: bool = false
var _player_ref: Node = null
var _has_triggered: bool = false

# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	add_to_group("level_trigger")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)


func _process(_delta: float) -> void:
	if not _auto_trigger and _player_inside and not _has_triggered:
		if Input.is_action_just_pressed("ui_accept"):
			_trigger_level_change(_player_ref)

# ==============================================================================
# Public Methods
# ==============================================================================

func trigger_level_change(player: Node) -> void:
	_trigger_level_change(player)

# ==============================================================================
# Private Methods - Trigger Logic
# ==============================================================================

func _trigger_level_change(player: Node) -> void:
	if _has_triggered:
		return

	if _target_level.is_empty():
		push_warning("LevelTrigger: No target scene specified")
		return

	if _require_key:
		if not player.has_method("use_key") or not player.use_key():
			if player.has_method("show_notification"):
				player.show_notification("A key is required to proceed!")
			return

	_has_triggered = true

	# Save player state before transitioning
	GameState.save_player_state(player)

	TransitionManager.transition_to_scene(_target_level, _spawn_point_id)

# ==============================================================================
# Private Methods - UI Prompts
# ==============================================================================

func _show_interaction_prompt(player: Node) -> void:
	if player.has_method("show_immediate_notification") and not _auto_trigger:
		var message: String = "Press SPACE to continue"
		if _require_key:
			message = "Press SPACE (Requires key)"
		player.show_immediate_notification(message)


func _hide_prompt(_player: Node) -> void:
	pass

# ==============================================================================
# Private Methods - Signal Handlers
# ==============================================================================

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_player_ref = body

		if _show_prompt:
			_show_interaction_prompt(body)

		if _auto_trigger and not _has_triggered:
			_trigger_level_change(body)


func _on_area_entered(area: Node) -> void:
	var parent: Node = area.get_parent()
	if parent and parent.is_in_group("player"):
		_player_inside = true
		_player_ref = parent

		if _show_prompt:
			_show_interaction_prompt(parent)

		if _auto_trigger and not _has_triggered:
			_trigger_level_change(parent)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_player_ref = null
		_hide_prompt(body)
