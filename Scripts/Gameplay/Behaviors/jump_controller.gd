extends RefCounted
class_name JumpController

var jump_profile: Vector2 = Vector2.ZERO
var last_time_on_floor: float = 0.0
var jump_buffer_timer: float = 0.0
var jump_consumed: bool = false
var is_jumping: bool = false
var airborne_time: float = 0.0


func configure(config: PlayerConfig, base_gravity: float, grid_step: float) -> void:
	jump_profile = Vector2(config.jump_speed, config.gravity_multiplier)
	if config.use_jump_model:
		var jump_height_world: float = max(config.jump_height * grid_step, 0.2)
		jump_profile = _build_jump_profile(jump_height_world, config.time_to_jump_apex, base_gravity)


func update_timers(delta: float, on_floor: bool, config: PlayerConfig) -> void:
	if on_floor:
		last_time_on_floor = config.jump_coyote_time
		jump_consumed = false
		is_jumping = false
		airborne_time = 0.0
	else:
		last_time_on_floor = max(last_time_on_floor - delta, 0.0)
		airborne_time += delta

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = config.jump_buffer_time
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)


func can_start_jump() -> bool:
	if jump_consumed:
		return false
	if jump_buffer_timer <= 0.0:
		return false
	return last_time_on_floor > 0.0


func start_jump(player: CharacterBody3D) -> void:
	player.velocity.y = jump_profile.x
	jump_buffer_timer = 0.0
	last_time_on_floor = 0.0
	jump_consumed = true
	is_jumping = true


func consume_jump_by_external_boost() -> void:
	jump_buffer_timer = 0.0
	last_time_on_floor = 0.0
	jump_consumed = true
	is_jumping = true


func get_air_gravity_multiplier(velocity_y: float, jump_pressed: bool, config: PlayerConfig) -> float:
	if velocity_y < 0.0:
		return config.fall_gravity_multiplier
	if velocity_y > 0.0 and not jump_pressed:
		return config.jump_release_gravity_multiplier
	return 1.0


func _build_jump_profile(height: float, apex_time: float, base_gravity: float) -> Vector2:
	var safe_height: float = max(height, 0.05)
	var safe_apex_time: float = max(apex_time, 0.05)
	var effective_gravity: float = (2.0 * safe_height) / (safe_apex_time * safe_apex_time)
	var safe_base_gravity: float = max(base_gravity, 0.001)
	var computed_jump_speed: float = (2.0 * safe_height) / safe_apex_time
	var computed_gravity_multiplier: float = effective_gravity / safe_base_gravity
	return Vector2(computed_jump_speed, computed_gravity_multiplier)
