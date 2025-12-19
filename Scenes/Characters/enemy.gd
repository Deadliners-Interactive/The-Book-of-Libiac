extends CharacterBody3D

# ================================
# CONFIGURACIÓN DEL ENEMIGO
# ================================
@export_group("Enemy Stats")
@export var max_hp: int = 30
@export var defense: int = 0
@export var move_speed: float = 0.3
@export var chase_speed: float = 1.0
@export var gravity_multiplier: float = 1.0

@export_group("Attack")
@export var melee_range: float = 0.7
@export var attack_damage: float = 10
@export var attack_cooldown: float = 0.2
@export var attack_knockback_force: float = 0.2
@export var post_attack_wait_time: float = 1.0

# @export_group("Patrol")
@export var wander_radius: float = 2.5
@export var lost_player_distance: float = 8.0

# **NUEVA CONFIGURACIÓN**
@export_group("Damage")
@export var damage_duration: float = 0.3 # Tiempo que dura el estado DAMAGE/stun.
@export var post_damage_recovery_pause: float = 0.5 #Pausa extra después de salir de DAMAGE.

# ================================
# ESTADOS
# ================================
enum State { IDLE, WANDER, CHASE, ATTACKING, ATTACK_COOLDOWN, DAMAGE, DEAD }
var current_state: State = State.IDLE

# ================================
# VARIABLES INTERNAS
# ================================
var current_hp: int
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var player_ref: CharacterBody3D = null
var cooldown_timer: float = 0.0
var wander_target: Vector3
var hit_registered: bool = false
var damage_recovery_timer: Timer = Timer.new()

@onready var animated_sprite = $AnimatedSprite3D
@onready var attack_area = $AttackArea
@onready var detection_area = $DetectionArea

# ================================
# READY
# ================================
func _ready():
	current_hp = max_hp
	detection_area.body_entered.connect(_on_detection_enter)
	detection_area.body_exited.connect(_on_detection_exit)
	attack_area.body_entered.connect(_on_attack_hit_player)

	var col = attack_area.get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)

	add_child(damage_recovery_timer)
	damage_recovery_timer.one_shot = true
	damage_recovery_timer.timeout.connect(_on_damage_recovery_timeout)

	set_state(State.WANDER)

# ================================
# PHYSICS
# ================================
func _physics_process(delta):
	if current_state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
	else:
		if current_state not in [State.ATTACKING, State.ATTACK_COOLDOWN, State.DAMAGE]:
			velocity.y = 0

	if cooldown_timer > 0:
		cooldown_timer -= delta

	_state_machine(delta)
	move_and_slide()
	_update_animations()

# ================================
# STATE MACHINE
# ================================
func _state_machine(delta):
	if current_state == State.WANDER:
		_process_wander()
		return

	if current_state == State.CHASE:
		_process_chase()
		return
	
	if current_state in [State.ATTACKING, State.ATTACK_COOLDOWN]:
		return

	if current_state == State.DAMAGE:
		# Lógica de frenado del knockback
		velocity.x = move_toward(velocity.x, 0, 3 * delta)
		velocity.z = move_toward(velocity.z, 0, 3 * delta)
		return

# ================================
# COMPORTAMIENTO: WANDER (Se mantiene)
# ================================
func _process_wander():
	if player_ref:
		set_state(State.CHASE)
		return

	if wander_target == Vector3.ZERO or global_position.distance_to(wander_target) < 0.3:
		var angle = randf_range(0, TAU)
		var dist = randf_range(1.0, wander_radius)
		wander_target = global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

	var dir = (wander_target - global_position).normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

# ================================
# COMPORTAMIENTO: CHASE (Se mantiene)
# ================================
func _process_chase():
	if not player_ref:
		set_state(State.WANDER)
		return

	var dist = global_position.distance_to(player_ref.global_position)

	if dist > lost_player_distance:
		player_ref = null
		set_state(State.WANDER)
		return
	
	# El ataque solo ocurre si NO estamos en un estado que debería ser interrumpido por daño,
	# y si el cooldown_timer <= 0.
	if current_state not in [State.DAMAGE, State.ATTACK_COOLDOWN] and dist <= melee_range and cooldown_timer <= 0:
		set_state(State.ATTACKING)
		return

	var dir = (player_ref.global_position - global_position).normalized()
	dir.y = 0

	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	_look_at_player()

# ================================
# ATAQUE (Se mantiene)
# ================================
func _enable_attack_area():
	var col = attack_area.get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", false)

func _disable_attack_area():
	var col = attack_area.get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)

func _execute_attack():
	hit_registered = false
	velocity = Vector3.ZERO

	if animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")
	else:
		animated_sprite.play("idle")

	_enable_attack_area()
	await get_tree().create_timer(0.15).timeout
	_disable_attack_area()

	if not hit_registered:
		cooldown_timer = attack_cooldown
		set_state(State.CHASE)

func _start_post_attack_wait():
	velocity = Vector3.ZERO
	await get_tree().create_timer(post_attack_wait_time).timeout
	cooldown_timer = attack_cooldown
	set_state(State.CHASE)

func _on_attack_hit_player(body):
	if current_state != State.ATTACKING or hit_registered:
		return
		
	if body.is_in_group("player"):
		var direction = (body.global_position - global_position).normalized()
		if body.has_method("take_damage_hearts_with_knockback"):
			body.take_damage_hearts_with_knockback(attack_damage, direction, attack_knockback_force)
			
		hit_registered = true
		set_state(State.ATTACK_COOLDOWN)

# ================================
# DETECCIÓN (Se mantienen)
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
	
	if current_hp > 0:
		velocity.y = 1.0 
	if current_hp <= 0:
		set_state(State.DEAD)
	else:
		set_state(State.DAMAGE)

# **LÓGICA DE SALIDA DEL DAÑO **
func _on_damage_recovery_timeout():
	if current_state == State.DAMAGE:
		cooldown_timer = max(cooldown_timer, post_damage_recovery_pause)
		
		# Decidir a dónde volver
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
			velocity = Vector3.ZERO

		State.WANDER:
			wander_target = Vector3.ZERO

		State.ATTACKING:
			_execute_attack()

		State.ATTACK_COOLDOWN:
			_start_post_attack_wait()

		State.DAMAGE:
			damage_recovery_timer.start(damage_duration) 
			
			velocity.x = move_toward(velocity.x, 0, 10.0) 
			velocity.z = move_toward(velocity.z, 0, 10.0)
			
			if animated_sprite.sprite_frames.has_animation("damage"):
				animated_sprite.play("damage")
			
		State.DEAD:
			velocity = Vector3.ZERO
			if animated_sprite.sprite_frames.has_animation("death"):
				animated_sprite.play("death")
				await animated_sprite.animation_finished
			queue_free()

# ================================
# UTILIDADES (Se mantienen)
# ================================
func _look_at_player():
	if player_ref:
		var dir = player_ref.global_position - global_position
		animated_sprite.flip_h = dir.x < 0

func _update_animations():
	if current_state in [State.DEAD, State.DAMAGE, State.ATTACKING, State.ATTACK_COOLDOWN]:
		return

	var anim = "idle"
	if velocity.length() > 0.05:
		anim = "walk"

	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)
