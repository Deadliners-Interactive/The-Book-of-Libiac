## Autoload handler for game over sequence and restart logic.
## Called when player dies to show death message, fade out, and reload scene.
extends Node

# ==============================================================================
# Exports
# ==============================================================================

@export var death_message: String = "¡Has muerto! Inténtalo de nuevo."
@export var show_message: bool = true
@export var fade_duration: float = 1.0
@export var restart_delay: float = 1.5

# ==============================================================================
# Member Variables
# ==============================================================================

var _has_triggered: bool = false
var _player_ref: Node = null


# ==============================================================================
# Public Methods
# ==============================================================================

func handle_player_death(player: Node) -> void:
	if _has_triggered:
		return

	_has_triggered = true
	_player_ref = player

	# Stop player physics and processes
	player.call_deferred("set_physics_process", false)
	player.call_deferred("set_process", false)
	player.velocity = Vector3.ZERO

	# Show death message
	if show_message and player.has_method("show_immediate_notification"):
		player.show_immediate_notification(death_message)

	_start_death_sequence()


# ==============================================================================
# Private Methods
# ==============================================================================

func _start_death_sequence() -> void:
	# Create fade to black
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
