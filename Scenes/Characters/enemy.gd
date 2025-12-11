extends CharacterBody3D

# --- CONFIGURACIÓN DEL ENEMIGO ---
@export_group("Enemy Stats")
@export var max_hp: int = 30
@export var defense: int = 0
@export var move_speed: float = 0.3
@export var gravity_multiplier: float = 1.0

@export_group("Chaser Behavior")
@export var chase_speed: float = 1.0             # Velocidad normal de persecución
@export var pursuit_speed: float = 0.6            # Velocidad de persecución agresiva (PURSUIT)
@export var stalk_speed: float = 0.1
@export var approach_jump_force: float = 1.35    # Fuerza base del salto de ataque
@export var retreat_jump_force: float = 1.0       # Fuerza del salto de retroceso
@export var retreat_speed_mult: float = 1.5
@export var safe_distance: float = 1.0
@export var melee_range: float = 0.2              # Rango de ataque (muy cerca)
@export var retreat_distance: float = 0.5
@export var retreat_duration: float = 0.15
@export var attack_damage: float = 10
@export var attack_cooldown: float = 1.0
@export var stalk_rotation_speed: float = 1.2
@export var max_pursuit_distance: float = 15.0    # Distancia máxima para abandonar persecución
@export var attack_fail_distance: float = 0.5     # Si aterriza más lejos de esta distancia (melee_range + X), vuelve a CHASE
@export var jump_over_margin: float = 0.1         # NUEVO: Distancia extra que debe saltar para caer más cerca del objetivo

# --- ESTADOS TÁCTICOS ---
enum State { IDLE, WANDER, CHASE, PURSUIT, STALK, APPROACH, ATTACKING, RETREAT, DAMAGE, DEAD }
var current_state: State = State.IDLE

# --- VARIABLES INTERNAS ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_hp: int
var is_facing_right = true
var player_ref: Node3D = null
var has_detected_player: bool = false   # Marca si alguna vez detectó al jugador

# Variables de Control de FSM y Movimiento
var cooldown_timer: float = 0.0
var retreat_target_position: Vector3 = Vector3.ZERO
var stalk_clockwise: bool = true
var wander_target: Vector3 = Vector3.ZERO
var is_jumping_to_attack: bool = false
var jump_target_position: Vector3 = Vector3.ZERO
var attack_was_successful: bool = false # <--- VARIABLE DE CONTROL DE ÉXITO

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
		if has_detected_player:
			set_state(State.IDLE)
		else:
			set_state(State.WANDER)
		return
	
	var distance_to_player = global_position.distance_to(player_ref.global_position)
	
	# Lógica para cambiar entre CHASE y PURSUIT
	if has_detected_player and current_state not in [State.ATTACKING, State.RETREAT, State.APPROACH]:
		if distance_to_player > safe_distance * 3.0:
			if current_state != State.PURSUIT:
				set_state(State.PURSUIT)
		elif current_state == State.PURSUIT:
			set_state(State.CHASE)
	
	match current_state:
		
		State.CHASE:
			if distance_to_player <= safe_distance:
				set_state(State.STALK)
			else:
				_process_chase()
		
		State.PURSUIT:
			if distance_to_player <= safe_distance * 2.0:
				set_state(State.CHASE)
			elif distance_to_player > max_pursuit_distance:
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
			var horizontal_distance = Vector2(
				global_position.x - player_ref.global_position.x,
				global_position.z - player_ref.global_position.z
			).length()

			if is_on_floor() and not is_jumping_to_attack:
				# Inicia el salto
				_jump_to_player(horizontal_distance)
			
			elif is_jumping_to_attack:
				if is_on_floor() and velocity.y <= 0.01: # Si ya aterrizó y está detenido verticalmente
					if horizontal_distance <= melee_range + attack_fail_distance:
						# Éxito de posicionamiento: Ataque
						print("⚔️ Enemigo: Ataque directo.")
						set_state(State.ATTACKING)
					else:
						# Fracaso de posicionamiento: Aterrizó lejos.
						is_jumping_to_attack = false
						# Vuelve a STALK para intentar de nuevo inmediatamente.
						print("❌ Enemigo: Aterrizaje fallido (distancia: %.2f). STALK y Reintento." % horizontal_distance)
						set_state(State.STALK) # CAMBIO CLAVE PARA REINTENTO INMEDIATO
		
		State.ATTACKING:
			velocity = Vector3.ZERO
		
		State.RETREAT:
			_process_retreat()

