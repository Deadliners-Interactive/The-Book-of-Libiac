extends CanvasLayer

# --- CONFIGURACIÓN ---
@export var full_heart: Texture2D
@export var half_heart: Texture2D
@export var empty_heart: Texture2D

# --- CONSTANTES DEL SISTEMA ---
const HP_PER_CONTAINER: float = 10.0
const HALF_CONTAINER_HP: float = 5.0

# --- REFERENCIAS ---
@onready var hearts_container: HBoxContainer = $HBoxContainer

# Array para guardar las referencias a los TextureRect creados
var heart_nodes: Array[TextureRect] = []

# Referencia al jugador
var player_ref: CharacterBody3D = null

func _ready():
	# IMPORTANTE: Añadirse al grupo "ui" automáticamente
	add_to_group("ui")
	
	# Limpiar contenedores existentes (empezamos desde cero)
	for child in hearts_container.get_children():
		child.queue_free()
	heart_nodes.clear()
	
	# Buscar al jugador con call_deferred para evitar problemas de orden
	call_deferred("_find_player")

# --- FUNCIÓN PRINCIPAL: ACTUALIZAR VIDA ACTUAL ---
func update_hearts_display():
	if not is_instance_valid(player_ref):
		return
	
	var current_hp = player_ref.current_health
	var num_containers = heart_nodes.size()
	
	print("💚 UI: Actualizando vida - HP: %.1f" % current_hp)
	
	for i in range(num_containers):
		var container_index = i
		var container_start_hp = container_index * HP_PER_CONTAINER
		var container_end_hp = (container_index + 1) * HP_PER_CONTAINER
		
		# Determinar qué sprite mostrar para este contenedor
		if current_hp >= container_end_hp:
			# Contenedor lleno (10 HP o más)
			heart_nodes[i].texture = full_heart
		elif current_hp >= container_start_hp + HALF_CONTAINER_HP:
			# Medio contenedor (entre 5 y 10 HP)
			heart_nodes[i].texture = half_heart
		else:
			# Contenedor vacío (menos de 5 HP)
			heart_nodes[i].texture = empty_heart

# --- FUNCIÓN: ACTUALIZAR CANTIDAD DE CONTENEDORES (MAX HP) ---
func update_max_hearts_display():
	if not is_instance_valid(player_ref):
		return
	
	var max_hp = player_ref.max_health
	var needed_containers = int(ceil(max_hp / HP_PER_CONTAINER))
	var current_containers = heart_nodes.size()
	
	print("💚 UI: Max HP = %.1f, Contenedores necesarios = %d" % [max_hp, needed_containers])
	
	# Crear contenedores faltantes
	if current_containers < needed_containers:
		for i in range(needed_containers - current_containers):
			var new_heart = TextureRect.new()
			new_heart.texture = full_heart
			new_heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			new_heart.custom_minimum_size = Vector2(32, 32)  # Tamaño recomendado
			hearts_container.add_child(new_heart)
			heart_nodes.append(new_heart)
			print("💚 UI: Contenedor %d creado" % (heart_nodes.size()))
	
	# Eliminar contenedores sobrantes
	elif current_containers > needed_containers:
		for i in range(current_containers - needed_containers):
			var heart_to_remove = heart_nodes.pop_back()
			heart_to_remove.queue_free()
	
	# Actualizar visual inmediatamente
	update_hearts_display()

func _find_player():
	"""Buscar al jugador de forma segura"""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_ref = players[0]
		print("💚 UI: Jugador encontrado - ", player_ref.name)
		
		# Crear los contenedores basados en max_health del jugador
		update_max_hearts_display()
		update_hearts_display()
	else:
		push_error("⚠️ UI: No se encontró jugador en el grupo 'player'")
		# Reintentar después de un momento
		await get_tree().create_timer(0.5).timeout
		_find_player()
