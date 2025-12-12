extends CharacterBody3D

# ================================
# CONFIGURACIÓN DEL ENEMIGO FLOTANTE
# ================================
@export_group("Enemy Stats")
@export var max_hp: int = 20
@export var defense: int = 0
@export var move_speed: float = 1.5 # Velocidad de movimiento (WANDER)
@export var chase_speed: float = 3.0 # Velocidad de persecución (CHASE)

@export_group("Range Attack")
@export var shoot_range: float = 5.0 # Rango para empezar a disparar
@export var shoot_cooldown: float = 2.0 # Tiempo entre disparos
@export var attack_damage: float = 5.0 # Daño del proyectil
@export var projectile_speed: float = 8.0 # Velocidad del proyectil
@export var projectile_scene: PackedScene # ⬅️ ASIGNA LA ESCENA DEL PROYECTIL AQUÍ

@export_group("Patrol")
@export var wander_radius: float = 4.0
@export var lost_player_distance: float = 10.0
@export var vertical_float_amplitude: float = 0.5 # Para el movimiento flotante vertical
@export var vertical_float_speed: float = 2.0 # Velocidad de la oscilación vertical

@export_group("Damage")
@export var damage_duration: float = 0.2
@export var post_damage_recovery_pause: float = 0.3

# ================================
# ESTADOS
# ================================
enum State { IDLE, WANDER, CHASE, SHOOTING, COOLDOWN, DAMAGE, DEAD }
var current_state: State = State.IDLE

# ================================
# VARIABLES INTERNAS
# ================================
var current_hp: int
var player_ref: CharacterBody3D = null
var cooldown_timer: float = 0.0
var wander_target: Vector3
var hit_registered: bool = false
var damage_recovery_timer: Timer = Timer.new()
var initial_y: float # Para el movimiento flotante

@onready var animated_sprite = $AnimatedSprite3D
@onready var detection_area = $DetectionArea
@onready var projectile_spawn_point = $ProjectileSpawnPoint

# ================================
# READY
# ================================
func _ready():
	current_hp = max_hp
	initial_y = global_position.y # Guardar posición inicial para el flotamiento
	
	# 🟢 Conexiones
	detection_area.body_entered.connect(_on_detection_enter)
	detection_area.body_exited.connect(_on_detection_exit)

	add_child(damage_recovery_timer)
	damage_recovery_timer.one_shot = true
	damage_recovery_timer.timeout.connect(_on_damage_recovery_timeout)

	set_state(State.WANDER)

# ================================
# PHYSICS (SIN GRAVEDAD)
# ================================
func _physics_process(delta):
	if current_state == State.DEAD:
		return

	# Reiniciamos Y (la lógica de flotamiento la establecerá más tarde)
	var float_movement = velocity.y
	velocity.y = 0 

	if cooldown_timer > 0:
		cooldown_timer -= delta

	_state_machine(delta)
	
	# Lógica de flotamiento vertical constante (independiente del estado)
	var new_y = initial_y + sin(Time.get_ticks_msec() / 1000.0 * vertical_float_speed) * vertical_float_amplitude
	var float_vel = (new_y - global_position.y) / delta
	velocity.y = float_vel

	move_and_slide()
	_update_animations()

# ================================
# STATE MACHINE y COMPORTAMIENTO
# ================================
func _state_machine(delta):
	match current_state:
		State.WANDER:
			_process_wander()
		State.CHASE:
			_process_chase()
		State.SHOOTING:
			velocity.x = move_toward(velocity.x, 0, 10 * delta)
			velocity.z = move_toward(velocity.z, 0, 10 * delta)
		State.COOLDOWN:
			velocity.x = move_toward(velocity.x, 0, 10 * delta)
			velocity.z = move_toward(velocity.z, 0, 10 * delta)
		State.DAMAGE:
			# Lógica de frenado del knockback
			velocity.x = move_toward(velocity.x, 0, 5 * delta)
			velocity.z = move_toward(velocity.z, 0, 5 * delta)

# --- WANDER (Movimiento 3D) ---
func _process_wander():
	if player_ref:
		set_state(State.CHASE)
		return

	if wander_target == Vector3.ZERO or global_position.distance_to(wander_target) < 0.5:
		var angle = randf_range(0, TAU)
		var dist = randf_range(1.0, wander_radius)
		
		# Usamos la Y actual (initial_y) para mantener la altura base
		wander_target = Vector3(global_position.x, initial_y, global_position.z) + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		
	# Aplanamos la dirección de movimiento para ignorar la diferencia de altura.
	var dir = (wander_target - global_position).normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	
	# Actualizar 'initial_y' para que el flotamiento continúe alrededor del nuevo objetivo.
	initial_y = global_position.y - sin(Time.get_ticks_msec() / 1000.0 * vertical_float_speed) * vertical_float_amplitude


