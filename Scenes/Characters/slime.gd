## Slime enemy with state machine AI, pursuit behavior, and splitting mechanic.
## Tracks player, chases, stalks, and attacks. When killed, splits into smaller slimes.
class_name Slime
extends CharacterBody3D

# ==============================================================================
# Enums
# ==============================================================================

enum State { IDLE, WANDER, CHASE, PURSUIT, STALK, APPROACH, ATTACKING, RETREAT, DAMAGE, DEAD }

# ==============================================================================
# Exports - External Resources
# ==============================================================================

@export var small_slime_scene: PackedScene

# ==============================================================================
# Exports - Enemy Core Stats
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

# ==============================================================================
# Exports - Loot Settings
# ==============================================================================

@export_group("Loot Settings")
@export var loot_scale: Vector3 = Vector3(2.0, 2.0, 2.0)
@export var loot_drop_chance: float = 0.6
@export var possible_loot_scenes: Array[PackedScene]

# ==============================================================================
# Exports - Chaser Behavior
# ==============================================================================

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

# ==============================================================================
# Exports - Small Slime Settings
# ==============================================================================

@export_group("Small Slime Settings")
@export var spawn_invulnerability_time: float = 2.0
@export var small_slime_attack_damage: float = 5
@export var small_slime_approach_range: float = 0.5
@export var startup_attack_delay: float = 1.0
@export var split_rebound_distance: float = 1.5
@export var split_rebound_force: float = 2.5

# ==============================================================================
# Member Variables
# ==============================================================================

var _current_state: State = State.IDLE
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_hp: int
var _is_facing_right: bool = true
var _player_ref: Node3D = null
var _has_detected_player: bool = false

var _cooldown_timer: float = 0.0
var _stalk_clockwise: bool = true
var _wander_target: Vector3 = Vector3.ZERO
var _is_jumping_to_attack: bool = false
var _attack_was_successful: bool = false

var _can_jump: bool = true
var _pending_horizontal_velocity: Vector3 = Vector3.ZERO
var _is_splitting: bool = false

var _is_invulnerable_spawn: bool = false
var _can_attack: bool = true

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _detection_area: Area3D = $DetectionArea

var _jump_timer: Timer
var _retreat_timer: Timer
var _startup_timer: Timer
var _invulnerability_timer: Timer


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	_current_hp = max_hp

	add_to_group("slime")

	# Create timers
	_retreat_timer = Timer.new()
	add_child(_retreat_timer)
	_retreat_timer.one_shot = true
	_retreat_timer.timeout.connect(_on_retreat_timer_timeout)

	_jump_timer = Timer.new()
	add_child(_jump_timer)
	_jump_timer.one_shot = true
	_jump_timer.timeout.connect(_on_jump_timer_timeout)

	_invulnerability_timer = Timer.new()
	add_child(_invulnerability_timer)
	_invulnerability_timer.one_shot = true
	_invulnerability_timer.timeout.connect(_on_invulnerability_timeout)

	_startup_timer = Timer.new()
	add_child(_startup_timer)
	_startup_timer.one_shot = true
	_startup_timer.timeout.connect(_on_startup_timeout)

	_setup_detection_area()
	_update_visual_scale()

	if _detection_area:
		_detection_area.body_entered.connect(_on_detection_area_body_entered)
		_detection_area.body_exited.connect(_on_detection_area_body_exited)

	if _attack_area:
		_attack_area.body_entered.connect(_on_attack_hit_player)
		var attack_collision = _attack_area.get_node_or_null("CollisionShape3D")
		if attack_collision:
			attack_collision.disabled = true

	_stalk_clockwise = randf() > 0.5

	if size < 1.0:
		_activate_spawn_invulnerability()
		_startup_delay()
	else:
		_can_attack = true

	set_state(State.WANDER)


func _physics_process(delta: float) -> void:
	if _current_state == State.DEAD or _is_splitting:
		return

	if _current_state not in [State.DAMAGE, State.ATTACKING]:
		if not is_on_floor():
			velocity.y -= _gravity * gravity_multiplier * delta
		else:
			velocity.y = 0

	if _is_jumping_to_attack and _current_state != State.APPROACH:
		_is_jumping_to_attack = false

	if _can_jump and _current_state not in [State.APPROACH, State.RETREAT, State.DAMAGE, State.ATTACKING]:
		_start_movement_jump()

	if _cooldown_timer > 0:
		_cooldown_timer -= delta

	if _player_ref and _current_state not in [State.WANDER, State.IDLE, State.DEAD, State.DAMAGE]:
		_look_at_player()

	if _current_state != State.DAMAGE:
		_state_machine(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 5.0 * delta)
		velocity.y = move_toward(velocity.y, 0, 10.0 * delta)

	move_and_slide()
	_update_animations()

