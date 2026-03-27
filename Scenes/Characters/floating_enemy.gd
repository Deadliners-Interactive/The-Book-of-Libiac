## Floating ranged enemy that patrols and shoots projectiles at the player.
extends CharacterBody3D

# ==============================================================================
# Enums
# ==============================================================================

enum State { IDLE, WANDER, CHASE, SHOOTING, COOLDOWN, DAMAGE, DEAD }

# ==============================================================================
# Exports - Enemy Stats
# ==============================================================================

@export_group("Enemy Stats")
@export var max_hp: int = 20
@export var defense: int = 0
@export var move_speed: float = 1.5
@export var chase_speed: float = 3.0

# ==============================================================================
# Exports - Range Attack
# ==============================================================================

@export_group("Range Attack")
@export var shoot_range: float = 5.0
@export var shoot_cooldown: float = 2.0
@export var attack_damage: float = 5.0
@export var projectile_speed: float = 8.0
@export var projectile_scene: PackedScene

# ==============================================================================
# Exports - Patrol
# ==============================================================================

@export_group("Patrol")
@export var wander_radius: float = 4.0
@export var lost_player_distance: float = 10.0
@export var vertical_float_amplitude: float = 0.5
@export var vertical_float_speed: float = 2.0

# ==============================================================================
# Exports - Damage
# ==============================================================================

@export_group("Damage")
@export var damage_duration: float = 0.2
@export var post_damage_recovery_pause: float = 0.3

# ==============================================================================
# Member Variables
# ==============================================================================

var _current_state: State = State.IDLE
var _current_hp: int
var _player_ref: CharacterBody3D = null
var _cooldown_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _initial_y: float

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var _detection_area: Area3D = $DetectionArea
@onready var _projectile_spawn_point: Node3D = $ProjectileSpawnPoint

var _damage_recovery_timer: Timer


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	_current_hp = max_hp
	_initial_y = global_position.y

	_detection_area.body_entered.connect(_on_detection_enter)
	_detection_area.body_exited.connect(_on_detection_exit)

	_damage_recovery_timer = Timer.new()
	add_child(_damage_recovery_timer)
	_damage_recovery_timer.one_shot = true
	_damage_recovery_timer.timeout.connect(_on_damage_recovery_timeout)

	set_state(State.WANDER)


func _physics_process(delta: float) -> void:
	if _current_state == State.DEAD:
		return

	var float_movement: float = velocity.y
	velocity.y = 0

	if _cooldown_timer > 0:
		_cooldown_timer -= delta

	_state_machine(delta)

	# Vertical floating logic
	var new_y: float = _initial_y + sin(Time.get_ticks_msec() / 1000.0 * vertical_float_speed) * vertical_float_amplitude
	var float_vel: float = (new_y - global_position.y) / delta
	velocity.y = float_vel

	move_and_slide()
	_update_animations()


# ==============================================================================
# Public Methods
# ==============================================================================

func set_state(s: State) -> void:
	_current_state = s

	match s:
		State.IDLE:
			velocity.x = 0
			velocity.z = 0

		State.WANDER:
			_wander_target = Vector3.ZERO

		State.SHOOTING:
			_execute_shoot()

		State.COOLDOWN:
			_start_post_attack_wait()

		State.DAMAGE:
			_damage_recovery_timer.start(damage_duration)
			velocity.x = move_toward(velocity.x, 0, 10.0)
			velocity.z = move_toward(velocity.z, 0, 10.0)

			if _animated_sprite.sprite_frames.has_animation("damage"):
				_animated_sprite.play("damage")
			else:
				_animated_sprite.modulate = Color.RED

		State.DEAD:
			velocity = Vector3.ZERO
			if _animated_sprite.sprite_frames.has_animation("death"):
				_animated_sprite.play("death")
				await _animated_sprite.animation_finished
			queue_free()


func take_damage(amount: int) -> void:
	_current_hp -= max(amount - defense, 1)

	if _current_hp > 0:
		velocity.y = 1.0

	if _current_hp <= 0:
		set_state(State.DEAD)
	else:
		set_state(State.DAMAGE)


# ==============================================================================
# Private Methods - State Machine
# ==============================================================================

func _state_machine(delta: float) -> void:
	match _current_state:
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
			velocity.x = move_toward(velocity.x, 0, 5 * delta)
			velocity.z = move_toward(velocity.z, 0, 5 * delta)


