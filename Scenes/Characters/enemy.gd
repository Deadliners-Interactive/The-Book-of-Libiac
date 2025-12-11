extends CharacterBody3D

# --- CONFIGURACIÓN DEL ENEMIGO ---
@export_group("Enemy Stats")
@export var max_hp: int = 30
@export var defense: int = 0
@export var move_speed: float = 0.3
@export var gravity_multiplier: float = 1.0

@export_group("Chaser Behavior")
@export var chase_speed: float = 0.3
@export var pursuit_speed: float = 0.6
@export var stalk_speed: float = 0.1
@export var approach_jump_force: float = 5.0  # Fuerza del salto de ataque
@export var retreat_jump_force: float = 3.0   # Fuerza del salto de retroceso
@export var retreat_speed_mult: float = 1.5
@export var safe_distance: float = 1.0
@export var melee_range: float = 0.2
@export var retreat_distance: float = 0.5
@export var retreat_duration: float = 0.15
@export var attack_damage: float = 1.0
@export var attack_cooldown: float = 1.0
@export var stalk_rotation_speed: float = 1.2
@export var max_pursuit_distance: float = 15.0

# --- ESTADOS TÁCTICOS ---
enum State { IDLE, WANDER, CHASE, PURSUIT, STALK, APPROACH, ATTACKING, RETREAT, DAMAGE, DEAD }
var current_state: State = State.IDLE

# --- VARIABLES INTERNAS ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_hp: int
var is_facing_right = true
var player_ref: Node3D = null
var has_detected_player: bool = false  # Marca si alguna vez detectó al jugador

# Variables de Control de FSM y Movimiento
var cooldown_timer: float = 0.0
var retreat_target_position: Vector3 = Vector3.ZERO
var stalk_clockwise: bool = true
var wander_target: Vector3 = Vector3.ZERO
var is_jumping_to_attack: bool = false
var jump_target_position: Vector3 = Vector3.ZERO

@onready var animated_sprite = $AnimatedSprite3D
@onready var attack_area = $AttackArea
@onready var detection_area = $DetectionArea
@onready var retreat_timer = Timer.new()

func _ready():
	current_hp = max_hp
	
	add_child(retreat_timer)
	retreat_timer.one_shot = true
	retreat_timer.timeout.connect(_on_retreat_timer_timeout)

	_setup_detection_area()
	
	if detection_area and detection_area.has_signal("body_entered"):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if detection_area and detection_area.has_signal("body_exited"):
		detection_area.body_exited.connect(_on_detection_area_body_exited)
		
	if attack_area and attack_area.has_signal("body_entered"):
		attack_area.body_entered.connect(_on_attack_hit_player)
	
	if attack_area:
		var attack_collision = attack_area.get_node_or_null("CollisionShape3D")
		if attack_collision:
			attack_collision.disabled = true
		
	stalk_clockwise = randf() > 0.5
	set_state(State.WANDER)

func _physics_process(delta):
	if current_state == State.DEAD:
		return
	
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
	else:
		if current_state not in [State.ATTACKING, State.RETREAT]:
			velocity.y = 0
		# Resetear flag de salto al tocar suelo
		if is_jumping_to_attack and current_state != State.APPROACH:
			is_jumping_to_attack = false
			
	# Manejar cooldown/tiempo de espera
	if cooldown_timer > 0:
		cooldown_timer -= delta
	
	# IMPORTANTE: Siempre mirar al jugador cuando está targeteado
	if player_ref and current_state not in [State.WANDER, State.IDLE, State.DEAD]:
		_look_at_player()
	
	# Lógica según estado
	if current_state not in [State.DAMAGE]:
		_state_machine(delta)
	
	move_and_slide()
	_update_animations()

# --- MÁQUINA DE ESTADOS TÁCTICA ---

