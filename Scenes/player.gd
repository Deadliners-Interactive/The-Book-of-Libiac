extends CharacterBody3D

# ==============================================================================
# --- CONFIGURACIÓN ---
# ==============================================================================
@export_group("Movement")
@export var move_speed: float = 1.0
@export var jump_speed: float = 2.0
@export var gravity_multiplier: float = 1.0

@export_group("Combat")
@export var attack_damage: int = 10
@export var attack_movement_multiplier: float = 0.6
@export var attack_hit_delay: float = 0.1

@export_group("Health")
@export var max_health: float = 30.0
var current_health: float

@export_group("Roll")
@export var roll_speed: float = 3.0
@export var roll_duration: float = 0.4
@export var roll_cooldown: float = 0.2

# ==============================================================================
# --- ESTADOS (FSM) ---
# ==============================================================================
enum State { NORMAL, ATTACKING, ROLLING, DAMAGE }
var current_state: State = State.NORMAL

# ==============================================================================
# --- VARIABLES INTERNAS ---
# ==============================================================================
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_facing_right = true
var attack_combo_step = 0
var input_buffer = ""
var enemies_hit = []
var damage_knockback_timer = Timer.new()
var ui_ref: CanvasLayer = null

# Sistema de invulnerabilidad
var damage_visual_timer = Timer.new()
var is_invulnerable: bool = false
@export var invulnerability_time: float = 1.0
@export var damage_visual_time: float = 0.5

# Sistema de prevención de notificaciones repetidas
var notification_cooldown: Dictionary = {}
var notification_cooldown_time: float = 1.0  # 1 segundo de cooldown

# Referencias a Nodos
@onready var animated_sprite = $Sprite3D
@onready var attack_area = $AttackArea
@onready var attack_collision = $AttackArea/CollisionShape3D
@onready var roll_cooldown_timer: Timer = Timer.new()
@onready var detection_area = $DetectionArea  # NUEVO: Para detectar triggers de nivel

# ==============================================================================
# --- INICIALIZACIÓN ---
# ==============================================================================
func _ready():
	current_health = max_health
	attack_collision.disabled = true
	
	# --- GRUPOS IMPORTANTES ---
	add_to_group("player") # El cuerpo del player
	
	# Añadimos el área de la espada al grupo que busca el cofre
	attack_area.add_to_group("hitbox_player") 
	
	# Configuración de Timers
	add_child(roll_cooldown_timer)
	roll_cooldown_timer.one_shot = true
	
	add_child(damage_knockback_timer)
	damage_knockback_timer.one_shot = true
	damage_knockback_timer.timeout.connect(func():
		if current_state == State.DAMAGE:
			velocity = Vector3.ZERO
			call_deferred("set_state", State.NORMAL) 
	)
	
	add_child(damage_visual_timer)
	damage_visual_timer.one_shot = true
	damage_visual_timer.timeout.connect(func():
		is_invulnerable = false 
	)
	
	# Señales
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
	if not attack_area.body_entered.is_connected(_on_attack_hit):
		attack_area.body_entered.connect(_on_attack_hit)
	
	# ============ SISTEMA DE CAMBIO DE NIVEL ============
	# Cargar estado guardado si existe
	if GameState.player_health > 0:
		GameState.load_player_state(self)
	
	# Conectar señal para detectar áreas desde el Area3D hijo
	if has_node("DetectionArea"):
		detection_area.area_entered.connect(_on_area_entered_player)
	else:
		push_warning("⚠️ Player: Falta nodo DetectionArea para cambio de nivel")
	# ====================================================
	
	# Buscar UI al inicio
	call_deferred("_find_ui")

func _physics_process(delta):
	match current_state:
		State.NORMAL:
			_handle_move(delta)
			_handle_jump()
			_handle_actions_input()
		State.ATTACKING:
			if damage_knockback_timer.is_stopped():
				_handle_move(delta, attack_movement_multiplier)
			_handle_buffer_input()
		State.ROLLING:
			_apply_roll_physics()
		State.DAMAGE:
			pass # Knockback controlado por timer

	# Gravedad
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
	else:
		if current_state == State.DAMAGE and damage_knockback_timer.is_stopped():
			velocity.y = 0
	
	move_and_slide()
	_update_animations()

