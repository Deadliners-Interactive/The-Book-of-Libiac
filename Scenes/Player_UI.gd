extends CanvasLayer

# ================================
# CONFIGURACIÓN: ICONOS DE VIDA
# ================================
@export var full_heart: Texture2D
@export var half_heart: Texture2D
@export var empty_heart: Texture2D

# ================================
# CONFIGURACIÓN: ICONO DE LLAVE
# ================================
@export var key_texture: Texture2D

# ================================
# CONSTANTES DEL SISTEMA DE VIDA
# ================================
const HP_PER_CONTAINER: float = 10.0
const HALF_CONTAINER_HP: float = 5.0

# ================================
# REFERENCIAS A LA UI
# ================================
@onready var hearts_container: HBoxContainer = $HeartsContainer
@onready var keys_container: HBoxContainer = $KeysContainer
@onready var key_icon: TextureRect = $KeysContainer/TextureRect
@onready var key_label: Label = $KeysContainer/Label

var heart_nodes: Array[TextureRect] = []

# ================================
# REFERENCIA AL JUGADOR
# ================================
var player_ref: CharacterBody3D = null


func _ready():
	add_to_group("ui")

	# --- FORZAR QUE EL ICONO DE LA LLAVE SIEMPRE SE VEA ---
	key_icon.visible = true
	key_icon.texture = key_texture if key_texture else key_icon.texture
	key_icon.custom_minimum_size = Vector2(32, 32)
	key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	key_label.text = "x0"

	# --- LIMPIAR CORAZONES ---
	for child in hearts_container.get_children():
		child.queue_free()
	heart_nodes.clear()

	call_deferred("_find_player")


# =============================================================
#  SISTEMA DE VIDA
# =============================================================
func update_hearts_display():
	if not is_instance_valid(player_ref):
		return

	var current_hp = player_ref.current_health
	var num_containers = heart_nodes.size()

	for i in range(num_containers):
		var container_index = i
		var container_start_hp = container_index * HP_PER_CONTAINER
		var container_end_hp = (container_index + 1) * HP_PER_CONTAINER
		
		if current_hp >= container_end_hp:
			heart_nodes[i].texture = full_heart
		elif current_hp >= container_start_hp + HALF_CONTAINER_HP:
			heart_nodes[i].texture = half_heart
		else:
			heart_nodes[i].texture = empty_heart


func update_max_hearts_display():
	if not is_instance_valid(player_ref):
		return

	var max_hp = player_ref.max_health
	var needed_containers = int(ceil(max_hp / HP_PER_CONTAINER))
	var current_containers = heart_nodes.size()

	# Crear contenedores faltantes
	if current_containers < needed_containers:
		for i in range(needed_containers - current_containers):
			var new_heart = TextureRect.new()
			new_heart.texture = full_heart
			new_heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			new_heart.custom_minimum_size = Vector2(32, 32)
			hearts_container.add_child(new_heart)
			heart_nodes.append(new_heart)

	# Eliminar contenedores sobrantes
	elif current_containers > needed_containers:
		for i in range(current_containers - needed_containers):
			var heart_to_remove = heart_nodes.pop_back()
			heart_to_remove.queue_free()

	update_hearts_display()


# =============================================================
#  SISTEMA DE LLAVES  🔑
# =============================================================
func update_keys_display():
	if not is_instance_valid(player_ref):
		return

	# Esto NO oculta nada, solo actualiza el número
	key_label.text = "x" + str(player_ref.key_count)


# =============================================================
# BÚSQUEDA DE PLAYER
# =============================================================
func _find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_ref = players[0]

		update_max_hearts_display()
		update_hearts_display()
		update_keys_display()
	else:
		await get_tree().create_timer(0.5).timeout
		_find_player()