func _state_machine(delta: float):
	
	if current_state in [State.WANDER, State.IDLE]:
		_process_wander_idle(delta)
		return

	if not player_ref:
		# Si pierde al jugador pero lo había detectado antes
		if has_detected_player:
			set_state(State.IDLE)
		else:
			set_state(State.WANDER)
		return
	
	var distance_to_player = global_position.distance_to(player_ref.global_position)
	
	# Si el jugador está muy lejos, perseguirlo agresivamente
	if has_detected_player and current_state not in [State.ATTACKING, State.RETREAT]:
		if distance_to_player > safe_distance * 3.0:
			if current_state != State.PURSUIT:
				set_state(State.PURSUIT)
		elif current_state == State.PURSUIT:
			# Volver a chase normal cuando se acerca
			set_state(State.CHASE)
	
	match current_state:
		
		State.CHASE:
			if distance_to_player <= safe_distance:
				set_state(State.STALK)
			else:
				_process_chase()
		
		State.PURSUIT:
			# Perseguir agresivamente hasta acercarse
			if distance_to_player <= safe_distance * 2.0:
				set_state(State.CHASE)
			elif distance_to_player > max_pursuit_distance:
				# Demasiado lejos, abandonar
				print("🏃 Enemigo: Jugador muy lejos, abandonando persecución")
				player_ref = null
				has_detected_player = false
				set_state(State.IDLE)
			else:
				_process_pursuit()
		
		State.STALK:
			if distance_to_player > safe_distance + 0.5:
				set_state(State.CHASE)
			elif cooldown_timer <= 0:
				set_state(State.APPROACH)
			else:
				_process_stalk(delta, distance_to_player)
		
		State.APPROACH:
			if is_on_floor() and not is_jumping_to_attack:
				# Realizar salto hacia el jugador
				_jump_to_player()
			elif is_jumping_to_attack:
				# En el aire, esperar a llegar
				var horizontal_distance = Vector2(
					global_position.x - player_ref.global_position.x,
					global_position.z - player_ref.global_position.z
				).length()
				
				if is_on_floor() and horizontal_distance <= melee_range:
					set_state(State.ATTACKING)
		
		State.ATTACKING:
			velocity = Vector3.ZERO
		
		State.RETREAT:
			_process_retreat()

# --- LÓGICA DE PROCESAMIENTO ---

func _process_wander_idle(_delta):
	if player_ref:
		set_state(State.CHASE)
		return
		
	if current_state == State.IDLE:
		velocity = Vector3.ZERO
		if cooldown_timer <= 0:
			set_state(State.WANDER)
		return
		
	var direction = (wander_target - global_position).normalized()
	direction.y = 0
	
	if global_position.distance_to(wander_target) < 0.1:
		set_state(State.IDLE)
		return
		
	_apply_movement(direction, move_speed)

func _process_chase():
	var direction_to_player = (player_ref.global_position - global_position).normalized()
	direction_to_player.y = 0
	_apply_movement(direction_to_player, chase_speed)

func _process_pursuit():
	"""Perseguir agresivamente al jugador que intenta escapar"""
	var direction_to_player = (player_ref.global_position - global_position).normalized()
	direction_to_player.y = 0
	_apply_movement(direction_to_player, pursuit_speed)
	
	# Debug visual
	if Engine.get_frames_drawn() % 60 == 0:  # Cada 60 frames
		print("🏃💨 Enemigo: PERSIGUIENDO AGRESIVAMENTE - Distancia: ", 
			  "%.1f" % global_position.distance_to(player_ref.global_position))

func _process_stalk(delta: float, current_distance: float):
	var to_target = player_ref.global_position - global_position
	to_target.y = 0
	
	var radial_dir = to_target.normalized()
	
	var distance_error = current_distance - safe_distance
	var approach_factor = clamp(-distance_error * 0.3, -1.0, 1.0)
	
	var tangent_dir = Vector3(-radial_dir.z, 0, radial_dir.x)
	if not stalk_clockwise:
		tangent_dir = -tangent_dir
	
	var move_direction = (radial_dir * approach_factor + tangent_dir).normalized()
	
	_apply_movement(move_direction, stalk_speed)