# ==============================================================================
# Public Methods
# ==============================================================================

func set_state(new_state: State) -> void:
	if _current_state == new_state:
		return

	if _current_state == State.ATTACKING:
		var attack_collision = _attack_area.get_node_or_null("CollisionShape3D")
		if attack_collision:
			attack_collision.set_deferred("disabled", true)

	_current_state = new_state

	match _current_state:
		State.IDLE:
			_cooldown_timer = randf_range(0.5, 1.5)
			_pending_horizontal_velocity = Vector3.ZERO
			_can_jump = true

		State.WANDER:
			_start_wander()

		State.ATTACKING:
			if _can_attack:
				_execute_attack()
				_can_jump = false
			else:
				set_state(State.CHASE)

		State.RETREAT:
			_start_retreat()
			_can_jump = false

		State.DAMAGE:
			_start_damage()
			_can_jump = false

		State.DEAD:
			if size < 1.0:
				_start_dead()
			else:
				_start_death_animation_and_split()
			_can_jump = false
			if _jump_timer:
				_jump_timer.stop()


func take_damage(damage_amount: int) -> void:
	if _current_state == State.DEAD or _is_splitting:
		return

	if _is_invulnerable_spawn:
		return

	var actual_damage: int = max(damage_amount - defense, 1)
	_current_hp -= actual_damage

	if _current_hp <= 0:
		call_deferred("set_state", State.DEAD)
	else:
		if _current_state not in [State.DEAD, State.RETREAT]:
			call_deferred("set_state", State.DAMAGE)


# ==============================================================================
# Private Methods - Initialization
# ==============================================================================

func _activate_spawn_invulnerability() -> void:
	_is_invulnerable_spawn = true
	_invulnerability_timer.start(spawn_invulnerability_time)


func _startup_delay() -> void:
	_can_attack = false
	_startup_timer.start(startup_attack_delay)


# ==============================================================================
# Private Methods - Timer Callbacks
# ==============================================================================

func _on_invulnerability_timeout() -> void:
	_is_invulnerable_spawn = false


func _on_startup_timeout() -> void:
	_can_attack = true


func _on_jump_timer_timeout() -> void:
	_can_jump = true


func _on_retreat_timer_timeout() -> void:
	if _current_state != State.DEAD and not _is_splitting and _player_ref:
		velocity = Vector3.ZERO
		set_state(State.CHASE)
	elif _current_state != State.DEAD and not _is_splitting:
		set_state(State.IDLE)


# ==============================================================================
# Private Methods - Movement
# ==============================================================================

func _start_movement_jump() -> void:
	if _pending_horizontal_velocity.length_squared() > 0.001:
		velocity.x = _pending_horizontal_velocity.x
		velocity.z = _pending_horizontal_velocity.z
		velocity.y = 0.5 * size

		_pending_horizontal_velocity = Vector3.ZERO
		_can_jump = false
		_jump_timer.start(jump_interval)


func _apply_movement(direction: Vector3, speed: float) -> void:
	_pending_horizontal_velocity = direction * speed

	if not is_on_floor():
		velocity.x = move_toward(velocity.x, _pending_horizontal_velocity.x, 3.0 * get_physics_process_delta_time())
		velocity.z = move_toward(velocity.z, _pending_horizontal_velocity.z, 3.0 * get_physics_process_delta_time())


func _jump_to_player(horizontal_distance: float) -> void:
	_is_jumping_to_attack = true
	_can_jump = false

	var direction_to_player: Vector3 = (_player_ref.global_position - global_position)
	direction_to_player.y = 0

	var jump_force: float = approach_jump_force if size >= 1.0 else approach_jump_force * 0.7

	var distance_needed: float = horizontal_distance - melee_range + jump_over_margin
	var target_h_distance: float = max(0.1, distance_needed)

	var time_to_land: float = 2.0 * jump_force / _gravity
	var horizontal_speed: float = target_h_distance / time_to_land

	var jump_vector: Vector3 = direction_to_player.normalized()
	velocity.x = jump_vector.x * horizontal_speed
	velocity.z = jump_vector.z * horizontal_speed
	velocity.y = jump_force


