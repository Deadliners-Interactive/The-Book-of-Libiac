## Player character controller with state machine (FSM).
##
## Handles movement, combat, rolling, health, and level transitions.
## Uses a finite state machine for state management.
extends CharacterBody3D


# ==============================================================================
# Signals
# ==============================================================================

signal health_changed(current: float, max_value: float)
signal max_health_changed(max_value: float)
signal keys_changed(count: int)
signal notification_requested(message: String)
signal immediate_notification_requested(message: String)
signal state_changed(previous: int, current: int)


# ==============================================================================
# Enums
# ==============================================================================

enum State {
	NORMAL,
	ATTACKING,
	ROLLING,
	DAMAGE,
}


# ==============================================================================
# Constants
# ==============================================================================

const KB_MULTIPLIER: float = 5.0


# ==============================================================================
# Export variables - Config
# ==============================================================================

@export_group("Config")
@export var player_config: PlayerConfig


# ==============================================================================
# Export variables - Debug
# ==============================================================================

@export_group("Debug")
@export var fsm_debug_logs: bool = false


# ==============================================================================
# Export variables - Movement
# ==============================================================================

@export_group("Movement")
@export var move_speed: float = 1.0
@export var jump_speed: float = 2.0
@export var gravity_multiplier: float = 1.0
@export var jump_coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var fall_gravity_multiplier: float = 1.15
@export var jump_release_gravity_multiplier: float = 1.35
@export var air_animation_delay: float = 0.08
@export var ground_snap_length: float = 0.34
@export var max_floor_angle_degrees: float = 58.0
@export var terrain_floor_stop_on_slope: bool = false
@export var terrain_floor_constant_speed: bool = true
@export var collision_safe_margin: float = 0.0002


# ==============================================================================
# Export variables - Combat
# ==============================================================================

@export_group("Combat")
@export var attack_damage: int = 10
@export var attack_movement_multiplier: float = 0.6
@export var attack_hit_delay: float = 0.1


# ==============================================================================
# Export variables - Health
# ==============================================================================

@export_group("Health")
@export var max_health: float = 30.0
@export var invulnerability_time: float = 1.0
@export var damage_visual_time: float = 0.5


# ==============================================================================
# Export variables - Roll
# ==============================================================================

@export_group("Roll")
@export var roll_speed: float = 3.0
@export var roll_duration: float = 0.4
@export var roll_cooldown: float = 0.2


# ==============================================================================
# Regular variables
# ==============================================================================

var current_health: float
var current_state: State = State.NORMAL
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var key_count: int = 0

var _is_facing_right: bool = true
var _last_move_animation: StringName = &"move_sides"
var _last_move_input: Vector2 = Vector2.RIGHT
var _attack_combo_step: int = 0
var _input_buffer: String = ""
var _enemies_hit: Array = []
var _is_invulnerable: bool = false

var _damage_knockback_timer: Timer = Timer.new()
var _damage_visual_timer: Timer = Timer.new()
var _roll_cooldown_timer: Timer = Timer.new()
var _notification_cooldown: Dictionary = {}
var _notification_cooldown_time: float = 1.0
var _last_time_on_floor: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_consumed: bool = false
var _is_jumping: bool = false
var _airborne_time: float = 0.0


# ==============================================================================
# Onready variables
# ==============================================================================

@onready var _animated_sprite: AnimatedSprite3D = $Sprite3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _attack_collision: CollisionShape3D = $AttackArea/CollisionShape3D
@onready var _detection_area: Area3D = $DetectionArea


# ==============================================================================
# Built-in methods
# ==============================================================================

