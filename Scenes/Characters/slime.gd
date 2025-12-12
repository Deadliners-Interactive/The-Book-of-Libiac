class_name Slime
extends CharacterBody3D

# ==============================================================================
# --- RECURSOS EXTERNOS ---
# ==============================================================================
@export var small_slime_scene: PackedScene

# ==============================================================================
# --- CONFIGURACIÓN DEL ENEMIGO ---
# ==============================================================================
@export_group("Enemy Core Stats")
@export var max_hp: int = 30
@export var defense: int = 0
@export var move_speed: float = 0.3
@export var gravity_multiplier: float = 1.0
@export var size: float = 1.0: 
	set(value):
		size = value
		if is_inside_tree():
			_update_visual_scale()

@export_group("Chaser Behavior")
@export var chase_speed: float = 1.0
@export var pursuit_speed: float = 0.6
@export var stalk_speed: float = 0.1
@export var approach_jump_force: float = 1.35
@export var retreat_jump_force: float = 1.0
@export var retreat_speed_mult: float = 1.5
@export var safe_distance: float = 1.0
@export var melee_range: float = 0.2
@export var retreat_distance: float = 0.5
@export var retreat_duration: float = 0.15
@export var attack_damage: float = 10
@export var attack_cooldown: float = 1.0
@export var stalk_rotation_speed: float = 1.2
@export var max_pursuit_distance: float = 15.0
@export var attack_fail_distance: float = 0.5
@export var jump_over_margin: float = 0.1
@export var jump_interval: float = 0.6

@export_group("Small Slime Settings")
@export var spawn_invulnerability_time: float = 2.0
@export var small_slime_attack_damage: float = 5
@export var small_slime_approach_range: float = 0.5

# ==============================================================================
# --- ESTADOS Y VARIABLES INTERNAS ---
# ==============================================================================
enum State { IDLE, WANDER, CHASE, PURSUIT, STALK, APPROACH, ATTACKING, RETREAT, DAMAGE, DEAD }
var current_state: State = State.IDLE

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_hp: int
var is_facing_right = true
var player_ref: Node3D = null
var has_detected_player: bool = false

var cooldown_timer: float = 0.0
var stalk_clockwise: bool = true
var wander_target: Vector3 = Vector3.ZERO
var is_jumping_to_attack: bool = false
var attack_was_successful: bool = false

var can_jump: bool = true
var pending_horizontal_velocity: Vector3 = Vector3.ZERO
var jump_timer: Timer
var is_splitting: bool = false

# Variables de invulnerabilidad al spawn (solo para pequeños)
var is_invulnerable_spawn: bool = false
var invulnerability_timer: Timer

@onready var animated_sprite = $AnimatedSprite3D
@onready var attack_area = $AttackArea
@onready var detection_area = $DetectionArea
var retreat_timer: Timer

# ==============================================================================
# --- LIFECYCLE Y PROCESS ---
# ==============================================================================

func _ready():
	current_hp = max_hp
	
	add_to_group("slime")
	
	# Crear timers
	retreat_timer = Timer.new()
	add_child(retreat_timer)
	retreat_timer.one_shot = true
	retreat_timer.timeout.connect(_on_retreat_timer_timeout)

	jump_timer = Timer.new()
	add_child(jump_timer)
	jump_timer.one_shot = true
	jump_timer.timeout.connect(_on_jump_timer_timeout)
	
	# Timer de invulnerabilidad al spawn (solo para pequeños)
	invulnerability_timer = Timer.new()
	add_child(invulnerability_timer)
	invulnerability_timer.one_shot = true
	invulnerability_timer.timeout.connect(_on_invulnerability_timeout)

	_setup_detection_area()
	_update_visual_scale()

	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
		detection_area.body_exited.connect(_on_detection_area_body_exited)

	if attack_area:
		attack_area.body_entered.connect(_on_attack_hit_player)
		var attack_collision = attack_area.get_node_or_null("CollisionShape3D")
		if attack_collision:
			attack_collision.disabled = true

	stalk_clockwise = randf() > 0.5
	
	# Si es pequeño, activar invulnerabilidad al spawn
	if size < 1.0:
		_activate_spawn_invulnerability()
	
	set_state(State.WANDER)

func _activate_spawn_invulnerability():
	is_invulnerable_spawn = true
	invulnerability_timer.start(spawn_invulnerability_time)
	
	# SOLO texto, sin cambiar el color
	print("🛡️ Slime pequeño: Invulnerable por %.1f segundos" % spawn_invulnerability_time)

func _on_invulnerability_timeout():
	is_invulnerable_spawn = false
	print("✅ Slime pequeño: Invulnerabilidad terminada")

