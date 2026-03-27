## Game over screen UI that allows player to restart the game.
extends Control

# ==============================================================================
# Constants
# ==============================================================================

const START_LEVEL_PATH: String = "res://Scenes/Levels/main.tscn"


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	# Make mouse visible
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Connect play again button
	if %PlayAgainButton:
		%PlayAgainButton.pressed.connect(_on_play_again_button_pressed)
	else:
		push_error("Error crítico: El nodo PlayAgainButton no se encontró usando el prefijo %.")


# ==============================================================================
# Private Methods - Signal Handlers
# ==============================================================================

func _on_play_again_button_pressed() -> void:
	# Hide cursor again for main game
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Load start level with transition
	TransitionManager.transition_to_scene(START_LEVEL_PATH, "default")