func _ready() -> void:
	_apply_config()
	_setup_terrain_motion()
	current_health = max_health
	_attack_collision.disabled = true
	
	add_to_group("player")
	_attack_area.add_to_group("hitbox_player")
	
	# Setup timers
	add_child(_roll_cooldown_timer)
	_roll_cooldown_timer.one_shot = true
	
	add_child(_damage_knockback_timer)
	_damage_knockback_timer.one_shot = true
	_damage_knockback_timer.timeout.connect(func() -> void:
		if current_state == State.DAMAGE:
			velocity = Vector3.ZERO
			call_deferred("set_state", State.NORMAL)
	)
	
	add_child(_damage_visual_timer)
	_damage_visual_timer.one_shot = true
	_damage_visual_timer.timeout.connect(func() -> void:
		_is_invulnerable = false
	)
	
	# Connect signals
	_animated_sprite.animation_finished.connect(_on_animation_finished)
	
	if not _attack_area.body_entered.is_connected(_on_attack_hit):
		_attack_area.body_entered.connect(_on_attack_hit)
	
	# Load saved state if exists
	if GameState.player_health > 0:
		GameState.load_player_state(self)
	
	# Connect level change detection
	if has_node("DetectionArea"):
		_detection_area.area_entered.connect(_on_area_entered_player)
	else:
		push_warning("Falta nodo DetectionArea para cambio de nivel")

	refresh_ui_state()


func _physics_process(delta: float) -> void:
	_update_jump_timers(delta)
	_update_current_state(delta)
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * _get_air_gravity_multiplier() * delta
	else:
		if current_state == State.DAMAGE and _damage_knockback_timer.is_stopped():
			velocity.y = 0
		else:
			_apply_terrain_adhesion()

	if velocity.y <= 0.0 and current_state != State.ROLLING and not _is_jumping:
		apply_floor_snap()
	
	move_and_slide()
	if _resolve_slope_edge_block():
		move_and_slide()
	_update_animations()


# ==============================================================================
# Public methods - Input handling
# ==============================================================================

func add_key() -> void:
	key_count += 1
	keys_changed.emit(key_count)
	show_notification("Llave conseguida (%d)" % key_count)


func use_key() -> bool:
	if key_count > 0:
		key_count -= 1
		keys_changed.emit(key_count)
		return true
	else:
		show_notification("Necesitas una llave!")
		return false


# ==============================================================================
# Public methods - Health & Combat
# ==============================================================================

func take_damage_hearts(damage_amount: float) -> void:
	take_damage_hearts_with_knockback(damage_amount, Vector3.ZERO, 0.0)


func take_damage_hearts_with_knockback(
		damage_amount: float,
		knockback_direction: Vector3,
		knockback_force: float
) -> void:
	if current_state == State.ROLLING or _is_invulnerable:
		return
	
	current_health -= damage_amount
	current_health = max(0.0, current_health)
	
	if current_state != State.DAMAGE:
		set_state(State.DAMAGE)

	health_changed.emit(current_health, max_health)
	
	if knockback_force > 0:
		if _damage_knockback_timer.is_stopped():
			velocity.x = knockback_direction.x * knockback_force * KB_MULTIPLIER
			velocity.z = knockback_direction.z * knockback_force * KB_MULTIPLIER
			velocity.y = min(velocity.y + knockback_force * 3.0, 5.0)
		
		_damage_knockback_timer.start(0.35)
	else:
		_damage_knockback_timer.start(0.1)
	
	if current_health <= 0:
		die()


func heal(amount: float) -> void:
	if current_health < max_health:
		var previous_health: float = current_health
		current_health += amount
		
		if current_health > max_health:
			current_health = max_health
		
		var actual_heal: float = current_health - previous_health
		var heart_containers: int = int(floor(actual_heal / 10.0))
		var partial_heart: float = fmod(actual_heal, 10.0)
		
		if actual_heal > 0:
			if heart_containers >= 1:
				show_notification("Recuperaste %d pluma(s) de vida" % heart_containers)
			elif partial_heart > 0:
				show_notification("Medio corazon recuperado")

		health_changed.emit(current_health, max_health)


func increase_max_health(amount: float) -> void:
	max_health += amount
	current_health = max_health
	max_health_changed.emit(max_health)
	health_changed.emit(current_health, max_health)
	
	show_notification("Obtuviste una vida extra!")


func die() -> void:
	if is_instance_valid(GameOverHandler):
		GameOverHandler.handle_player_death(self)
	else:
		get_tree().call_deferred("reload_current_scene")


# ==============================================================================
# Public methods - UI notifications
# ==============================================================================