func _process_approach():
	# Movimiento mientras está en el aire (salto)
	if not is_on_floor():
		return
	
	# Si está en el suelo y no ha saltado, prepararse
	var direction = (player_ref.global_position - global_position).normalized()
	direction.y = 0
	_apply_movement(direction, stalk_speed)  # Moverse lentamente antes de saltar

func _jump_to_player():
	"""Saltar directamente hacia la posición del jugador"""
	is_jumping_to_attack = true
	
	# Calcular dirección hacia el jugador
	var direction_to_player = (player_ref.global_position - global_position).normalized()
	direction_to_player.y = 0
	
	# Aplicar velocidad horizontal hacia el jugador
	velocity.x = direction_to_player.x * approach_jump_force
	velocity.z = direction_to_player.z * approach_jump_force
	
	# Aplicar salto vertical
	velocity.y = approach_jump_force
	
	print("🦘 Enemigo: ¡SALTO DE ATAQUE!")

func _jump_retreat():
	"""Saltar hacia atrás después de atacar"""
	var direction_away = (global_position - player_ref.global_position).normalized()
	direction_away.y = 0
	
	# Aplicar velocidad horizontal hacia atrás
	velocity.x = direction_away.x * retreat_jump_force
	velocity.z = direction_away.z * retreat_jump_force
	
	# Aplicar salto vertical (más bajo que el de ataque)
	velocity.y = retreat_jump_force
	
	print("🦘 Enemigo: ¡SALTO DE RETROCESO!")

func _process_retreat():
	# Si está en el suelo, hacer salto de retroceso una sola vez
	if is_on_floor() and velocity.y <= 0:
		_jump_retreat()
	
	# En el aire, mantener dirección (la física se encarga)
	pass

# --- MANEJO DE ESTADOS ---

func set_state(new_state: State):
	if current_state == new_state: return
	
	# Cleanup del estado anterior
	if current_state == State.ATTACKING:
		var attack_collision = attack_area.get_node_or_null("CollisionShape3D")
		if attack_collision:
			attack_collision.disabled = true
	
	current_state = new_state
	
	match current_state:
		State.IDLE:
			cooldown_timer = randf_range(0.5, 1.5)
			velocity = Vector3.ZERO
		
		State.WANDER:
			_start_wander()
		
		State.CHASE:
			print("🏃 Enemigo: PERSIGUIENDO al jugador")
		
		State.PURSUIT:
			print("🏃💨 Enemigo: PERSECUCIÓN AGRESIVA - ¡No escaparás!")
			
		State.ATTACKING:
			_execute_attack() 
			
		State.RETREAT:
			_start_retreat()
			
		State.DAMAGE:
			_start_damage()
			
		State.DEAD:
			_start_dead()

# --- INICIALIZACIÓN DE ESTADOS ---

func _start_wander():
	var wander_origin = global_position
	var random_angle = randf_range(0, 2 * PI)
	var random_distance = randf_range(0.5, 1.5)

	wander_target = wander_origin + Vector3(
		cos(random_angle) * random_distance,
		0,
		sin(random_angle) * random_distance
	)

func _execute_attack():
	cooldown_timer = attack_cooldown
	velocity = Vector3.ZERO
	
	if animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")
	else:
		animated_sprite.play("idle") 
	
	var attack_collision = attack_area.get_node_or_null("CollisionShape3D")
	if attack_collision:
		attack_collision.disabled = false
	
	await get_tree().create_timer(0.15).timeout
	
	if attack_collision:
		attack_collision.disabled = true
		
	if current_state != State.DEAD:
		set_state(State.RETREAT)

func _start_retreat():
	if not player_ref:
		set_state(State.IDLE)
		return
	
	# Iniciar timer para volver a STALK
	retreat_timer.start(retreat_duration)
	
