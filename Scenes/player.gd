extends CharacterBody3D

# --- CONFIGURACIÓN ---
@export_group("Movement")
@export var move_speed: float = 1.0
@export var jump_speed: float = 2.0
@export var gravity_multiplier: float = 1.0

@export_group("Combat")
@export var attack_damage: int = 10
@export var attack_movement_multiplier: float = 0.6
@export var attack_hit_delay: float = 0.1

@export_group("Health")
@export var max_health: float = 30.0 # 3 contenedores x 10 HP cada uno
var current_health: float

@export_group("Roll")
@export var roll_speed: float = 4.0
@export var roll_duration: float = 0.4
@export var roll_cooldown: float = 0.2

# --- ESTADOS (FSM) ---
enum State { NORMAL, ATTACKING, ROLLING, DAMAGE }
var current_state: State = State.NORMAL

# --- VARIABLES INTERNAS ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_facing_right = true
var attack_combo_step = 0
var input_buffer = ""
var enemies_hit = []
var damage_knockback_timer = Timer.new()
var ui_ref: CanvasLayer = null

# Los timers de daño se mantienen, pero la lógica de uso cambia:
var damage_visual_timer = Timer.new() # Controla solo la duración de la invulnerabilidad (1.0s)

var is_invulnerable: bool = false
@export var invulnerability_time: float = 1.0 # El tiempo que dura la invulnerabilidad (1.0s)
@export var damage_visual_time: float = 0.5 # **NUEVA VARIABLE:** El tiempo que dura el efecto de color (0.5s)

@onready var animated_sprite = $Sprite3D
@onready var attack_area = $AttackArea
@onready var attack_collision = $AttackArea/CollisionShape3D
@onready var roll_cooldown_timer: Timer = Timer.new()

func _ready():
	current_health = max_health
	attack_collision.disabled = true
	
	add_to_group("player")
	
	add_child(roll_cooldown_timer)
	roll_cooldown_timer.one_shot = true
	
	# Configuración del temporizador de knockback
	add_child(damage_knockback_timer)
	damage_knockback_timer.one_shot = true
	damage_knockback_timer.timeout.connect(func():
		if current_state == State.DAMAGE:
			velocity = Vector3.ZERO
			# Retorna al estado NORMAL después de que el knockback termine
			call_deferred("set_state", State.NORMAL) 
	)
	
	# Configuración del temporizador de invulnerabilidad (ahora SÓLO controla la invulnerabilidad)
	add_child(damage_visual_timer)
	damage_visual_timer.one_shot = true
	damage_visual_timer.timeout.connect(func():
		# **Lógica modificada:** SOLO remueve la invulnerabilidad aquí
		is_invulnerable = false 
	)
	
	animated_sprite.animation_finished.connect(_on_animation_finished)
	if not attack_area.body_entered.is_connected(_on_attack_hit):
		attack_area.body_entered.connect(_on_attack_hit)
	
	call_deferred("_find_ui")

func _physics_process(delta):
	# Lógica de movimiento principal gestionada por la máquina de estados
	match current_state:
		State.NORMAL:
			_handle_move(delta)
			_handle_jump()
			_handle_actions_input()
		State.ATTACKING:
			# Permite el movimiento de inercia del ataque si no hay knockback activo
			if damage_knockback_timer.is_stopped():
				_handle_move(delta, attack_movement_multiplier)
			_handle_buffer_input()
		State.ROLLING:
			_apply_roll_physics()
		State.DAMAGE:
			# El knockback es aplicado en take_damage_hearts_with_knockback.
			pass

	# Aplicar Gravedad
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
	else:
		# Si estamos en DAMAGE y ya aterrizamos/el knockback terminó, resetear Y
		if current_state == State.DAMAGE and damage_knockback_timer.is_stopped():
			velocity.y = 0
			
	move_and_slide()
	_update_animations()

# --- MANEJO DE INPUTS ---
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

# --- LÓGICA DE MOVIMIENTO ---
func _handle_move(_delta: float, speed_mult: float = 1.0):
	# Si el temporizador NO está detenido (es decir, está corriendo),
	# el knockback está en efecto y bloqueamos la entrada de movimiento normal.
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
		var current_vel_xz = Vector3(velocity.x, 0, velocity.z).length()
		if current_vel_xz < roll_speed * 0.95:
			var roll_dir_xz = Vector3(velocity.x, 0, velocity.z).normalized()
			velocity.x = roll_dir_xz.x * roll_speed
			velocity.z = roll_dir_xz.z * roll_speed

func _flip_sprite(_x_velocity: float):
	if _x_velocity == 0: return
	var moving_right = _x_velocity > 0
	if _x_velocity != 0 and moving_right != is_facing_right:
		is_facing_right = moving_right
		animated_sprite.flip_h = not is_facing_right
		attack_area.scale.x = 1.0 if is_facing_right else -1.0

# --- GESTIÓN DE ESTADOS (FSM) ---
func set_state(new_state: State):
	if current_state == State.ATTACKING:
		# **CORRECCIÓN APLICADA: Uso de set_deferred()**
		attack_collision.set_deferred("disabled", true) 
		animated_sprite.speed_scale = 1.0
		
	current_state = new_state
	
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
			
# --- ACCIONES ---
func _start_attack():
	enemies_hit.clear()
	animated_sprite.speed_scale = 2.0
	if attack_combo_step == 0:
		animated_sprite.play("attack")
		attack_combo_step = 1
	else:
		animated_sprite.play_backwards("attack")
		attack_combo_step = 0
	get_tree().create_timer(attack_hit_delay).timeout.connect(_on_hitbox_activate)