func refresh_ui_state() -> void:
	max_health_changed.emit(max_health)
	health_changed.emit(current_health, max_health)
	keys_changed.emit(key_count)


func show_notification(message: String) -> void:
	var current_time: int = Time.get_ticks_msec()
	
	if _notification_cooldown.has(message):
		var last_shown_time: int = _notification_cooldown[message]
		if current_time - last_shown_time < int(_notification_cooldown_time * 1000):
			return
	
	_notification_cooldown[message] = current_time
	notification_requested.emit(message)


func show_immediate_notification(message: String) -> void:
	immediate_notification_requested.emit(message)


# ==============================================================================
# Private methods - Input handling
# ==============================================================================

func _handle_actions_input() -> void:
	if Input.is_action_just_pressed("attack"):
		set_state(State.ATTACKING)
	elif Input.is_action_just_pressed("roll") and _roll_cooldown_timer.is_stopped():
		set_state(State.ROLLING)


func _handle_buffer_input() -> void:
	if Input.is_action_just_pressed("attack"):
		_input_buffer = "attack"
	elif Input.is_action_just_pressed("roll"):
		_input_buffer = "roll"
		if _roll_cooldown_timer.is_stopped():
			set_state(State.ROLLING)


# ==============================================================================
# Private methods - Movement
# ==============================================================================

func _handle_move(speed_mult: float = 1.0) -> void:
	if not _damage_knockback_timer.is_stopped():
		return

	var input_dir: Vector2 = Input.get_vector(
			"move_left",
			"move_right",
			"move_up",
			"move_down"
	)
	var direction: Vector3 = (
			transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()
	
	var final_speed: float = move_speed * speed_mult
	
	if direction:
		_update_facing_from_input(input_dir)
		velocity.x = direction.x * final_speed
		velocity.z = direction.z * final_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, final_speed)
		velocity.z = move_toward(velocity.z, 0.0, final_speed)


func _handle_jump() -> void:
	if _can_start_jump():
		_start_jump()


func _apply_roll_physics() -> void:
	if current_state == State.ROLLING:
		var current_vel_xz: float = Vector3(velocity.x, 0, velocity.z).length()
		
		if current_vel_xz < 0.1:
			var facing_direction: Vector3 = _get_last_facing_direction_3d()
			velocity.x = facing_direction.x * roll_speed
			velocity.z = facing_direction.z * roll_speed
		else:
			var roll_dir_xz: Vector3 = Vector3(velocity.x, 0, velocity.z).normalized()
			velocity.x = roll_dir_xz.x * roll_speed
			velocity.z = roll_dir_xz.z * roll_speed


func _flip_sprite(x_velocity: float) -> void:
	if abs(x_velocity) < 0.1:
		return
	
	var moving_right: bool = x_velocity > 0
	_is_facing_right = moving_right
	_animated_sprite.flip_h = not _is_facing_right
	_attack_area.scale.x = 1.0 if _is_facing_right else -1.0


func _update_facing_from_input(input_dir: Vector2) -> void:
	if input_dir == Vector2.ZERO:
		return

	_last_move_input = input_dir.normalized()

	if abs(input_dir.x) >= abs(input_dir.y):
		_last_move_animation = &"move_sides"
		_flip_sprite(input_dir.x)
		return

	if input_dir.y < 0.0:
		_last_move_animation = &"move_up"
	else:
		_last_move_animation = &"move_down"

	# Keep vertical animations unmirrored.
	_animated_sprite.flip_h = false


func _get_last_facing_direction_3d() -> Vector3:
	if _last_move_input.length_squared() > 0.0:
		return Vector3(_last_move_input.x, 0.0, _last_move_input.y).normalized()

	var side_direction: float = 1.0 if _is_facing_right else -1.0
	return Vector3(side_direction, 0.0, 0.0)


# ==============================================================================
# Private methods - State management
# ==============================================================================

