# TreasureChest.gd
extends Node3D

# ================================
# CONFIGURACIÓN DEL COFRE
# ================================
@export var loot_scene: PackedScene         # Escena del item a soltar
@export var spawn_offset: Vector3 = Vector3(0, 1.0, 0)
@export var open_duration: float = 0.5      # Duración de la apertura

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
		push_error("💰 TreasureChest: Falta el nodo 'tapa'")
		return

	# Conectar señal: Area detecta Area (tu espada es un Area3D)
	if not area.area_entered.is_connected(_on_area_entered):
		area.area_entered.connect(_on_area_entered)

func _on_area_entered(area_hit: Area3D) -> void:
	# 1. Verifica si ya está abierto
	if is_open or is_opening:
		return

	# 2. Verifica si quien golpeó es el hitbox del jugador
	if not area_hit.is_in_group("hitbox_player"):
		return

	print("💰 TreasureChest: ¡Golpeado por el jugador! Abriendo...")
	_open_chest()

func _open_chest() -> void:
	is_opening = true
	
	# Desactivar monitoreo de forma segura para evitar doble golpe
	area.set_deferred("monitoring", false)
	area.set_deferred("monitorable", false)

	# Animación con Tween
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE) 

	# --- CORRECCIÓN DE ROTACIÓN: Usamos el valor ABSOLUTO del editor ---
	# El valor final en grados que hace que la tapa quede abierta y girada:
	var target_rotation_degrees = Vector3(24.6, 90.0, -90.0)
	
	tween.tween_property(
		tapa, 
		"rotation_degrees", 
		target_rotation_degrees, 
		open_duration
	)
	# -----------------------------------------------------------------

	# Spawn del item a mitad de animación
	await get_tree().create_timer(open_duration * 0.3).timeout
	_spawn_loot()

	await tween.finished
	is_open = true
	is_opening = false
	print("✅ TreasureChest: Abierto completamente.")

func _spawn_loot() -> void:
	if not loot_scene:
		print("💰 TreasureChest: Abierto pero sin loot configurado.")
		return

	var item = loot_scene.instantiate()
	get_tree().current_scene.add_child(item)
	item.global_position = global_position + spawn_offset
	
	# Pequeño salto del item
	var tween = create_tween()
	item.scale = Vector3.ZERO
	tween.tween_property(item, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC)
