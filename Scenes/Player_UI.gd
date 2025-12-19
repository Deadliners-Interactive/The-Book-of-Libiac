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
# CONFIGURACIÓN: NOTIFICACIONES
# ================================
@export var notification_duration: float = 3.0  # Duración de cada notificación
@export var notification_fade_speed: float = 0.5  # Velocidad de desvanecimiento
@export var max_notifications: int = 5  # Máximo de notificaciones visibles

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
@onready var notification_container: PanelContainer = $Notification
@onready var notification_label: Label = $Notification/NotificationLabel

var heart_nodes: Array[TextureRect] = []
var notification_queue: Array[String] = []
var is_showing_notification: bool = false
var last_notification_message: String = ""  # Para evitar notificaciones duplicadas
var notification_cooldown: float = 0.5  # 0.5 segundos entre notificaciones iguales
var last_notification_time: float = 0.0
# ================================
# REFERENCIA AL JUGADOR
# ================================
var player_ref: CharacterBody3D = null

func _ready():
	add_to_group("ui")
	
	key_icon.visible = true
	key_icon.texture = key_texture if key_texture else key_icon.texture
	key_icon.custom_minimum_size = Vector2(32, 32)
	key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	key_label.text = "x0"
	
	notification_container.visible = false
	notification_label.text = ""
	
	# Ajustar posición del panel de notificaciones (inferior izquierda)
	notification_container.position = Vector2(20, get_viewport().size.y - 100)
	
	# Escuchar cambios de tamaño de ventana
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	# --- LIMPIAR CORAZONES ---
	for child in hearts_container.get_children():
		child.queue_free()
	heart_nodes.clear()
	
	call_deferred("_find_player")

func _on_viewport_size_changed():
	notification_container.position = Vector2(20, get_viewport().size.y - 100)

# =============================================================
#  SISTEMA DE NOTIFICACIONES
# =============================================================
func show_notification(message: String):
	var current_time = Time.get_unix_time_from_system()
	
	# Verificar si es la misma notificación reciente
	if message == last_notification_message and current_time - last_notification_time < notification_cooldown:
		return  # No mostrar notificaciones duplicadas muy seguidas
	
	print("📢 Notificación: ", message)
	
	# Guardar la última notificación
	last_notification_message = message
	last_notification_time = current_time
	
	# Agregar mensaje a la cola
	notification_queue.append(message)
	
	# Si no se está mostrando ninguna notificación, mostrar la siguiente
	if not is_showing_notification and notification_queue.size() > 0:
		_show_next_notification()

func _show_next_notification():
	if notification_queue.size() == 0:
		return
	
	is_showing_notification = true
	
	# Obtener el siguiente mensaje de la cola
	var message = notification_queue.pop_front()
	notification_label.text = message
	
	# Hacer visible el panel con animación de entrada
	notification_container.visible = true
	notification_container.modulate = Color(1, 1, 1, 0)  # Inicio transparente
	
	# Animación de entrada (fade in)
	var tween_in = create_tween()
	tween_in.tween_property(notification_container, "modulate", 
						   Color(1, 1, 1, 1), notification_fade_speed)
	tween_in.set_ease(Tween.EASE_OUT)
	
	# Esperar la duración configurada
	await get_tree().create_timer(notification_duration).timeout
	
	# Animación de salida (fade out)
	var tween_out = create_tween()
	tween_out.tween_property(notification_container, "modulate", 
							Color(1, 1, 1, 0), notification_fade_speed)
	tween_out.set_ease(Tween.EASE_IN)
	
	# Esperar que termine la animación
	await tween_out.finished
	
	# Ocultar el panel
	notification_container.visible = false
	is_showing_notification = false
	
	# Mostrar la siguiente notificación si hay más en la cola
	if notification_queue.size() > 0:
		# Pequeña pausa entre notificaciones
		await get_tree().create_timer(0.2).timeout
		_show_next_notification()

# Función para mostrar notificación inmediata (sin cola)
func show_immediate_notification(message: String):
	# Limpiar la cola actual
	notification_queue.clear()
	is_showing_notification = false
	
	# Mostrar notificación inmediata
	show_notification(message)

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
#  SISTEMA DE LLAVES 
# =============================================================
func update_keys_display():
	if not is_instance_valid(player_ref):
		return
	
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