func set_state(new_state: State) -> void:
	var previous_state: State = current_state

	if new_state == previous_state:
		return

	if not _is_transition_allowed(previous_state, new_state):
		if fsm_debug_logs:
			push_warning(
				"Player FSM: blocked transition %s -> %s"
				% [_state_to_string(previous_state), _state_to_string(new_state)]
			)
		return

	_exit_state(previous_state)
	current_state = new_state
	_enter_state(new_state)

	if fsm_debug_logs:
		print(
			"Player FSM: %s -> %s"
			% [_state_to_string(previous_state), _state_to_string(current_state)]
		)

	state_changed.emit(previous_state, current_state)


func _update_current_state(_delta: float) -> void:
	match current_state:
		State.NORMAL:
			_update_state_normal()
		State.ATTACKING:
			_update_state_attacking()
		State.ROLLING:
			_update_state_rolling()
		State.DAMAGE:
			_update_state_damage()


func _update_state_normal() -> void:
	_handle_move()
	_handle_jump()
	_handle_actions_input()


func _update_state_attacking() -> void:
	if _damage_knockback_timer.is_stopped():
		_handle_move(attack_movement_multiplier)
	_handle_buffer_input()


func _update_state_rolling() -> void:
	_apply_roll_physics()


func _update_state_damage() -> void:
	pass


func _enter_state(state: State) -> void:
	match state:
		State.NORMAL:
			_enter_state_normal()
		State.ATTACKING:
			_start_attack()
		State.ROLLING:
			_start_roll()
		State.DAMAGE:
			_start_damage()


func _exit_state(state: State) -> void:
	match state:
		State.ATTACKING:
			_attack_collision.set_deferred("disabled", true)
			_animated_sprite.speed_scale = 1.0


func _enter_state_normal() -> void:
	if not _damage_knockback_timer.is_stopped():
		return

	if _input_buffer == "attack":
		_input_buffer = ""
		set_state(State.ATTACKING)
	elif _input_buffer == "roll" and _roll_cooldown_timer.is_stopped():
		_input_buffer = ""
		set_state(State.ROLLING)


func _is_transition_allowed(from_state: State, to_state: State) -> bool:
	if not player_config:
		return _is_transition_allowed_default(from_state, to_state)

	match from_state:
		State.NORMAL:
			match to_state:
				State.ATTACKING:
					return player_config.allow_normal_to_attacking
				State.ROLLING:
					return player_config.allow_normal_to_rolling
				State.DAMAGE:
					return player_config.allow_normal_to_damage
		State.ATTACKING:
			match to_state:
				State.NORMAL:
					return player_config.allow_attacking_to_normal
				State.ROLLING:
					return player_config.allow_attacking_to_rolling
				State.DAMAGE:
					return player_config.allow_attacking_to_damage
		State.ROLLING:
			match to_state:
				State.NORMAL:
					return player_config.allow_rolling_to_normal
				State.DAMAGE:
					return player_config.allow_rolling_to_damage
		State.DAMAGE:
			if to_state == State.NORMAL:
				return player_config.allow_damage_to_normal

	return false


func _is_transition_allowed_default(from_state: State, to_state: State) -> bool:
	match from_state:
		State.NORMAL:
			return to_state in [State.ATTACKING, State.ROLLING, State.DAMAGE]
		State.ATTACKING:
			return to_state in [State.NORMAL, State.ROLLING, State.DAMAGE]
		State.ROLLING:
			return to_state in [State.NORMAL, State.DAMAGE]
		State.DAMAGE:
			return to_state == State.NORMAL

	return false


func _state_to_string(state: State) -> String:
	match state:
		State.NORMAL:
			return "NORMAL"
		State.ATTACKING:
			return "ATTACKING"
		State.ROLLING:
			return "ROLLING"
		State.DAMAGE:
			return "DAMAGE"

	return "UNKNOWN"


# ==============================================================================
# Private methods - Combat
# ==============================================================================

func _start_attack() -> void:
	_enemies_hit.clear()
	_animated_sprite.speed_scale = 2.0
	
	if _attack_combo_step == 0:
		_animated_sprite.play("attack")
		_attack_combo_step = 1
	else:
		_animated_sprite.play_backwards("attack")
		_attack_combo_step = 0
	
	get_tree().create_timer(attack_hit_delay).timeout.connect(_on_hitbox_activate)