func _physics_process(delta):
	if current_state == State.DEAD or is_splitting:
		return

	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
	else:
		if current_state not in [State.APPROACH, State.RETREAT]:
			velocity.y = 0

		if is_jumping_to_attack and current_state != State.APPROACH:
			is_jumping_to_attack = false
			
		# Salto de movimiento continuo
		if can_jump and current_state not in [State.APPROACH, State.RETREAT, State.DAMAGE, State.ATTACKING]:
			_start_movement_jump()

	if cooldown_timer > 0:
		cooldown_timer -= delta

	if player_ref and current_state not in [State.WANDER, State.IDLE, State.DEAD]:
		_look_at_player()

	if current_state != State.DAMAGE:
		_state_machine(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, 3 * delta)
		velocity.z = move_toward(velocity.z, 0, 3 * delta)

	move_and_slide()
	_update_animations()

# ==============================================================================
# --- LÓGICA DE MOVIMIENTO / SALTO ---
# ==============================================================================

func _on_jump_timer_timeout():
	can_jump = true

func _start_movement_jump():
	if pending_horizontal_velocity.length_squared() > 0.001:
		velocity.x = pending_horizontal_velocity.x
		velocity.z = pending_horizontal_velocity.z
		velocity.y = 0.5 * size 
		
		pending_horizontal_velocity = Vector3.ZERO
		can_jump = false
		jump_timer.start(jump_interval)

func _apply_movement(direction: Vector3, speed: float):
	# Añadir un poco de variabilidad aleatoria para evitar movimiento sincronizado
	var random_variation = Vector3(
		randf_range(-0.1, 0.1),
		0,
		randf_range(-0.1, 0.1)
	)
	direction += random_variation
	direction = direction.normalized()
	
	pending_horizontal_velocity = direction * speed
	
	if not is_on_floor():
		velocity.x = move_toward(velocity.x, pending_horizontal_velocity.x, 3.0 * get_physics_process_delta_time())
		velocity.z = move_toward(velocity.z, pending_horizontal_velocity.z, 3.0 * get_physics_process_delta_time())

# ==============================================================================
# --- MÁQUINA DE ESTADOS TÁCTICA ---
# ==============================================================================

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

	if has_detected_player and current_state not in [State.ATTACKING, State.RETREAT, State.APPROACH]:
		if distance_to_player > safe_distance * 3.0:
			if current_state != State.PURSUIT:
				set_state(State.PURSUIT)
		elif current_state == State.PURSUIT:
			set_state(State.CHASE)

	match current_state:
		State.CHASE:
			# AHORA AMBOS TAMAÑOS ATACAN
			if distance_to_player <= small_slime_approach_range:
				set_state(State.APPROACH)
			else:
				_process_chase()

		State.PURSUIT:
			if distance_to_player <= safe_distance * 2.0:
				set_state(State.CHASE)
			elif distance_to_player > max_pursuit_distance:
				player_ref = null
				has_detected_player = false
				set_state(State.IDLE) 
			else:
				_process_pursuit()

		State.STALK:
			# Solo slimes grandes usan STALK
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
				_jump_to_player(horizontal_distance)
			elif is_jumping_to_attack:
				if is_on_floor() and velocity.y <= 0.01:
					var attack_range = melee_range if size >= 1.0 else melee_range * 1.5
					if horizontal_distance <= attack_range + attack_fail_distance:
						set_state(State.ATTACKING)
					else:
						is_jumping_to_attack = false
						set_state(State.CHASE)

		State.ATTACKING:
			velocity = Vector3.ZERO

		State.RETREAT:
			_process_retreat()

# ==============================================================================
# --- PROCESAMIENTO DE ESTADOS ---
# ==============================================================================

func _process_wander_idle(_delta):
	if player_ref:
		set_state(State.CHASE)
		return

	if current_state == State.IDLE:
		pending_horizontal_velocity = Vector3.ZERO
		velocity.x = move_toward(velocity.x, 0, 0.1)
		velocity.z = move_toward(velocity.z, 0, 0.1)
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

func _process_stalk(delta: float, current_distance: float):
	# Solo slimes grandes usan STALK
	if size < 1.0:
		set_state(State.CHASE)
		return
	
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