# ==============================================================================
# --- MANEJO DE INPUTS ---
# ==============================================================================

func _handle_actions_input():
	if Input.is_action_just_pressed("attack"):
		set_state(State.ATTACKING)
	elif Input.is_action_just_pressed("roll") and roll_cooldown_timer.is_stopped():
		set_state(State.ROLLING)

func _handle_buffer_input():
	if Input.is_action_just_pressed("attack"):
		input_buffer = "attack"
	elif Input.is_action_just_pressed("roll"):
		input_buffer = "roll"
		if roll_cooldown_timer.is_stopped():
			set_state(State.ROLLING)

# ==============================================================================
# --- LÓGICA DE MOVIMIENTO ---
# ==============================================================================

func _handle_move(_delta: float, speed_mult: float = 1.0):
	if not damage_knockback_timer.is_stopped(): 
		return

	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var final_speed = move_speed * speed_mult
	
	if direction:
		velocity.x = direction.x * final_speed
		velocity.z = direction.z * final_speed
		_flip_sprite(velocity.x)
	else:
		velocity.x = move_toward(velocity.x, 0, final_speed)
		velocity.z = move_toward(velocity.z, 0, final_speed)

func _handle_jump():
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_speed

func _apply_roll_physics():
	if current_state == State.ROLLING:
		# Aseguramos que ruede aunque estuviera quieto (hacia donde mira)
		var current_vel_xz = Vector3(velocity.x, 0, velocity.z).length()
		
		if current_vel_xz < 0.1:
			# Si estaba quieto, forzar velocidad en dirección de la mirada
			var facing_dir = 1.0 if is_facing_right else -1.0
			velocity.x = facing_dir * roll_speed
			velocity.z = 0
		else:
			# Mantener dirección actual pero a velocidad de roll
			var roll_dir_xz = Vector3(velocity.x, 0, velocity.z).normalized()
			velocity.x = roll_dir_xz.x * roll_speed
			velocity.z = roll_dir_xz.z * roll_speed

func _flip_sprite(_x_velocity: float):
	if abs(_x_velocity) < 0.1: return
	
	var moving_right = _x_velocity > 0
	if moving_right != is_facing_right:
		is_facing_right = moving_right
		animated_sprite.flip_h = not is_facing_right
		
		# Ajustar hitbox de ataque si es necesario (si tiene offset)
		attack_area.scale.x = 1.0 if is_facing_right else -1.0

# ==============================================================================
# --- GESTIÓN DE ESTADOS (FSM) ---
# ==============================================================================

func set_state(new_state: State):
	# Salir del estado anterior
	if current_state == State.ATTACKING:
		# Usamos set_deferred para evitar errores de físicas
		attack_collision.set_deferred("disabled", true) 
		animated_sprite.speed_scale = 1.0
		
	current_state = new_state
	
	# Entrar al nuevo estado
	match new_state:
		State.NORMAL:
			if damage_knockback_timer.is_stopped():
				if input_buffer == "attack":
					input_buffer = ""
					set_state(State.ATTACKING)
				elif input_buffer == "roll" and roll_cooldown_timer.is_stopped():
					input_buffer = ""
					set_state(State.ROLLING)
		State.ATTACKING:
			_start_attack()
		State.ROLLING:
			_start_roll()
		State.DAMAGE:
			_start_damage()

# ==============================================================================
# --- ACCIONES DE COMBATE ---
# ==============================================================================

func _start_attack():
	enemies_hit.clear()
	animated_sprite.speed_scale = 2.0 # Ataque más rápido visualmente
	
	if attack_combo_step == 0:
		animated_sprite.play("attack")
		attack_combo_step = 1
	else:
		animated_sprite.play_backwards("attack") # Combo simple alternando animación
		attack_combo_step = 0
	
	# Activar hitbox con delay para coincidir con la animación
	get_tree().create_timer(attack_hit_delay).timeout.connect(_on_hitbox_activate)

func _on_hitbox_activate():
	if current_state != State.ATTACKING: return
	
	# [CORRECCIÓN] Usar set_deferred es vital para evitar errores
	attack_collision.set_deferred("disabled", false)
	
	# Desactivar hitbox automáticamente tras un instante
	get_tree().create_timer(0.15).timeout.connect(func(): 
		if current_state == State.ATTACKING:
			attack_collision.set_deferred("disabled", true)
	)

