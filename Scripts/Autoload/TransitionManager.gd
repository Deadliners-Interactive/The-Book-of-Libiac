## Scene transition manager with fade effect.
##
## Handles smooth transitions between scenes with fade in/out animations.
## Must be configured as an Autoload in Project Settings.
extends Node


# ==============================================================================
# Member variables
# ==============================================================================

var _fade_rect: ColorRect = null
var _is_transitioning: bool = false


# ==============================================================================
# Built-in methods
# ==============================================================================

func _ready() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.name = "TransitionFade"
	_fade_rect.z_index = 1000
	add_child(_fade_rect)


# ==============================================================================
# Public methods
# ==============================================================================

func transition_to_scene(scene_path: String, spawn_id: String = "default") -> void:
	"""Performs a fade transition to another scene."""
	if _is_transitioning:
		return
	
	_is_transitioning = true
	GameState.spawn_point_name = spawn_id
	
	# Fade out
	_fade_rect.modulate.a = 0.0
	_fade_rect.visible = true
	
	var tween_out: Tween = create_tween()
	tween_out.tween_property(_fade_rect, "modulate:a", 1.0, 0.5)
	await tween_out.finished
	
	# Change scene
	var error: int = get_tree().change_scene_to_file(scene_path)
	
	if error != OK:
		push_error(
			"⚠️ TransitionManager: Error al cambiar escena: " + scene_path
		)
		_is_transitioning = false
		_fade_rect.visible = false
		return
	
	# Wait for new scene to load
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Fade in
	var tween_in: Tween = create_tween()
	tween_in.tween_property(_fade_rect, "modulate:a", 0.0, 0.5)
	await tween_in.finished
	
	_fade_rect.visible = false
	_is_transitioning = false


func transition_instant(scene_path: String, spawn_id: String = "default") -> void:
	"""Changes scene instantly without animation."""
	if _is_transitioning:
		return
	
	GameState.spawn_point_name = spawn_id
	get_tree().change_scene_to_file(scene_path)