# --- CHASE (Movimiento 3D y Ataque de Rango) ---
func _process_chase():
	if not player_ref:
		set_state(State.WANDER)
		return

	var dist = global_position.distance_to(player_ref.global_position)

	if dist > lost_player_distance:
		player_ref = null
		set_state(State.WANDER)
		return
		
	# Lógica de Disparo: Si está dentro del rango y sin cooldown
	if dist <= shoot_range and cooldown_timer <= 0:
		set_state(State.SHOOTING)
		return
		
	# Perseguir al jugador en 3D
	var target_pos_flat = Vector3(player_ref.global_position.x, global_position.y, player_ref.global_position.z)
	var dir = (target_pos_flat - global_position).normalized()
	
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	_look_at_player()

# ================================
# ATAQUE (DISPARO)
# ================================

func _execute_shoot():
	velocity.x = 0
	velocity.z = 0
	
	_look_at_player() # Asegurarse de que el enemigo mire al jugador antes de disparar
	
	if animated_sprite.sprite_frames.has_animation("attack"): 
		animated_sprite.play("attack")
	else:
		animated_sprite.play("idle")

	# Esperar un momento (ej. 0.2s) para la animación de 'wind-up'
	await get_tree().create_timer(0.2).timeout
	
	_spawn_projectile()
	
	# Transición a Cooldown/Post-disparo
	if animated_sprite.sprite_frames.has_animation("attack"):
		await animated_sprite.animation_finished 
	
	cooldown_timer = shoot_cooldown
	set_state(State.COOLDOWN)

func _spawn_projectile():
	if projectile_scene == null:
		push_error("Projectile Scene no está asignado en el inspector.")
		return

	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	
	projectile.global_position = projectile_spawn_point.global_position
	
	# Dirección del disparo hacia el jugador
	var shoot_dir = (player_ref.global_position - projectile_spawn_point.global_position).normalized()
	
	# Configurar el proyectil
	if projectile.has_method("initialize"):
		projectile.initialize(shoot_dir, projectile_speed, attack_damage, self)

func _start_post_attack_wait():
	# En un enemigo volador, el cooldown es solo una pausa, luego vuelve a perseguir/disparar.
	velocity.x = 0
	velocity.z = 0
	await get_tree().create_timer(post_damage_recovery_pause).timeout
	set_state(State.CHASE)

# ================================
# DETECCIÓN (Conexiones de la DetectionArea)
# ================================
func _on_detection_enter(body):
	if body.is_in_group("player"):
		player_ref = body
		set_state(State.CHASE)

func _on_detection_exit(body):
	if player_ref == body:
		player_ref = null
		set_state(State.WANDER)

# ================================
# DAÑO
# ================================
func take_damage(amount: int):
	current_hp -= max(amount - defense, 1)
	
	# Aplicar un rebote en Y al ser golpeado
	if current_hp > 0:
		velocity.y = 1.0 

	if current_hp <= 0:
		set_state(State.DEAD)
	else:
		set_state(State.DAMAGE)
		
func _on_damage_recovery_timeout():
	# 🟢 CAMBIO CLAVE 2: Restablecer el color del sprite al salir de DAMAGE
	if animated_sprite.modulate == Color.RED:
		animated_sprite.modulate = Color.WHITE
		
	if current_state == State.DAMAGE:
		# Al salir de DAMAGE, impón el cooldown para evitar ataques instantáneos
		cooldown_timer = max(cooldown_timer, post_damage_recovery_pause)
		
		if player_ref:
			set_state(State.CHASE)
		else:
			set_state(State.WANDER)

# ================================
# SET STATE
# ================================
func set_state(s: State):
	current_state = s

	match s:
		State.IDLE:
			velocity.x = 0
			velocity.z = 0

		State.WANDER:
			wander_target = Vector3.ZERO

		State.SHOOTING:
			_execute_shoot()

		State.COOLDOWN:
			_start_post_attack_wait()
			
		State.DAMAGE:
			damage_recovery_timer.start(damage_duration)
			velocity.x = move_toward(velocity.x, 0, 10.0) 
			velocity.z = move_toward(velocity.z, 0, 10.0)
			
			# 🟢 CAMBIO CLAVE 1: Aplicar color rojo si NO hay animación de daño.
			if animated_sprite.sprite_frames.has_animation("damage"):
				animated_sprite.play("damage")
			else:
				animated_sprite.modulate = Color.RED # Pintar de rojo
			
		State.DEAD:
			velocity = Vector3.ZERO
			if animated_sprite.sprite_frames.has_animation("death"):
				animated_sprite.play("death")
				await animated_sprite.animation_finished
			queue_free()

# ================================
# UTILIDADES
# ================================
func _look_at_player():
	if player_ref:
		var dir = player_ref.global_position - global_position
		# Solo miramos en el eje X para sprites 2D
		animated_sprite.flip_h = dir.x < 0

func _update_animations():
	if current_state in [State.DEAD, State.DAMAGE, State.SHOOTING, State.COOLDOWN]:
		return

	var anim = "idle"
	# Usamos la velocidad horizontal (X/Z) para determinar si está caminando
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z).length()
	
	if horizontal_velocity > 0.1:
		anim = "walk"

	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)