func _jump_to_player(horizontal_distance: float):
	is_jumping_to_attack = true
	can_jump = false

	var direction_to_player = (player_ref.global_position - global_position)
	direction_to_player.y = 0

	# Ajustar fuerza de salto según tamaño
	var jump_force = approach_jump_force if size >= 1.0 else approach_jump_force * 0.7
	
	var distance_needed = horizontal_distance - melee_range + jump_over_margin
	var target_h_distance = max(0.1, distance_needed) 

	var time_to_land = 2.0 * jump_force / gravity
	var horizontal_speed = target_h_distance / time_to_land

	var jump_vector = direction_to_player.normalized()
	velocity.x = jump_vector.x * horizontal_speed
	velocity.z = jump_vector.z * horizontal_speed
	velocity.y = jump_force

func _jump_retreat():
	can_jump = false
	
	var direction_away = (global_position - player_ref.global_position).normalized()
	direction_away.y = 0

	# Ajustar fuerza de retroceso según tamaño
	var retreat_force = retreat_jump_force if size >= 1.0 else retreat_jump_force * 0.7
	
	velocity.x = direction_away.x * retreat_force
	velocity.z = direction_away.z * retreat_force
	velocity.y = retreat_force

func _process_retreat():
	if is_on_floor() and velocity.y <= 0.01:
		_jump_retreat()

# ==============================================================================
# --- MANEJO DE ESTADOS Y TRANSICIONES (CORREGIDO CON call_deferred) ---
# ==============================================================================

func set_state(new_state: State):
	if current_state == new_state:
		return

	# Usar call_deferred para evitar errores de física
	if current_state == State.ATTACKING:
		var attack_collision = attack_area.get_node_or_null("CollisionShape3D")
		if attack_collision:
			attack_collision.set_deferred("disabled", true)

	current_state = new_state

	match current_state:
		State.IDLE:
			cooldown_timer = randf_range(0.5, 1.5)
			pending_horizontal_velocity = Vector3.ZERO
			can_jump = true

		State.WANDER:
			_start_wander()

		State.ATTACKING:
			_execute_attack()
			can_jump = false

		State.RETREAT:
			_start_retreat()
			can_jump = false

		State.DAMAGE:
			_start_damage()
			can_jump = false

		State.DEAD:
			_start_dead()
			can_jump = false
			if jump_timer:
				jump_timer.stop()

# ==============================================================================
# --- INICIALIZACIÓN DE ESTADOS ---
# ==============================================================================

func _start_wander():
	can_jump = true
	jump_timer.start(jump_interval)
	
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
	attack_was_successful = false

	if animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")
	else:
		animated_sprite.play("idle")

	var attack_collision = attack_area.get_node_or_null("CollisionShape3D")
	if attack_collision:
		attack_collision.set_deferred("disabled", false)

	await get_tree().create_timer(0.15).timeout

	if attack_collision:
		attack_collision.set_deferred("disabled", true)

	if current_state != State.DEAD and not is_splitting:
		if attack_was_successful:
			set_state(State.RETREAT)
		else:
			set_state(State.CHASE)

func _start_retreat():
	if not player_ref:
		set_state(State.IDLE)
		return

	retreat_timer.start(retreat_duration)

func _on_retreat_timer_timeout():
	if current_state != State.DEAD and not is_splitting and player_ref:
		velocity = Vector3.ZERO
		set_state(State.CHASE)
	elif current_state != State.DEAD and not is_splitting:
		set_state(State.IDLE)

func _start_damage():
	if jump_timer:
		jump_timer.stop()
	
	velocity = Vector3.ZERO
	if animated_sprite.sprite_frames.has_animation("damage"):
		animated_sprite.play("damage")
	else:
		animated_sprite.modulate = Color(1, 0.5, 0.5, 1)

	await get_tree().create_timer(0.3).timeout
	
	if is_splitting or current_state == State.DEAD:
		return
		
	animated_sprite.modulate = Color.WHITE
	if current_state != State.DEAD:
		if player_ref:
			set_state(State.CHASE)
		else:
			set_state(State.IDLE)
		can_jump = true

func _start_dead():
	velocity = Vector3.ZERO
	
	if animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		await animated_sprite.animation_finished
	
	queue_free()

# ==============================================================================
# --- UTILIDADES Y COLISIONES ---
# ==============================================================================

func _update_visual_scale():
	scale = Vector3(size, size, size)
	move_speed = 0.3 * size
	chase_speed = 1.0 * size
	pursuit_speed = 0.6 * size
	stalk_speed = 0.1 * size

func _setup_detection_area():
	if not detection_area:
		return
		
	var collision_shape_detection = detection_area.get_node_or_null("CollisionShape3D")
	if collision_shape_detection:
		if not collision_shape_detection.shape is SphereShape3D:
			var sphere_shape = SphereShape3D.new()
			sphere_shape.radius = safe_distance * 3
			collision_shape_detection.shape = sphere_shape

