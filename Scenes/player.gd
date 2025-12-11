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
@export var max_health: float = 30.0  # 3 contenedores x 10 HP cada uno
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
	
	add_child(damage_knockback_timer)
	damage_knockback_timer.one_shot = true
	damage_knockback_timer.timeout.connect(func(): 
		if current_state == State.DAMAGE: 
			set_state(State.NORMAL)
	)
	
	animated_sprite.animation_finished.connect(_on_animation_finished)
	if not attack_area.body_entered.is_connected(_on_attack_hit):
		attack_area.body_entered.connect(_on_attack_hit)
	
	# Buscar UI con múltiples métodos
	call_deferred("_find_ui")

func _physics_process(delta):
	if current_state == State.DAMAGE:
		pass
	else:
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

	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
		
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
		set_state(State.ROLLING)

# --- LÓGICA DE MOVIMIENTO ---
func _handle_move(_delta: float, speed_mult: float = 1.0):
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
	pass

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
		attack_collision.disabled = true
		animated_sprite.speed_scale = 1.0
		
	current_state = new_state
	
	match new_state:
		State.NORMAL:
			if input_buffer == "attack":
				input_buffer = ""
				set_state(State.ATTACKING)
			elif input_buffer == "roll" and roll_cooldown_timer.is_stopped():
				input_buffer = ""
				set_state(State.ROLLING)
		State.ATTACKING:
			_start_attack()
		State.ROLLING:
			input_buffer = ""
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
		get_tree().create_timer(roll_duration).timeout.connect(func(): set_state(State.NORMAL))

func _start_damage():
	velocity = Vector3.ZERO
	animated_sprite.modulate = Color(1, 0.5, 0.5, 1) 
	get_tree().create_timer(0.2).timeout.connect(func():
		animated_sprite.modulate = Color.WHITE
		if current_state == State.DAMAGE:
			set_state(State.NORMAL)
	)

# --- SISTEMA DE SALUD Y DAÑO ---

func take_damage_hearts(damage_amount: float):
	take_damage_hearts_with_knockback(damage_amount, Vector3.ZERO, 0.0)

func take_damage_hearts_with_knockback(damage_amount: float, knockback_direction: Vector3, knockback_force: float):
	if current_state == State.ROLLING: 
		print("🛡️ Player: Daño bloqueado por roll")
		return 
	
	current_health -= damage_amount
	current_health = max(0, current_health)  # No bajar de 0
	
	print("💔 Player: Recibió %.1f de daño. HP: %.1f/%.1f" % [damage_amount, current_health, max_health])
	
	set_state(State.DAMAGE)
	
	# Actualizar UI
	if ui_ref and ui_ref.has_method("update_hearts_display"):
		ui_ref.update_hearts_display()
	
	# Aplicar knockback
	if knockback_force > 0:
		var KB_MULTIPLIER = 10.0 
		velocity.x = knockback_direction.x * knockback_force * KB_MULTIPLIER
		velocity.z = knockback_direction.z * knockback_force * KB_MULTIPLIER
		damage_knockback_timer.start(0.1) 
	
	if current_health <= 0:
		die()

# --- FUNCIONES DE CURACIÓN ---

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
	current_health = max_health  # Curar al máximo
	
	print("💚 Player: Max HP aumentado a %.1f" % max_health)
	
	if ui_ref and ui_ref.has_method("update_max_hearts_display"):
		ui_ref.update_max_hearts_display()

func die():
	print("💀 Player: ¡Has muerto!")
	# Usar call_deferred para evitar el error de física
	get_tree().call_deferred("reload_current_scene")

# --- ANIMACIONES Y EVENTOS ---
func _update_animations():
	if current_state != State.NORMAL: return
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
		roll_cooldown_timer.start(roll_cooldown)
		set_state(State.NORMAL)

func _find_ui():
	"""Buscar la UI de forma segura después de que todo esté cargado"""
	# Método 1: Por grupo
	ui_ref = get_tree().get_first_node_in_group("ui")
	
	# Método 2: Por nombre exacto en la raíz
	if not ui_ref:
		for child in get_tree().root.get_children():
			if child.name == "Player_UI" or child is CanvasLayer:
				ui_ref = child
				break
	
	# Método 3: Buscar cualquier CanvasLayer con el script correcto
	if not ui_ref:
		var canvas_layers = get_tree().get_nodes_in_group("ui")
		if canvas_layers.size() > 0:
			ui_ref = canvas_layers[0]
	
	if ui_ref:
		print("💚 Player: UI encontrada - ", ui_ref.name)
		# Actualizar UI inmediatamente
		if ui_ref.has_method("update_max_hearts_display"):
			ui_ref.update_max_hearts_display()
	else:
		push_warning("⚠️ Player: No se encontró UI. Asegúrate de:")
		push_warning("  1. Añadir Player_UI al grupo 'ui'")
		push_warning("  2. Que Player_UI sea CanvasLayer")
		push_warning("  3. Que la escena esté instanciada correctamente")