func _on_hitbox_activate() -> void:
	if current_state != State.ATTACKING:
		return
	
	_attack_collision.set_deferred("disabled", false)
	
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if current_state == State.ATTACKING:
			_attack_collision.set_deferred("disabled", true)
	)


func _on_attack_hit(body: Node3D) -> void:
	if _attack_collision.disabled:
		return
	
	if (body.has_method("take_damage") and body != self
			and body not in _enemies_hit):
		_enemies_hit.append(body)
		body.take_damage(attack_damage)


func _start_roll() -> void:
	_is_invulnerable = true
	_input_buffer = ""
	_animated_sprite.speed_scale = 2.0

	var roll_animation: StringName = _get_roll_animation_name(Vector3(velocity.x, 0.0, velocity.z))
	if not _play_animation_with_fallback(roll_animation, &"roll"):
		var roll_timer: SceneTreeTimer = get_tree().create_timer(roll_duration)
		roll_timer.timeout.connect(func() -> void:
			_is_invulnerable = false
			_roll_cooldown_timer.start(roll_cooldown)
			set_state(State.NORMAL)
		)


func _start_damage() -> void:
	_is_invulnerable = true
	_damage_visual_timer.start(invulnerability_time)
	_animated_sprite.modulate = Color(1, 0.5, 0.5, 1)
	
	get_tree().create_timer(damage_visual_time).timeout.connect(func() -> void:
		if _is_invulnerable:
			_animated_sprite.modulate = Color.WHITE
	)


# ==============================================================================
# Private methods - Animation
# ==============================================================================

func _update_animations() -> void:
	if current_state in [State.ATTACKING, State.ROLLING, State.DAMAGE]:
		return
	
	if not is_on_floor():
		if _airborne_time < air_animation_delay:
			if velocity.x != 0 or velocity.z != 0:
				var ground_move_animation: StringName = _get_move_animation_name(Vector3(velocity.x, 0.0, velocity.z))
				_play_animation_with_fallback(ground_move_animation, &"run")
			else:
				_play_idle_from_last_direction()
			return

		_animated_sprite.speed_scale = 2.0
		if _is_jumping:
			_animated_sprite.play("jump")
		else:
			_animated_sprite.play("fall")
		return
	
	_animated_sprite.speed_scale = 1.0
	if velocity.x != 0 or velocity.z != 0:
		var move_animation: StringName = _get_move_animation_name(Vector3(velocity.x, 0.0, velocity.z))
		_last_move_animation = move_animation
		_play_animation_with_fallback(move_animation, &"run")
	else:
		_play_idle_from_last_direction()


func _on_animation_finished() -> void:
	if _animated_sprite.animation == "attack":
		set_state(State.NORMAL)
	elif String(_animated_sprite.animation).begins_with("roll"):
		_is_invulnerable = false
		_roll_cooldown_timer.start(roll_cooldown)
		set_state(State.NORMAL)


func _get_move_animation_name(direction: Vector3) -> StringName:
	var horizontal: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.0001:
		return &"move_sides"

	if abs(horizontal.z) > abs(horizontal.x):
		if horizontal.z < 0.0:
			return &"move_up"
		return &"move_down"

	return &"move_sides"


func _get_roll_animation_name(direction: Vector3) -> StringName:
	var horizontal: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.0001:
		match _last_move_animation:
			&"move_up":
				return &"roll_up"
			&"move_down":
				return &"roll_down"
			_:
				return &"roll_sides"

	if abs(horizontal.z) > abs(horizontal.x):
		if horizontal.z < 0.0:
			return &"roll_up"
		return &"roll_down"

	return &"roll_sides"


func _play_animation_with_fallback(preferred: StringName, fallback: StringName) -> bool:
	if _animated_sprite.sprite_frames.has_animation(preferred):
		_animated_sprite.play(preferred)
		return true

	if _animated_sprite.sprite_frames.has_animation(fallback):
		_animated_sprite.play(fallback)
		return true

	return false


func _play_idle_from_last_direction() -> void:
	if _play_animation_with_fallback(_last_move_animation, &"move_sides"):
		_animated_sprite.stop()
		_animated_sprite.frame = 0


# ==============================================================================
# Private methods - Configuration
# ==============================================================================