func _process_wander() -> void:
	if _player_ref and is_instance_valid(_player_ref):
		set_state(State.CHASE)
		return

	if _wander_target == Vector3.ZERO or global_position.distance_to(_wander_target) < 0.5:
		var angle: float = randf_range(0, TAU)
		var dist: float = randf_range(1.0, wander_radius)

		_wander_target = Vector3(global_position.x, _initial_y, global_position.z) + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

	var dir: Vector3 = (_wander_target - global_position).normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

	_initial_y = global_position.y - sin(Time.get_ticks_msec() / 1000.0 * vertical_float_speed) * vertical_float_amplitude


func _process_chase() -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		_player_ref = null
		set_state(State.WANDER)
		return

	var dist: float = global_position.distance_to(_player_ref.global_position)

	if dist > lost_player_distance:
		_player_ref = null
		set_state(State.WANDER)
		return

	if dist <= shoot_range and _cooldown_timer <= 0:
		set_state(State.SHOOTING)
		return

	var target_pos_flat: Vector3 = Vector3(_player_ref.global_position.x, global_position.y, _player_ref.global_position.z)
	var dir: Vector3 = (target_pos_flat - global_position).normalized()

	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	_look_at_player()


# ==============================================================================
# Private Methods - Attack
# ==============================================================================

func _execute_shoot() -> void:
	velocity.x = 0
	velocity.z = 0

	if not _player_ref or not is_instance_valid(_player_ref):
		set_state(State.CHASE)
		return

	_look_at_player()

	if _animated_sprite.sprite_frames.has_animation("attack"):
		_animated_sprite.play("attack")
	else:
		_animated_sprite.play("idle")

	await get_tree().create_timer(0.2).timeout

	if not _player_ref or not is_instance_valid(_player_ref) or _current_state != State.SHOOTING:
		_cooldown_timer = shoot_cooldown
		set_state(State.COOLDOWN)
		return

	_spawn_projectile()

	if _animated_sprite.sprite_frames.has_animation("attack"):
		await _animated_sprite.animation_finished

	_cooldown_timer = shoot_cooldown
	set_state(State.COOLDOWN)


func _spawn_projectile() -> void:
	if projectile_scene == null:
		push_error("Projectile Scene no está asignado en el inspector.")
		return

	if not _player_ref or not is_instance_valid(_player_ref):
		push_warning("Intento de disparar sin objetivo válido.")
		return

	var projectile: Node = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	if not is_instance_valid(_projectile_spawn_point):
		push_error("ProjectileSpawnPoint no es válido.")
		projectile.queue_free()
		return

	projectile.global_position = _projectile_spawn_point.global_position

	var shoot_dir: Vector3 = (_player_ref.global_position - _projectile_spawn_point.global_position).normalized()

	if projectile.has_method("initialize"):
		projectile.initialize(shoot_dir, projectile_speed, attack_damage, self)


func _start_post_attack_wait() -> void:
	velocity.x = 0
	velocity.z = 0
	await get_tree().create_timer(post_damage_recovery_pause).timeout
	set_state(State.CHASE)


# ==============================================================================
# Private Methods - Damage
# ==============================================================================

func _on_damage_recovery_timeout() -> void:
	if _animated_sprite.modulate == Color.RED:
		_animated_sprite.modulate = Color.WHITE

	if _current_state == State.DAMAGE:
		_cooldown_timer = max(_cooldown_timer, post_damage_recovery_pause)

		if _player_ref and is_instance_valid(_player_ref):
			set_state(State.CHASE)
		else:
			set_state(State.WANDER)


# ==============================================================================
# Private Methods - Utilities
# ==============================================================================

func _look_at_player() -> void:
	if _player_ref and is_instance_valid(_player_ref):
		var dir: Vector3 = _player_ref.global_position - global_position
		_animated_sprite.flip_h = dir.x < 0


func _update_animations() -> void:
	if _current_state in [State.DEAD, State.DAMAGE, State.SHOOTING, State.COOLDOWN]:
		return

	var anim: String = "idle"
	var horizontal_velocity: float = Vector3(velocity.x, 0, velocity.z).length()

	if horizontal_velocity > 0.1:
		anim = "walk"

	if _animated_sprite.sprite_frames.has_animation(anim):
		_animated_sprite.play(anim)


# ==============================================================================
# Private Methods - Signal Handlers
# ==============================================================================

func _on_detection_enter(body: Node) -> void:
	if body.is_in_group("player"):
		_player_ref = body
		set_state(State.CHASE)


func _on_detection_exit(body: Node) -> void:
	if _player_ref == body:
		_player_ref = null
		set_state(State.WANDER)