func _jump_retreat() -> void:
	_can_jump = false

	var direction_away: Vector3 = (global_position - _player_ref.global_position).normalized()
	direction_away.y = 0

	var retreat_force: float = retreat_jump_force if size >= 1.0 else retreat_jump_force * 0.7

	velocity.x = direction_away.x * retreat_force
	velocity.z = direction_away.z * retreat_force
	velocity.y = retreat_force


# ==============================================================================
# Private Methods - State Machine
# ==============================================================================

func _state_machine(delta: float) -> void:
	if _current_state in [State.WANDER, State.IDLE]:
		_process_wander_idle(delta)
		return

	if not _player_ref:
		if _has_detected_player:
			set_state(State.IDLE)
		else:
			set_state(State.WANDER)
		return

	var distance_to_player: float = global_position.distance_to(_player_ref.global_position)

	if _has_detected_player and _current_state not in [State.ATTACKING, State.RETREAT, State.APPROACH, State.DAMAGE]:
		if distance_to_player > safe_distance * 3.0:
			if _current_state != State.PURSUIT:
				set_state(State.PURSUIT)
		elif _current_state == State.PURSUIT:
			set_state(State.CHASE)

	match _current_state:
		State.CHASE:
			if distance_to_player <= small_slime_approach_range and _can_attack and _cooldown_timer <= 0:
				set_state(State.APPROACH)
			else:
				_process_chase()

		State.PURSUIT:
			if distance_to_player <= safe_distance * 2.0:
				set_state(State.CHASE)
			elif distance_to_player > max_pursuit_distance:
				_player_ref = null
				_has_detected_player = false
				set_state(State.IDLE)
			else:
				_process_pursuit()

		State.STALK:
			if distance_to_player > safe_distance + 0.5:
				set_state(State.CHASE)
			elif _cooldown_timer <= 0 and _can_attack:
				set_state(State.APPROACH)
			else:
				_process_stalk(delta, distance_to_player)

		State.APPROACH:
			var horizontal_distance: float = Vector2(
				global_position.x - _player_ref.global_position.x,
				global_position.z - _player_ref.global_position.z
			).length()

			if is_on_floor() and not _is_jumping_to_attack and _can_attack:
				_jump_to_player(horizontal_distance)
			elif _is_jumping_to_attack:
				if is_on_floor() and velocity.y <= 0.01:
					var attack_range: float = melee_range if size >= 1.0 else melee_range * 1.5
					if horizontal_distance <= attack_range + attack_fail_distance:
						set_state(State.ATTACKING)
					else:
						_is_jumping_to_attack = false
						set_state(State.CHASE)

		State.ATTACKING:
			velocity = Vector3.ZERO

		State.RETREAT:
			_process_retreat()


func _process_wander_idle(_delta: float) -> void:
	if _player_ref:
		set_state(State.CHASE)
		return

	if _current_state == State.IDLE:
		_pending_horizontal_velocity = Vector3.ZERO
		velocity.x = move_toward(velocity.x, 0, 0.1)
		velocity.z = move_toward(velocity.z, 0, 0.1)
		if _cooldown_timer <= 0:
			set_state(State.WANDER)
		return

	var direction: Vector3 = (_wander_target - global_position).normalized()
	direction.y = 0

	if global_position.distance_to(_wander_target) < 0.1:
		set_state(State.IDLE)
		return

	_apply_movement(direction, move_speed)


func _process_chase() -> void:
	var direction_to_player: Vector3 = (_player_ref.global_position - global_position).normalized()
	direction_to_player.y = 0
	_apply_movement(direction_to_player, chase_speed)


func _process_pursuit() -> void:
	var direction_to_player: Vector3 = (_player_ref.global_position - global_position).normalized()
	direction_to_player.y = 0
	_apply_movement(direction_to_player, pursuit_speed)


func _process_stalk(delta: float, current_distance: float) -> void:
	if size < 1.0:
		set_state(State.CHASE)
		return

	var to_target: Vector3 = _player_ref.global_position - global_position
	to_target.y = 0

	var radial_dir: Vector3 = to_target.normalized()
	var distance_error: float = current_distance - safe_distance
	var approach_factor: float = clamp(-distance_error * 0.3, -1.0, 1.0)

	var tangent_dir: Vector3 = Vector3(-radial_dir.z, 0, radial_dir.x)
	if not _stalk_clockwise:
		tangent_dir = -tangent_dir

	var move_direction: Vector3 = (radial_dir * approach_factor + tangent_dir).normalized()
	_apply_movement(move_direction, stalk_speed)