func _apply_config() -> void:
	if not player_config:
		return

	move_speed = player_config.move_speed
	jump_speed = player_config.jump_speed
	gravity_multiplier = player_config.gravity_multiplier
	jump_coyote_time = player_config.jump_coyote_time
	jump_buffer_time = player_config.jump_buffer_time
	fall_gravity_multiplier = player_config.fall_gravity_multiplier
	jump_release_gravity_multiplier = player_config.jump_release_gravity_multiplier
	air_animation_delay = player_config.air_animation_delay
	ground_snap_length = player_config.ground_snap_length
	max_floor_angle_degrees = player_config.max_floor_angle_degrees
	terrain_floor_stop_on_slope = player_config.floor_stop_on_slope
	terrain_floor_constant_speed = player_config.floor_constant_speed
	collision_safe_margin = player_config.collision_safe_margin

	attack_damage = player_config.attack_damage
	attack_movement_multiplier = player_config.attack_movement_multiplier
	attack_hit_delay = player_config.attack_hit_delay

	max_health = player_config.max_health
	invulnerability_time = player_config.invulnerability_time
	damage_visual_time = player_config.damage_visual_time

	roll_speed = player_config.roll_speed
	roll_duration = player_config.roll_duration
	roll_cooldown = player_config.roll_cooldown


func _update_jump_timers(delta: float) -> void:
	if is_on_floor():
		_last_time_on_floor = jump_coyote_time
		_jump_consumed = false
		_is_jumping = false
		_airborne_time = 0.0
	else:
		_last_time_on_floor = max(_last_time_on_floor - delta, 0.0)
		_airborne_time += delta

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)


func _can_start_jump() -> bool:
	if _jump_consumed:
		return false

	if _jump_buffer_timer <= 0.0:
		return false

	return _last_time_on_floor > 0.0


func _start_jump() -> void:
	velocity.y = jump_speed
	_jump_buffer_timer = 0.0
	_last_time_on_floor = 0.0
	_jump_consumed = true
	_is_jumping = true


func _get_air_gravity_multiplier() -> float:
	if velocity.y < 0.0:
		return fall_gravity_multiplier

	if velocity.y > 0.0 and not Input.is_action_pressed("jump"):
		return jump_release_gravity_multiplier

	return 1.0


func _setup_terrain_motion() -> void:
	up_direction = Vector3.UP
	floor_snap_length = ground_snap_length
	floor_max_angle = deg_to_rad(max_floor_angle_degrees)
	self.floor_stop_on_slope = terrain_floor_stop_on_slope
	self.floor_constant_speed = terrain_floor_constant_speed
	safe_margin = collision_safe_margin


func _apply_terrain_adhesion() -> void:
	if not is_on_floor():
		return

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() <= 0.0:
		return

	var floor_normal: Vector3 = get_floor_normal()
	var adjusted_velocity: Vector3 = horizontal_velocity.slide(floor_normal)
	velocity.x = adjusted_velocity.x
	velocity.z = adjusted_velocity.z


func _resolve_slope_edge_block() -> bool:
	if not is_on_floor() or not is_on_wall():
		return false

	var input_dir: Vector2 = Input.get_vector(
			"move_left",
			"move_right",
			"move_up",
			"move_down"
	)
	if input_dir == Vector2.ZERO:
		return false

	for i: int in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		if collision == null:
			continue

		var normal: Vector3 = collision.get_normal()
		if normal.y > 0.05 and normal.y < 0.95:
			var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
			if horizontal_velocity.length_squared() <= 0.0:
				return false

			var adjusted_velocity: Vector3 = horizontal_velocity.slide(normal)
			velocity.x = adjusted_velocity.x
			velocity.z = adjusted_velocity.z
			velocity.y = max(velocity.y, 0.18)
			return true

	return false


# ==============================================================================
# Private methods - Level transitions
# ==============================================================================

func _on_area_entered_player(area: Area3D) -> void:
	"""Detecta cuando el jugador entra en un área de cambio de nivel."""
	if area.is_in_group("level_trigger"):
		if area.has_method("trigger_level_change"):
			area.trigger_level_change(self)
