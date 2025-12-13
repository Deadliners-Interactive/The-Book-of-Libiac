# ==============================================================================
# TransitionManager.gd - AUTOLOAD
# ==============================================================================
# Este script debe configurarse como Autoload:
# Project > Project Settings > Autoload
# Path: res://TransitionManager.gd
# Node Name: TransitionManager

extends Node

var fade_rect: ColorRect = null
var is_transitioning: bool = false

func _ready():
	# Crear el fade que persiste entre escenas
	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.name = "TransitionFade"
	fade_rect.z_index = 1000  # Asegurar que esté encima de todo
	add_child(fade_rect)

func transition_to_scene(scene_path: String, spawn_id: String = "default"):
	"""Realiza una transición con fade a otra escena"""
	if is_transitioning:
		print("⚠️ TransitionManager: Ya hay una transición en curso")
		return
	
	is_transitioning = true
	
	# Guardar el spawn point
	GameState.spawn_point_name = spawn_id
	
	# Fade out
	fade_rect.modulate.a = 0
	fade_rect.visible = true
	
	var tween_out = create_tween()
	tween_out.tween_property(fade_rect, "modulate:a", 1.0, 0.5)
	await tween_out.finished
	
	# Cambiar escena
	var error = get_tree().change_scene_to_file(scene_path)
	
	if error != OK:
		push_error("⚠️ TransitionManager: Error al cambiar escena: " + scene_path)
		is_transitioning = false
		fade_rect.visible = false
		return
	
	# Esperar a que la nueva escena cargue
	await get_tree().process_frame
	await get_tree().process_frame  # Doble frame para asegurar
	
	# Fade in
	var tween_in = create_tween()
	tween_in.tween_property(fade_rect, "modulate:a", 0.0, 0.5)
	await tween_in.finished
	
	fade_rect.visible = false
	is_transitioning = false
	
	print("✅ TransitionManager: Transición completada a:", scene_path)

func transition_instant(scene_path: String, spawn_id: String = "default"):
	"""Cambia de escena sin animación"""
	if is_transitioning:
		return
	
	GameState.spawn_point_name = spawn_id
	get_tree().change_scene_to_file(scene_path)