func _on_attack_hit(body):
	# Si la colisión está deshabilitada lógicamente, ignorar
	if attack_collision.disabled: return
	
	# Evitar golpearse a sí mismo y golpear dos veces al mismo enemigo
	if body.has_method("take_damage") and body != self and not body in enemies_hit:
		enemies_hit.append(body)
		body.take_damage(attack_damage)
		# Aquí podrías añadir un efecto de sonido o partículas de golpe

func _start_roll():
	is_invulnerable = true
	input_buffer = ""
	animated_sprite.speed_scale = 2.0
	
	if animated_sprite.sprite_frames.has_animation("roll"):
		animated_sprite.play("roll")
	
	# Si no hay animación de roll, usamos un timer
	if not animated_sprite.sprite_frames.has_animation("roll"):
		var roll_timer = get_tree().create_timer(roll_duration)
		roll_timer.timeout.connect(func():
			is_invulnerable = false
			roll_cooldown_timer.start(roll_cooldown)
			set_state(State.NORMAL)
		)

func _start_damage():
	is_invulnerable = true 
	damage_visual_timer.start(invulnerability_time) 
	animated_sprite.modulate = Color(1, 0.5, 0.5, 1) # Rojo claro
	
	get_tree().create_timer(damage_visual_time).timeout.connect(func():
		if is_invulnerable:
			animated_sprite.modulate = Color.WHITE
	)

# ==============================================================================
# --- SISTEMA DE SALUD Y DAÑO ---
# ==============================================================================

func take_damage_hearts(damage_amount: float):
	take_damage_hearts_with_knockback(damage_amount, Vector3.ZERO, 0.0)

func take_damage_hearts_with_knockback(damage_amount: float, knockback_direction: Vector3, knockback_force: float):
	if current_state == State.ROLLING or is_invulnerable:
		# print("🛡️ Player: Daño bloqueado.")
		return
	
	current_health -= damage_amount
	current_health = max(0, current_health)
	
	# print("💔 Player: Recibió daño. HP: ", current_health)
	
	if current_state != State.DAMAGE:
		set_state(State.DAMAGE)
	
	if ui_ref and ui_ref.has_method("update_hearts_display"):
		ui_ref.update_hearts_display()
	
	# Aplicar empuje (Knockback)
	if knockback_force > 0:
		var KB_MULTIPLIER = 5.0
		if damage_knockback_timer.is_stopped():
			velocity.x = knockback_direction.x * knockback_force * KB_MULTIPLIER
			velocity.z = knockback_direction.z * knockback_force * KB_MULTIPLIER
			velocity.y = min(velocity.y + knockback_force * 3.0, 5.0)
		
		damage_knockback_timer.start(0.35)
	else:
		damage_knockback_timer.start(0.1)
	
	if current_health <= 0:
		die()

# ==============================================================================
# --- FUNCIONES DE CURACIÓN Y VIDA ---
# ==============================================================================

func heal(amount: float):
	if current_health < max_health:
		var previous_health = current_health
		current_health += amount
		
		# Asegurar que no exceda el máximo
		if current_health > max_health:
			current_health = max_health
		
		# Calcular cuántos corazones completos se curaron
		# Cada corazón es 10 HP, así que calculamos cuántos corazones completos
		var actual_heal = current_health - previous_health
		var heart_containers = floor(actual_heal / 10.0)
		
		# CORRECCIÓN: Usar fmod() en lugar del operador %
		var partial_heart = fmod(actual_heal, 10.0)
		
		print("💚 Player: Curado. Total: ", current_health)
		
		# Mostrar notificación temática de curación
		if actual_heal > 0:
			if heart_containers >= 1:
				show_notification("Recuperaste %d pluma(s) de vida" % heart_containers)
			elif partial_heart > 0:
				show_notification("Medio corazon recuperado")
		
		if ui_ref and ui_ref.has_method("update_hearts_display"):
			ui_ref.update_hearts_display()