func _on_retreat_timer_timeout():
	if current_state != State.DEAD and player_ref:
		velocity = Vector3.ZERO
		set_state(State.STALK)
	elif current_state != State.DEAD:
		set_state(State.IDLE)

func _start_damage():
	velocity = Vector3.ZERO
	if animated_sprite.sprite_frames.has_animation("damage"):
		animated_sprite.play("damage")
	else:
		animated_sprite.modulate = Color(1, 0.5, 0.5, 1)
	
	get_tree().create_timer(0.3).timeout.connect(func():
		animated_sprite.modulate = Color.WHITE
		if current_state != State.DEAD:
			if player_ref:
				set_state(State.CHASE)
			else:
				set_state(State.IDLE)
	)

func _start_dead():
	velocity = Vector3.ZERO
	print("💀 Enemigo eliminado")
	if animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		await animated_sprite.animation_finished
	queue_free()

# --- UTILIDADES Y DETECCIÓN ---

func _setup_detection_area():
	var collision_shape_detection = detection_area.get_node_or_null("CollisionShape3D")
	if collision_shape_detection and not collision_shape_detection.shape is SphereShape3D:
		var sphere_shape = SphereShape3D.new()
		sphere_shape.radius = safe_distance * 3
		collision_shape_detection.shape = sphere_shape

func _on_detection_area_body_entered(body):
	if body.is_in_group("player"):
		player_ref = body
		has_detected_player = true  # Marcar que lo detectó
		print("🎯 Enemigo: ¡Jugador detectado por primera vez!")
		set_state(State.CHASE)

func _on_detection_area_body_exited(body):
	if body == player_ref:
		print("👁️ Enemigo: Jugador salió del área de detección")
		# NO limpiar player_ref ni has_detected_player
		# El enemigo seguirá persiguiendo agresivamente
		if current_state in [State.CHASE, State.STALK, State.APPROACH]:
			set_state(State.PURSUIT)

func _on_attack_hit_player(body):
	if current_state == State.ATTACKING and body.is_in_group("player"):
		if body.has_method("take_damage_hearts"):
			body.take_damage_hearts(attack_damage)

func take_damage(damage_amount: int):
	if current_hp > 0:
		current_hp -= max(damage_amount - defense, 1)
		print("💔 Enemigo HP: ", current_hp, "/", max_hp)
		if current_hp <= 0:
			set_state(State.DEAD)
		else:
			set_state(State.DAMAGE)

func _apply_movement(direction: Vector3, speed: float):
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	# NO llamar _flip_sprite aquí, ya que se hace en _look_at_player

func _look_at_player():
	"""Hacer que el enemigo siempre mire hacia el jugador"""
	if not player_ref:
		return
	
	var direction_to_player = player_ref.global_position - global_position
	direction_to_player.y = 0
	
	if direction_to_player.length() > 0.01:
		var facing_right = direction_to_player.x > 0
		
		if facing_right != is_facing_right:
			is_facing_right = facing_right
			animated_sprite.flip_h = not is_facing_right
			# IMPORTANTE: Voltear también el AttackArea
			if attack_area:
				attack_area.scale.x = 1.0 if is_facing_right else -1.0

func _update_animations():
	if current_state in [State.DEAD, State.DAMAGE, State.ATTACKING]:
		return
	
	var target_animation = "idle"
	if velocity.length_squared() > 0.001:
		target_animation = "walk"
		
	if animated_sprite.sprite_frames.has_animation(target_animation):
		animated_sprite.play(target_animation)

func _flip_sprite(x_direction: float):
	"""Método legacy - ahora se usa _look_at_player"""
	if x_direction == 0: return
	var facing_right = x_direction > 0
	if facing_right != is_facing_right:
		is_facing_right = facing_right
		animated_sprite.flip_h = not is_facing_right
		if attack_area:
			attack_area.scale.x = 1.0 if is_facing_right else -1.0