func _on_hitbox_activate():
	if current_state != State.ATTACKING: return
	attack_collision.disabled = false
	get_tree().create_timer(0.1).timeout.connect(func(): attack_collision.disabled = true)

func _on_attack_hit(body):
	if attack_collision.disabled: return
	if body.has_method("take_damage") and body != self and not body in enemies_hit:
		enemies_hit.append(body)
		body.take_damage(attack_damage)

func _start_roll():
	is_invulnerable = true
	input_buffer = ""
	animated_sprite.speed_scale = 2.0
	if animated_sprite.sprite_frames.has_animation("roll"):
		animated_sprite.play("roll")
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var roll_dir = Vector3.ZERO
	
	if input_dir.length() > 0:
		roll_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	else:
		roll_dir = Vector3(1 if is_facing_right else -1, 0, 0)
		
	velocity.x = roll_dir.x * roll_speed
	velocity.z = roll_dir.z * roll_speed
	
	if not animated_sprite.sprite_frames.has_animation("roll"):
		var roll_timer = get_tree().create_timer(roll_duration)
		roll_timer.timeout.connect(func():
			is_invulnerable = false
			roll_cooldown_timer.start(roll_cooldown)
			set_state(State.NORMAL)
		)

func _start_damage():
	is_invulnerable = true 
	
	# 1. Iniciar el temporizador de invulnerabilidad (1.0s)
	damage_visual_timer.start(invulnerability_time) 
	
	# 2. Iniciar el efecto visual (color rojo/parpadeo) (0.5s)
	animated_sprite.modulate = Color(1, 0.5, 0.5, 1) # Efecto de color
	
	# Usar un timer one-shot anónimo para limpiar el color después de 0.5s
	get_tree().create_timer(damage_visual_time).timeout.connect(func():
		# Solo limpia el color si la invulnerabilidad aún está activa
		if is_invulnerable:
			animated_sprite.modulate = Color.WHITE
	)

# --- SISTEMA DE SALUD Y DAÑO ---

func take_damage_hearts(damage_amount: float):
	take_damage_hearts_with_knockback(damage_amount, Vector3.ZERO, 0.0)

func take_damage_hearts_with_knockback(damage_amount: float, knockback_direction: Vector3, knockback_force: float):
	if current_state == State.ROLLING or is_invulnerable:
		print("🛡️ Player: Daño bloqueado por roll o invulnerabilidad.")
		return
	
	current_health -= damage_amount
	current_health = max(0, current_health) # No bajar de 0
	
	print("💔 Player: Recibió %.1f de daño. HP: %.1f/%.1f" % [damage_amount, current_health, max_health])
	
	# 1. Aplicar el estado de daño de forma inmediata.
	if current_state != State.DAMAGE:
		set_state(State.DAMAGE)
	
	# 2. Actualizar UI
	if ui_ref and ui_ref.has_method("update_hearts_display"):
		ui_ref.update_hearts_display()
	
	# 3. Aplicar knockback.
	if knockback_force > 0:
		var KB_MULTIPLIER = 5.0
		# Solo aplicamos velocidad si el timer de knockback no está corriendo.
		if damage_knockback_timer.is_stopped():
			velocity.x = knockback_direction.x * knockback_force * KB_MULTIPLIER
			velocity.z = knockback_direction.z * knockback_force * KB_MULTIPLIER
			# Añadir un pequeño impulso vertical para un mejor efecto
			velocity.y = min(velocity.y + knockback_force * 3.0, 5.0)
		
		# Iniciar timer para finalizar el knockback y regresar a NORMAL
		damage_knockback_timer.start(0.35)
	else:
		# Si no hay knockback, sal del estado DAMAGE rápidamente.
		damage_knockback_timer.start(0.1)
	
	if current_health <= 0:
		die()

# --- FUNCIONES DE CURACIÓN Y SALUD ---

func heal(amount: float):
	if current_health < max_health:
		current_health += amount
		if current_health > max_health:
			current_health = max_health
			
		print("💚 Player: Curado %.1f HP. Total: %.1f/%.1f" % [amount, current_health, max_health])
		
		if ui_ref and ui_ref.has_method("update_hearts_display"):
			ui_ref.update_hearts_display()

func increase_max_health(amount: float):
	max_health += amount
	current_health = max_health # Curar al máximo
	
	print("💚 Player: Max HP aumentado a %.1f" % max_health)
	
	if ui_ref and ui_ref.has_method("update_max_hearts_display"):
		ui_ref.update_max_hearts_display()

func die():
	print("💀 Player: ¡Has muerto!")
	get_tree().call_deferred("reload_current_scene")

# --- ANIMACIONES Y EVENTOS ---
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
		is_invulnerable = false # Final de la invulnerabilidad de roll
		roll_cooldown_timer.start(roll_cooldown)
		set_state(State.NORMAL)

func _find_ui():
	ui_ref = get_tree().get_first_node_in_group("ui")
	if not ui_ref:
		for child in get_tree().root.get_children():
			if child.name == "Player_UI" or child is CanvasLayer:
				ui_ref = child
				break
	if not ui_ref:
		var canvas_layers = get_tree().get_nodes_in_group("ui")
		if canvas_layers.size() > 0:
			ui_ref = canvas_layers[0]
			
	if ui_ref:
		print("💚 Player: UI encontrada - ", ui_ref.name)
		if ui_ref.has_method("update_max_hearts_display"):
			ui_ref.update_max_hearts_display()
	else:
		push_warning("⚠️ Player: No se encontró UI. Asegúrate de:")
		push_warning("  1. Añadir Player_UI al grupo 'ui'")
		push_warning("  2. Que Player_UI sea CanvasLayer")
		push_warning("  3. Que la escena esté instanciada correctamente")
