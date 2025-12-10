extends CharacterBody3D

# --- CONFIGURACIÓN ---
@export_group("Movement")
@export var move_speed: float = 5.0
@export var jump_speed: float = 4.5
@export var gravity_multiplier: float = 1.0

@export_group("Combat")
@export var attack_damage: int = 10
@export var attack_movement_multiplier: float = 0.6
@export var attack_hit_delay: float = 0.1 # Tiempo antes de que salga el hitbox

@export_group("Roll")
@export var roll_speed: float = 10.0
@export var roll_duration: float = 0.4
@export var roll_cooldown: float = 0.2

# --- ESTADOS (FSM) ---
enum State { NORMAL, ATTACKING, ROLLING }
var current_state: State = State.NORMAL

# --- VARIABLES INTERNAS ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_facing_right = true
var attack_combo_step = 0 # 0 = forward, 1 = backward (Efecto ping-pong)
var input_buffer = "" # Para encolar acciones (buffer de input: "attack" o "roll")
var enemies_hit = [] # Lista de enemigos golpeados en el ataque actual (Para evitar doble golpe)

@onready var animated_sprite = $Sprite3D
@onready var attack_area = $AttackArea
@onready var attack_collision = $AttackArea/CollisionShape3D
@onready var roll_cooldown_timer: Timer = Timer.new()

func _ready():
	attack_collision.disabled = true
	
	# Configurar Timer para el cooldown del roll
	add_child(roll_cooldown_timer)
	roll_cooldown_timer.one_shot = true
	
	# Conectar señales UNA sola vez
	animated_sprite.animation_finished.connect(_on_animation_finished)
	# Conectar la señal del Area para detectar golpes
	if not attack_area.body_entered.is_connected(_on_attack_hit):
		attack_area.body_entered.connect(_on_attack_hit)

func _physics_process(delta):
	# Aplicar gravedad constante
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta

	# Lógica según estado
	match current_state:
		State.NORMAL:
			_handle_move(delta)
			_handle_jump()
			_handle_actions_input()
		
		State.ATTACKING:
			_handle_move(delta, attack_movement_multiplier)
			_handle_buffer_input()
			
		State.ROLLING:
			_apply_roll_physics()

	move_and_slide()
	_update_animations()

# --- MANEJO DE INPUTS ---

# Maneja inputs en estado NORMAL
func _handle_actions_input():
	if Input.is_action_just_pressed("attack"):
		set_state(State.ATTACKING)
	elif Input.is_action_just_pressed("roll") and roll_cooldown_timer.is_stopped():
		set_state(State.ROLLING)

# Maneja inputs mientras ATACA (para encolar la siguiente acción)
func _handle_buffer_input():
	if Input.is_action_just_pressed("attack"):
		input_buffer = "attack"
	elif Input.is_action_just_pressed("roll"):
		input_buffer = "roll"
		# Prioridad al roll: cancela el ataque inmediatamente
		set_state(State.ROLLING)

# --- LÓGICA DE MOVIMIENTO ---

func _handle_move(_delta, speed_mult: float = 1.0):
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
	# La velocidad ya fue calculada en _start_roll(), solo dejamos que move_and_slide() actúe.
	pass

func _flip_sprite(x_velocity: float):
	# Si no hay input de movimiento y la velocidad es cero, salimos.
	if x_velocity == 0: 
		if velocity.x == 0 and velocity.z == 0:
			return
	
	var moving_right = x_velocity > 0
	
	# Solo cambiar si la dirección de movimiento es diferente a la dirección actual.
	if x_velocity != 0 and moving_right != is_facing_right:
		is_facing_right = moving_right
		
		# 1. Voltear el sprite visual
		animated_sprite.flip_h = not is_facing_right
		
		# 2. Voltear el AttackArea y su CollisionShape (CORRECCIÓN CLAVE)
		# Esto hace que el área de golpe se refleje del lado derecho al izquierdo.
		attack_area.scale.x = 1.0 if is_facing_right else -1.0 

# --- GESTIÓN DE ESTADOS (FSM) ---

func set_state(new_state: State):
	# Salida del estado anterior (Cleanup)
	if current_state == State.ATTACKING:
		attack_collision.disabled = true
		animated_sprite.speed_scale = 1.0
		
	current_state = new_state
	
	# Entrada al nuevo estado (Setup)
	match new_state:
		State.NORMAL:
			# Revisar Buffer al volver a normal
			if input_buffer == "attack":
				input_buffer = ""
				set_state(State.ATTACKING)
			elif input_buffer == "roll" and roll_cooldown_timer.is_stopped():
				input_buffer = ""
				set_state(State.ROLLING)
				
		State.ATTACKING:
			_start_attack()
			
		State.ROLLING:
			input_buffer = "" # Limpiar buffer al rodar
			_start_roll()

# --- ACCIONES ---

func _start_attack():
	enemies_hit.clear() # Limpiamos la lista de golpeados al iniciar un nuevo ataque
	animated_sprite.speed_scale = 2.0
	
	# Lógica Ping-Pong del Combo
	if attack_combo_step == 0:
		animated_sprite.play("attack")
		attack_combo_step = 1
	else:
		animated_sprite.play_backwards("attack")
		attack_combo_step = 0
		
	# Retraso para que el hitbox coincida con el frame de golpe
	get_tree().create_timer(attack_hit_delay).timeout.connect(_on_hitbox_activate)

func _on_hitbox_activate():
	# Seguridad: si ya no estoy atacando, no activar.
	if current_state != State.ATTACKING:
		return
		
	# Activamos el hitbox. La señal _on_attack_hit hará el daño.
	attack_collision.disabled = false
	
	# Apagar el hitbox después de un momento breve
	get_tree().create_timer(0.1).timeout.connect(func(): attack_collision.disabled = true)

# --- FUNCIÓN CLAVE (SEÑAL DE DAÑO) ---

func _on_attack_hit(body):
	# Verificaciones de seguridad (si está deshabilitado, si no es un enemigo, si ya lo golpeé)
	if attack_collision.disabled: return
	
	if body.has_method("take_damage") and body != self and not body in enemies_hit:
		# Registrar golpe para evitar doble daño
		enemies_hit.append(body)
		
		# Aplicar daño
		body.take_damage(attack_damage)
		print("¡Golpe infligido a: ", body.name, "!")

# --- ROLL ---

func _start_roll():
	animated_sprite.speed_scale = 2.0
	
	if animated_sprite.sprite_frames.has_animation("roll"):
		animated_sprite.play("roll")
		
	# Calcular dirección del roll
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var roll_dir = Vector3.ZERO
	
	if input_dir.length() > 0:
		roll_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	else:
		# Roll hacia donde mira (ajustado para el flip_h)
		roll_dir = Vector3(1 if is_facing_right else -1, 0, 0)
		
	velocity.x = roll_dir.x * roll_speed
	velocity.z = roll_dir.z * roll_speed
	
	# Si no hay animación de roll, usamos un timer como respaldo
	if not animated_sprite.sprite_frames.has_animation("roll"):
		get_tree().create_timer(roll_duration).timeout.connect(func(): set_state(State.NORMAL))

# --- ANIMACIONES Y EVENTOS ---

func _update_animations():
	if current_state != State.NORMAL: return # El estado maneja su propia animación
	
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
		# Al terminar ataque, vuelve al estado NORMAL (donde checa el buffer)
		set_state(State.NORMAL)
	elif animated_sprite.animation == "roll":
		# Al terminar roll, empieza el cooldown y vuelve a NORMAL
		roll_cooldown_timer.start(roll_cooldown)
		set_state(State.NORMAL)