func increase_max_health(amount: float):
	max_health += amount
	current_health = max_health
	
	# Calcular cuántos corazones extra se obtuvieron
	var extra_hearts = amount / 10.0
	
	# Mostrar notificación temática de vida extra
	show_notification("Obtuviste una vida extra!")
	
	if ui_ref and ui_ref.has_method("update_max_hearts_display"):
		ui_ref.update_max_hearts_display()

func die():
	print("💀 Player: ¡Has muerto!")
	# Reiniciar escena
	get_tree().call_deferred("reload_current_scene")

# ==============================================================================
# --- ANIMACIONES Y EVENTOS ---
# ==============================================================================

func _update_animations():
	if current_state in [State.ATTACKING, State.ROLLING, State.DAMAGE]: 
		return
		
	if not is_on_floor():
		animated_sprite.speed_scale = 2.0
		if velocity.y > 0: animated_sprite.play("jump")
		else: animated_sprite.play("fall")
		return
		
	animated_sprite.speed_scale = 1.0
	if velocity.x != 0 or velocity.z != 0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

func _on_animation_finished():
	if animated_sprite.animation == "attack":
		set_state(State.NORMAL)
	elif animated_sprite.animation == "roll":
		is_invulnerable = false
		roll_cooldown_timer.start(roll_cooldown)
		set_state(State.NORMAL)

func _find_ui():
	# Intenta encontrar UI por grupo
	ui_ref = get_tree().get_first_node_in_group("ui")
	
	# Fallback: buscar hijo directo en root
	if not ui_ref:
		for child in get_tree().root.get_children():
			if child.name == "Player_UI" or child is CanvasLayer:
				ui_ref = child
				break
				
	if ui_ref:
		print("💚 Player: UI encontrada - ", ui_ref.name)
		if ui_ref.has_method("update_max_hearts_display"):
			ui_ref.update_max_hearts_display()
	else:
		push_warning("⚠️ Player: No se encontró UI.")

# ==============================================================================
# --- SISTEMA DE LLAVES ---
# ==============================================================================

var key_count: int = 0

func add_key():
	key_count += 1
	print("🔑 Player: Llaves =", key_count)
	
	# Mostrar notificación temática de llave conseguida
	show_notification("Llave conseguida (%d)" % key_count)
	
	if ui_ref and ui_ref.has_method("update_keys_display"):
		ui_ref.update_keys_display()

func use_key() -> bool:
	if key_count > 0:
		key_count -= 1
		print("🚪 Player: Usó llave. Restantes =", key_count)
		
		# IMPORTANTE: NO mostramos notificación aquí porque la puerta lo hará
		# Solo actualizamos la UI silenciosamente
		
		if ui_ref and ui_ref.has_method("update_keys_display"):
			ui_ref.update_keys_display()
		return true
	else:
		# Mostrar notificación temática cuando no tiene llaves (con cooldown)
		show_notification("Necesitas una llave!")
		return false

# ==============================================================================
# --- FUNCIONES DE NOTIFICACIONES (CON COOLDOWN) ---
# ==============================================================================

func show_notification(message: String):
	var current_time = Time.get_ticks_msec()
	
	# Verificar si esta notificación está en cooldown
	if notification_cooldown.has(message):
		var last_shown_time = notification_cooldown[message]
		if current_time - last_shown_time < notification_cooldown_time * 1000:
			# Aún está en cooldown, no mostrar
			return
	
	# Actualizar el tiempo de la última notificación
	notification_cooldown[message] = current_time
	
	# Mostrar la notificación
	if ui_ref and ui_ref.has_method("show_notification"):
		ui_ref.show_notification(message)
	else:
		print("📢 (UI no disponible): ", message)

func show_immediate_notification(message: String):
	if ui_ref and ui_ref.has_method("show_immediate_notification"):
		ui_ref.show_immediate_notification(message)
	else:
		print("📢 (UI no disponible): ", message)

# ==============================================================================
# --- SISTEMA DE CAMBIO DE NIVEL ---
# ==============================================================================

func _on_area_entered_player(area: Area3D):
	"""Detecta cuando el jugador entra en un Area3D"""
	if area.is_in_group("level_trigger"):
		print("🚪 Player: Entrando a zona de cambio de nivel")
		if area.has_method("trigger_level_change"):
			area.trigger_level_change(self)