# --- LÓGICA DE PROCESAMIENTO (Movimiento se mantiene) ---

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
	var direction_to_player = (player_ref.global_position - global_position).normalized()
	direction_to_player.y = 0
	_apply_movement(direction_to_player, pursuit_speed)
	
	if Engine.get_frames_drawn() % 60 == 0: 
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
	if not is_on_floor():
		return
	
	var direction = (player_ref.global_position - global_position).normalized()
	direction.y = 0
	_apply_movement(direction, stalk_speed)

func _jump_to_player(horizontal_distance: float):
	is_jumping_to_attack = true
	
	var direction_to_player = (player_ref.global_position - global_position)
	direction_to_player.y = 0
	
	# MODIFICADO: Añadir jump_over_margin a la distancia que necesita recorrer
	var distance_needed = horizontal_distance - melee_range + jump_over_margin 
	var target_h_distance = max(0.1, distance_needed) # Asegura que haya distancia positiva
	
	# Calcular el tiempo de vuelo (parábola simple)
	# T = 2 * V_y / g
	var time_to_land = 2.0 * approach_jump_force / gravity
	
	# Calcular la velocidad horizontal necesaria: Vh = Distancia / T
	var horizontal_speed = target_h_distance / time_to_land
	
	# Aplicar velocidad horizontal hacia el jugador
	var jump_vector = direction_to_player.normalized()
	velocity.x = jump_vector.x * horizontal_speed
	velocity.z = jump_vector.z * horizontal_speed
	
	# Aplicar salto vertical
	velocity.y = approach_jump_force
	
	print("🦘 Enemigo: ¡SALTO DE ATAQUE! Vh: %.2f (Distancia a cubrir: %.2f)" % [horizontal_speed, target_h_distance]) # Log mejorado

func _jump_retreat():
	var direction_away = (global_position - player_ref.global_position).normalized()
	direction_away.y = 0
	
	velocity.x = direction_away.x * retreat_jump_force
	velocity.z = direction_away.z * retreat_jump_force
	
	velocity.y = retreat_jump_force
	
	print("🦘 Enemigo: ¡SALTO DE RETROCESO!")

func _process_retreat():
	# Si está en el suelo y sin velocidad vertical, hacer salto de retroceso una sola vez
	if is_on_floor() and velocity.y <= 0.01:
		_jump_retreat()
	
	pass

# --- MANEJO DE ESTADOS ---

func set_state(new_state: State):
	if current_state == new_state: return
	
	# Cleanup
	if current_state == State.ATTACKING:
		var attack_collision = attack_area.get_node_or_null("CollisionShape3D")
		if attack_collision:
			attack_collision.disabled = true
	
	current_state = new_state
	
	# Setup
	match current_state:
		State.IDLE:
			cooldown_timer = randf_range(0.5, 1.5)
			velocity = Vector3.ZERO
		
		State.WANDER:
			_start_wander()
		
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
	attack_was_successful = false # RESETEAR ÉXITO ANTES DEL ATAQUE
	
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
		# LÓGICA: Retirada solo si el ataque tuvo éxito
		if attack_was_successful:
			set_state(State.RETREAT)
		else:
			# Si falló, volver a STALK para reintentar.
			set_state(State.STALK) 

func _start_retreat():
	if not player_ref:
		set_state(State.IDLE)
		return
	
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
		# El jugador sale del área inmediata, pasa a persecución agresiva
		if has_detected_player:
			if current_state in [State.CHASE, State.STALK, State.APPROACH]:
				set_state(State.PURSUIT)

func _on_attack_hit_player(body):
	if current_state == State.ATTACKING and body.is_in_group("player"):
		attack_was_successful = true # MARCAR ÉXITO
		if body.has_method("take_damage_hearts_with_knockback"):
			# Knockback de 0.1, multiplicado por 10.0 en el script del jugador para sentirlo
			var knockback_force = 0.1 
			var direction = (body.global_position - global_position).normalized()
			body.take_damage_hearts_with_knockback(attack_damage, direction, knockback_force)

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

func _look_at_player():
	if not player_ref:
		return
	
	var direction_to_player = player_ref.global_position - global_position
	direction_to_player.y = 0
	
	if direction_to_player.length() > 0.01:
		var facing_right = direction_to_player.x > 0
		
		if facing_right != is_facing_right:
			is_facing_right = facing_right
			# Ajustado para que el sprite mire al jugador
			animated_sprite.flip_h = not is_facing_right 
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
	# Ya no se usa para el enemigo, _look_at_player hace el trabajo
	pass