func _process_retreat() -> void:
	if is_on_floor() and velocity.y <= 0.01:
		_jump_retreat()


func _start_wander() -> void:
	_can_jump = true
	_jump_timer.start(jump_interval)

	var wander_origin: Vector3 = global_position
	var random_angle: float = randf_range(0, 2 * PI)
	var random_distance: float = randf_range(0.5, 1.5)

	_wander_target = wander_origin + Vector3(
		cos(random_angle) * random_distance,
		0,
		sin(random_angle) * random_distance
	)


# ==============================================================================
# Private Methods - Attack & Damage
# ==============================================================================

func _execute_attack() -> void:
	_cooldown_timer = attack_cooldown
	velocity = Vector3.ZERO
	_attack_was_successful = false

	if _animated_sprite.sprite_frames.has_animation("attack"):
		_animated_sprite.play("attack")
	else:
		_animated_sprite.play("idle")

	var attack_collision: CollisionShape3D = _attack_area.get_node_or_null("CollisionShape3D")
	if attack_collision:
		attack_collision.set_deferred("disabled", false)

	await get_tree().create_timer(0.15).timeout

	if attack_collision:
		attack_collision.set_deferred("disabled", true)

	if _current_state != State.DEAD and not _is_splitting:
		if _attack_was_successful:
			set_state(State.RETREAT)
		else:
			set_state(State.CHASE)


func _start_retreat() -> void:
	if not _player_ref:
		set_state(State.IDLE)
		return

	_retreat_timer.start(retreat_duration)


func _start_damage() -> void:
	if _jump_timer:
		_jump_timer.stop()

	velocity = Vector3.ZERO

	var damage_color_applied: bool = false
	if _animated_sprite.sprite_frames.has_animation("damage"):
		_animated_sprite.play("damage")
	else:
		_animated_sprite.modulate = Color(1, 0.5, 0.5, 1)
		damage_color_applied = true

	await get_tree().create_timer(0.5).timeout

	if _is_splitting or _current_state == State.DEAD:
		return

	if damage_color_applied:
		_animated_sprite.modulate = Color.WHITE

	if _current_state != State.DEAD:
		_cooldown_timer = 0.3
		if _player_ref:
			set_state(State.CHASE)
		else:
			set_state(State.IDLE)
		_can_jump = true


func _start_dead() -> void:
	velocity = Vector3.ZERO

	if size < 1.0:
		_spawn_random_loot()

	if _animated_sprite.sprite_frames.has_animation("death"):
		_animated_sprite.play("death")
		await _animated_sprite.animation_finished

	queue_free()


func _start_death_animation_and_split() -> void:
	velocity = Vector3.ZERO

	if _animated_sprite.sprite_frames.has_animation("death"):
		_animated_sprite.play("death")
		await _animated_sprite.animation_finished

	_split_into_smaller_slimes()


# ==============================================================================
# Private Methods - Loot
# ==============================================================================

func _spawn_random_loot() -> void:
	if randf() > loot_drop_chance:
		return

	if possible_loot_scenes.is_empty():
		return

	var loot_scene_to_spawn: PackedScene = possible_loot_scenes.pick_random()
	if not loot_scene_to_spawn:
		return

	var item: Node = loot_scene_to_spawn.instantiate()
	var parent_node: Node = get_parent()
	if not is_instance_valid(parent_node):
		parent_node = get_tree().current_scene

	parent_node.add_child(item)

	var spawn_pos: Vector3 = global_position

	var offset_x: float = randf_range(-0.1, 0.1) * size
	var offset_z: float = randf_range(-0.1, 0.1) * size
	var spawn_offset_y: float = 0.15

	var final_position: Vector3 = spawn_pos + Vector3(offset_x, spawn_offset_y, offset_z)

	item.global_position = final_position
	item.scale = loot_scale


# ==============================================================================
# Private Methods - Splitting
# ==============================================================================

