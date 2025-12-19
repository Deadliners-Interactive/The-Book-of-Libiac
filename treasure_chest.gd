# TreasureChest.gd
extends Node3D

# ================================
# CONFIGURACIÓN DEL COFRE
# ================================
@export var loot_scene: PackedScene         # Escena del item a soltar
@export var spawn_offset: Vector3 = Vector3(0, 0.1, 0) # Altura mínima (10 cm)
@export var open_duration: float = 0.5      # Duración de la apertura

# --- CONFIGURACIÓN DEL LOOT ---
@export var jump_distance: float = 0.05     # Distancia frontal mínima (5 cm)
@export var loot_scale: Vector3 = Vector3(2.0, 2.0, 2.0) # <--- NUEVO: Escala deseada al aparecer

# ================================
# ESTADO
# ================================
var is_open: bool = false
var is_opening: bool = false

# ================================
# REFERENCIAS
# ================================
@onready var tapa: Node3D = $tapa
@onready var area: Area3D = $Area3D

func _ready() -> void:
	if not tapa:
		push_error("Falta el nodo 'tapa'")
		return
	
	if not area.area_entered.is_connected(_on_area_entered):
		area.area_entered.connect(_on_area_entered)

func _on_area_entered(area_hit: Area3D) -> void:
	if is_open or is_opening:
		return
	
	if not area_hit.is_in_group("hitbox_player"):
		return
	
	print("¡Golpeado por el jugador! Abriendo...")
	_open_chest()

func _open_chest() -> void:
	is_opening = true
	
	area.set_deferred("monitoring", false)
	area.set_deferred("monitorable", false)
	
	# Animación de apertura de la tapa
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE) 
	
	var target_rotation_degrees = Vector3(24.6, 90.0, -90.0)
	tween.tween_property(tapa, "rotation_degrees", target_rotation_degrees, open_duration)
	
	# Spawn del item a mitad de animación
	await get_tree().create_timer(open_duration * 0.3).timeout
	_spawn_loot()
	
	await tween.finished
	is_open = true
	is_opening = false
	print("Abierto completamente.")

func _spawn_loot() -> void:
	if not loot_scene:
		print("Abierto pero sin loot configurado.")
		return

	var item = loot_scene.instantiate()
	
	item.scale = loot_scale

	add_child(item)

	var final_local_position = Vector3.ZERO
	
	final_local_position.y += spawn_offset.y
	
	final_local_position.z += jump_distance
	
	item.position = final_local_position
	
	print("Item aparecido, escala ajustada y flotando sobre el cofre.")
