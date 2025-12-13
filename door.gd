extends Node3D

@export var open_distance: float = 2.0
@export var open_speed: float = 1.5
@export var shake_duration: float = 1.0
@export var shake_intensity: float = 0.05  # Reducido para menos empuje

var is_open: bool = false
var is_opening: bool = false
var player_nearby: bool = false  # Para controlar si el jugador está cerca
var last_notification_time: float = 0.0  # Tiempo de la última notificación
var notification_cooldown: float = 2.0  # 2 segundos entre notificaciones

@onready var area: Area3D = %Area3D
@onready var animatable_body: AnimatableBody3D = %AnimatableBody3D

var start_pos: Vector3
var target_pos: Vector3

func _ready():
	print("🚪 Door: Inicializando...")
	
	if not animatable_body:
		push_error("⚠️ Door: No se encontró AnimatableBody3D!")
		return
	
	if not area:
		push_error("⚠️ Door: No se encontró Area3D!")
		return
	
	# IMPORTANTE: Configurar el AnimatableBody3D para movimiento por código
	animatable_body.sync_to_physics = false  # Desactivar sincronización automática
	
	# Configurar Area3D
	area.monitoring = true
	area.monitorable = true
	
	start_pos = global_position
	target_pos = start_pos - Vector3(0, open_distance, 0)
	
	# Conectar señales
	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)
	
	if not area.body_exited.is_connected(_on_body_exited):
		area.body_exited.connect(_on_body_exited)
	
	print("✅ Door: Lista en posición ", start_pos)

func _on_body_entered(body: Node):
	if is_open or is_opening:
		return
	
	if not body.is_in_group("player"):
		return
	
	player_nearby = true
	
	if not body.has_method("use_key"):
		return
	
	if body.use_key():
		is_opening = true
		print("🔓 Door: Llave usada, iniciando secuencia...")
		
		# Mostrar notificación mejorada (sin emojis)
		if body.has_method("show_notification"):
			body.show_notification("Puerta abierta! (usaste una llave)")
		
		_shake_and_open()
	else:
		var current_time = Time.get_unix_time_from_system()
		
		# Verificar cooldown para evitar spam
		if current_time - last_notification_time >= notification_cooldown:
			last_notification_time = current_time
			print("⛔ Necesitas una llave para abrir esta puerta.")
			
			# Notificación con cooldown
			if body.has_method("show_notification"):
				body.show_notification("Necesitas una llave!")

func _on_body_exited(body: Node):
	if body.is_in_group("player"):
		player_nearby = false
			
func _shake_and_open():
	# Desactivar el área de forma segura (deferred)
	area.set_deferred("monitoring", false)
	
	print("🔔 Door: Temblando...")
	
	# === FASE 1: TEMBLOR CON COLISIÓN REDUCIDA ===
	# Reducir temporalmente la intensidad de colisión
	# Mover solo el mesh visualmente, no todo el body
	var mesh_instance = animatable_body.get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		for child in animatable_body.get_children():
			if child is MeshInstance3D:
				mesh_instance = child
				break
	
	if mesh_instance:
		var original_mesh_pos = mesh_instance.position
		var shake_count = int(shake_duration * 15)
		
		for i in range(shake_count):
			var offset_x = randf_range(-shake_intensity, shake_intensity)
			var offset_z = randf_range(-shake_intensity, shake_intensity)
			var offset_rot = randf_range(-0.03, 0.03)
			
			# Solo mover el mesh, NO el AnimatableBody completo
			mesh_instance.position = original_mesh_pos + Vector3(offset_x, 0, offset_z)
			mesh_instance.rotation.y = offset_rot
			
			await get_tree().create_timer(shake_duration / shake_count).timeout
		
		# Resetear mesh
		mesh_instance.position = original_mesh_pos
		mesh_instance.rotation = Vector3.ZERO
	else:
		# Fallback: esperar el tiempo del temblor
		await get_tree().create_timer(shake_duration).timeout
	
	print("⬇️ Door: Bajando...")
	
	# AHORA desactivar colisión para que baje sin problemas
	if animatable_body:
		animatable_body.collision_layer = 0
		animatable_body.collision_mask = 0
	
	# === FASE 2: BAJAR ===
	var open_tween = create_tween()
	open_tween.set_ease(Tween.EASE_IN)
	open_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Animar la bajada
	open_tween.tween_property(
		self, 
		"global_position:y", 
		target_pos.y, 
		open_distance / open_speed
	)
	
	# Cuando termine de bajar
	open_tween.finished.connect(func():
		is_open = true
		is_opening = false
		print("✅ Door: Completamente abierta en Y:", global_position.y)
		
		# === FASE 3: DESAPARECER ===
		_fade_and_free()
	)

func _fade_and_free():
	print("👻 Door: Desapareciendo para ahorrar recursos...")
	
	# Hacer invisible inmediatamente para evitar que se vea
	visible = false
	
	# Esperar un frame para asegurar que todo está procesado
	await get_tree().process_frame
	
	# Eliminar directamente
	print("🗑️ Door: Liberada de memoria")
	queue_free()