func _split_into_smaller_slimes() -> void:
	if _is_splitting:
		return

	_is_splitting = true

	if _jump_timer:
		_jump_timer.stop()
	if _retreat_timer:
		_retreat_timer.stop()

	velocity = Vector3.ZERO

	if not small_slime_scene:
		queue_free()
		return

	var spawn_position: Vector3 = global_position
	var parent_node: Node = get_parent()

	for i in range(3):
		var new_slime: Slime = small_slime_scene.instantiate()

		new_slime.size = 0.5
		new_slime.max_hp = 10
		new_slime._current_hp = 10

		var direction_away_from_player: Vector3
		if _player_ref and is_instance_valid(_player_ref):
			direction_away_from_player = (spawn_position - _player_ref.global_position).normalized()
		else:
			var random_angle: float = randf() * 2 * PI
			direction_away_from_player = Vector3(cos(random_angle), 0, sin(random_angle)).normalized()

		var base_angle: float = atan2(direction_away_from_player.z, direction_away_from_player.x)
		var angle_variation: float = randf_range(-0.5, 0.5)
		var final_angle: float = base_angle + angle_variation

		var final_direction: Vector3 = Vector3(cos(final_angle), 0, sin(final_angle)).normalized()

		var offset_distance: float = split_rebound_distance
		var offset: Vector3 = final_direction * offset_distance

		if _player_ref and is_instance_valid(_player_ref):
			new_slime._player_ref = _player_ref
			new_slime._has_detected_player = true

		var impulse_strength: float = split_rebound_force
		new_slime.velocity = final_direction * impulse_strength
		new_slime.velocity.y = impulse_strength * 0.6

		parent_node.call_deferred("add_child", new_slime)

		var final_position: Vector3 = spawn_position + offset
		final_position.y = spawn_position.y + 0.1

		await get_tree().process_frame
		new_slime.global_position = final_position

	queue_free()


# ==============================================================================
# Private Methods - Utilities
# ==============================================================================

func _update_visual_scale() -> void:
	scale = Vector3(size, size, size)
	move_speed = 0.3 * size
	chase_speed = 1.0 * size
	pursuit_speed = 0.6 * size
	stalk_speed = 0.1 * size


func _setup_detection_area() -> void:
	if not _detection_area:
		return

	var collision_shape_detection: CollisionShape3D = _detection_area.get_node_or_null("CollisionShape3D")
	if collision_shape_detection:
		if not collision_shape_detection.shape is SphereShape3D:
			var sphere_shape: SphereShape3D = SphereShape3D.new()
			sphere_shape.radius = safe_distance * 3
			collision_shape_detection.shape = sphere_shape


func _look_at_player() -> void:
	if not _player_ref:
		return

	var direction_to_player: Vector3 = _player_ref.global_position - global_position
	direction_to_player.y = 0

	if direction_to_player.length() > 0.01:
		var facing_right: bool = direction_to_player.x > 0

		if facing_right != _is_facing_right:
			_is_facing_right = facing_right
			_animated_sprite.flip_h = not _is_facing_right
			if _attack_area:
				_attack_area.scale.x = 1.0 if _is_facing_right else -1.0


func _update_animations() -> void:
	if _current_state in [State.DEAD, State.DAMAGE, State.ATTACKING]:
		return

	var target_animation: String = "idle"

	if _pending_horizontal_velocity.length_squared() > 0.001 or velocity.length_squared() > 0.001:
		target_animation = "walk"

	if _animated_sprite.sprite_frames.has_animation(target_animation):
		_animated_sprite.play(target_animation)


# ==============================================================================
# Private Methods - Signal Handlers
# ==============================================================================

func _on_detection_area_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_ref = body
		_has_detected_player = true
		call_deferred("set_state", State.CHASE)


func _on_detection_area_body_exited(body: Node) -> void:
	if body == _player_ref:
		if _has_detected_player and _current_state in [State.CHASE, State.STALK, State.APPROACH]:
			call_deferred("set_state", State.PURSUIT)


func _on_attack_hit_player(body: Node) -> void:
	if _current_state == State.ATTACKING and body.is_in_group("player") and _can_attack:
		_attack_was_successful = true
		if body.has_method("take_damage_hearts_with_knockback"):
			var knockback_force: float = 0.05 if size < 1.0 else 0.1
			var direction: Vector3 = (body.global_position - global_position).normalized()
			var damage: float = small_slime_attack_damage if size < 1.0 else attack_damage
			body.take_damage_hearts_with_knockback(damage, direction, knockback_force)
