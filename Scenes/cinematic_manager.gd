extends Node

# ================================
# CONFIGURACIÓN
# ================================
@export var text_speed: float = 0.05  
@export var auto_advance_delay: float = 2.0  

# ================================
# REFERENCIAS UI
# ================================
@onready var cinematic_container: PanelContainer = $CinematicContainer
@onready var cinematic_label: Label = $CinematicContainer/CinematicLabel
@onready var skip_label: Label = $SkipLabel

# ================================
# VARIABLES INTERNAS
# ================================
var is_playing: bool = false
var current_dialogue_queue: Array = []
var current_dialogue_index: int = 0
var is_typing: bool = false
var current_text: String = ""
var displayed_chars: int = 0
var type_timer: float = 0.0

var on_cinematic_finished: Callable

# ================================
# SEÑALES
# ================================
signal dialogue_started()
signal dialogue_line_complete()
signal dialogue_finished()

# ==============================================================================
# INICIALIZACIÓN
# ==============================================================================
func _ready():
	cinematic_container.visible = false
	skip_label.visible = false
	
	cinematic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cinematic_label.text = ""

func _process(delta):
	if not is_playing:
		return
	
	if is_typing:
		_animate_text(delta)
	
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("jump"):
		_handle_advance_input()

# ==============================================================================
#  CINEMÁTICA
# ==============================================================================

func play_cinematic(dialogue_data: Array, callback: Callable = Callable()):
	"""
	dialogue_data: Array de diccionarios con esta estructura:
	[
		{
			"speaker": "Rupicola",  # Nombre del personaje (opcional)
			"text": "Hey! Ese es mi pescado!",
			"pause_game": true  # Si debe pausar entidades (default: true)
		}
	]
	"""
	if is_playing:
		print("⚠️ CinematicManager: Ya hay una cinemática en curso")
		return
	
	is_playing = true
	current_dialogue_queue = dialogue_data
	current_dialogue_index = 0
	on_cinematic_finished = callback
	
	_pause_game_entities()
	
	# Mostrar UI
	cinematic_container.visible = true
	skip_label.visible = true
	
	# Emitir señal de inicio
	dialogue_started.emit()
	
	# Mostrar primera línea
	_show_next_dialogue()

# Versión simplificada para un solo mensaje
func play_single_message(speaker: String, text: String, callback: Callable = Callable()):
	var dialogue = [{
		"speaker": speaker,
		"text": text,
		"pause_game": true
	}]
	play_cinematic(dialogue, callback)

# ==============================================================================
# LÓGICA DE DIÁLOGO
# ==============================================================================

func _show_next_dialogue():
	if current_dialogue_index >= current_dialogue_queue.size():
		_end_cinematic()
		return
	
	var dialogue_line = current_dialogue_queue[current_dialogue_index]
	var speaker = dialogue_line.get("speaker", "")
	var text = dialogue_line.get("text", "")
	
	if speaker != "":
		current_text = speaker + ": " + text
	else:
		current_text = text
	
	# animación de escritura
	is_typing = true
	displayed_chars = 0
	type_timer = 0.0
	cinematic_label.text = ""
	cinematic_label.visible_ratio = 0.0

func _animate_text(delta: float):
	if not is_typing:
		return
	
	type_timer += delta
	
	# Escribir progresivamente
	if type_timer >= text_speed:
		type_timer = 0.0
		displayed_chars += 1
		
		cinematic_label.text = current_text
		cinematic_label.visible_characters = displayed_chars
		
		# Verificar si terminó de escribir
		if displayed_chars >= current_text.length():
			_finish_typing()

func _finish_typing():
	is_typing = false
	cinematic_label.text = current_text
	cinematic_label.visible_ratio = 1.0
	dialogue_line_complete.emit()

func _handle_advance_input():
	if is_typing:
		_finish_typing()
	else:
		current_dialogue_index += 1
		_show_next_dialogue()

func _end_cinematic():
	is_playing = false
	
	# Ocultar UI
	cinematic_container.visible = false
	skip_label.visible = false
	
	_resume_game_entities()
	
	# Emitir señal de finalización
	dialogue_finished.emit()
	
	# Ejecutar callback si existe
	if on_cinematic_finished.is_valid():
		on_cinematic_finished.call()
	
	# Limpiar
	current_dialogue_queue.clear()
	current_dialogue_index = 0

# ==============================================================================
# ENTIDADES DEL JUEGO
# ==============================================================================

func _pause_game_entities():
	# Pausar player
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		player.set_process(false)
		player.set_physics_process(false)
	
	# Pausar enemigos
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)
	
	print("⏸️ CinematicManager: Entidades pausadas")

func _resume_game_entities():
	# Reanudar player
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		player.set_process(true)
		player.set_physics_process(true)
	
	# Reanudar enemigos
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		enemy.set_process(true)
		enemy.set_physics_process(true)
	
	print("▶️ CinematicManager: Entidades reanudadas")

# ==============================================================================
# FUNCIONES ÚTILES PARA EVENTOS
# ==============================================================================

# Skipear toda la cinemática
func skip_cinematic():
	if is_playing:
		_end_cinematic()
