## Death zone that detects player and triggers game over/restart sequence.
## Can trigger on body_entered or area_entered from any child area.
extends Area3D

# ==============================================================================
# Exports
# ==============================================================================

@export var death_message: String = "¡Has caído al vacío!"
@export var show_message: bool = true
@export var fade_duration: float = 1.0
@export var restart_delay: float = 0.5

# ==============================================================================
# Member Variables
# ==============================================================================

var _has_triggered: bool = false


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	add_to_group("death_zone")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


# ==============================================================================
# Private Methods - Signal Handlers
# ==============================================================================

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not _has_triggered:
		_trigger_death(body)


func _on_area_entered(area: Area3D) -> void:
	# Detect if child Area3D of player entered
	if area.get_parent() and area.get_parent().is_in_group("player") and not _has_triggered:
		var player: Node = area.get_parent()
		_trigger_death(player)


# ==============================================================================
# Private Methods - Death Sequence
# ==============================================================================

func _trigger_death(player: Node) -> void:
	if _has_triggered:
		return

	_has_triggered = true

	player.set_physics_process(false)
	player.set_process(false)
	player.velocity = Vector3.ZERO

	if show_message and player.has_method("show_immediate_notification"):
		player.show_immediate_notification(death_message)

	_start_death_sequence()


func _start_death_sequence() -> void:
	# Fade to black
	var fade: ColorRect = ColorRect.new()
	fade.color = Color.BLACK
	fade.modulate.a = 0
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.z_index = 1000
	get_tree().root.add_child(fade)

	# Fade out
	var tween: Tween = create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, fade_duration)
	await tween.finished

	# Wait before restarting
	await get_tree().create_timer(restart_delay).timeout

	# Restart game
	_restart_game()

	# Cleanup
	fade.queue_free()


func _restart_game() -> void:
	# Reset player state
	GameState.reset_player_state()

	# Reload current scene
	get_tree().call_deferred("reload_current_scene")