func _on_detection_area_body_entered(body):
	if body.is_in_group("player"):
		player_ref = body
		has_detected_player = true
		call_deferred("set_state", State.CHASE)

func _on_detection_area_body_exited(body):
	if body == player_ref:
		if has_detected_player and current_state in [State.CHASE, State.STALK, State.APPROACH]:
			call_deferred("set_state", State.PURSUIT)

func _on_attack_hit_player(body):
	# AHORA AMBOS TAMAÑOS ATACAN
	if current_state == State.ATTACKING and body.is_in_group("player"):
		attack_was_successful = true
		if body.has_method("take_damage_hearts_with_knockback"):
			var knockback_force = 0.05 if size < 1.0 else 0.1
			var direction = (body.global_position - global_position).normalized()
			var damage = small_slime_attack_damage if size < 1.0 else attack_damage
			body.take_damage_hearts_with_knockback(damage, direction, knockback_force)

func _look_at_player():
	if not player_ref:
		return

	var direction_to_player = player_ref.global_position - global_position
	direction_to_player.y = 0

	if direction_to_player.length() > 0.01:
		var facing_right = direction_to_player.x > 0

		if facing_right != is_facing_right:
			is_facing_right = facing_right
			animated_sprite.flip_h = not is_facing_right
			if attack_area:
				attack_area.scale.x = 1.0 if is_facing_right else -1.0

func _update_animations():
	if current_state in [State.DEAD, State.DAMAGE, State.ATTACKING]:
		return

	var target_animation = "idle"
	
	if pending_horizontal_velocity.length_squared() > 0.001 or velocity.length_squared() > 0.001:
		target_animation = "walk"

	if animated_sprite.sprite_frames.has_animation(target_animation):
		animated_sprite.play(target_animation)

# ==============================================================================
# --- DIVISIÓN Y DAÑO (COMPLETAMENTE REESCRITO) ---
# ==============================================================================

func _split_into_smaller_slimes():
	if is_splitting:
		return
	
	is_splitting = true
	print("🔄 Iniciando división del Slime grande...")
	
	if jump_timer:
		jump_timer.stop()
	if retreat_timer:
		retreat_timer.stop()
	
	velocity = Vector3.ZERO
	
	if not small_slime_scene:
		print("❌ ERROR: small_slime_scene no asignado")
		queue_free()
		return
	
	var spawn_position = global_position
	var parent_node = get_parent()
	
	for i in range(3):
		var new_slime = small_slime_scene.instantiate()
		
		new_slime.size = 0.5
		new_slime.max_hp = 10
		new_slime.current_hp = 10
		
		# Generar posiciones en un círculo COMPLETAMENTE EN EL SUELO
		var base_angle = (i * 120.0) * PI / 180.0
		var random_variation = randf_range(-20, 20) * PI / 180.0
		var angle = base_angle + random_variation
		
		# Offset MUY pequeño en el suelo
		var offset_distance = 0.2  # Muy pequeño
		var offset = Vector3(
			cos(angle) * offset_distance,
			0,  # EN EL SUELO, sin altura
			sin(angle) * offset_distance
		)
		
		if player_ref:
			new_slime.player_ref = player_ref
			new_slime.has_detected_player = true
		
		# NO dar velocidad inicial - dejar que la gravedad actúe naturalmente
		new_slime.velocity = Vector3.ZERO
		
		parent_node.call_deferred("add_child", new_slime)
		
		# Posicionar EXACTAMENTE en el suelo
		var final_position = spawn_position + offset
		# Asegurar que Y sea la misma que el slime grande (ya está en el suelo)
		final_position.y = spawn_position.y
		
		# Esperar un frame antes de posicionar para evitar problemas de física
		await get_tree().process_frame
		new_slime.global_position = final_position
		
		print("✅ Slime pequeño %d creado en posición: %s" % [i + 1, str(final_position)])
	
	queue_free()

func take_damage(damage_amount: int):
	if current_state == State.DEAD or is_splitting:
		return
	
	# Invulnerabilidad al spawn (solo pequeños)
	if is_invulnerable_spawn:
		print("🛡️ Slime: Daño bloqueado (invulnerable al spawn)")
		return

	var actual_damage = max(damage_amount - defense, 1)
	current_hp -= actual_damage
	print("💔 Slime HP: %d/%d (Daño: %d)" % [current_hp, max_hp, actual_damage])
	
	if current_hp <= 0:
		if size >= 1.0:
			_split_into_smaller_slimes()
		else:
			call_deferred("set_state", State.DEAD)
	else:
		if current_state not in [State.DEAD, State.RETREAT]:
			# Usar call_deferred para evitar el error de física
			call_deferred("set_state", State.DAMAGE)
