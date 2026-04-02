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

const ANIM_MOVE_SIDE: StringName = &"move_side"
const ANIM_MOVE_UP: StringName = &"move_up"
const ANIM_MOVE_DOWN: StringName = &"move_down"
const ANIM_ROLL_SIDE: StringName = &"roll_side"
const ANIM_ROLL_UP: StringName = &"roll_up"
const ANIM_ROLL_DOWN: StringName = &"roll_down"
const ANIM_JUMP_SIDE: StringName = &"jump_side"
const ANIM_JUMP_UP: StringName = &"jump_up"
const ANIM_JUMP_DOWN: StringName = &"jump_down"
const ANIM_ATTACK: StringName = &"attack_side"
const WEAPON_NONE: StringName = &"none"
const WEAPON_SWORD: StringName = &"sword"
const EDGE_HOP_RAYCAST_NAME: StringName = &"EdgeHopRayCast3D_Player"
const EdgeHopControllerScript = preload("res://Scripts/Gameplay/Behaviors/edge_hop_controller.gd")
const JumpControllerScript = preload("res://Scripts/Gameplay/Behaviors/jump_controller.gd")
const GroundLocomotionControllerScript = preload("res://Scripts/Gameplay/Behaviors/ground_locomotion_controller.gd")
const DirectionAnimationControllerScript = preload("res://Scripts/Gameplay/Behaviors/direction_animation_controller.gd")
const CombatControllerScript = preload("res://Scripts/Gameplay/Behaviors/combat_controller.gd")
const NotificationControllerScript = preload("res://Scripts/Gameplay/Behaviors/notification_controller.gd")


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

@export_group("Combat - Equipment")
@export var weapon_toggle_action: StringName = &"toggle_weapon"
@export var sword_starts_unlocked: bool = true
@export var sword_starts_equipped: bool = true


# ==============================================================================
# Runtime variables
# ==============================================================================

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_health: float
var key_count: int = 0
var _owned_weapons: Dictionary = {}
var _equipped_weapon: StringName = WEAPON_NONE

# Combat/Health config (loaded from player_config)
var max_health: float


# ==============================================================================
# FSM and state variables
# ==============================================================================

var current_state: State = State.NORMAL
var _is_facing_right: bool = true
var _last_move_animation: StringName = ANIM_MOVE_SIDE
var _last_move_input: Vector2 = Vector2.RIGHT
var _input_buffer: String = ""

var _damage_knockback_timer: Timer = Timer.new()
var _damage_visual_timer: Timer = Timer.new()
var _roll_cooldown_timer: Timer = Timer.new()
var _notification_cooldown_time: float = 1.0
var _was_on_floor_last_frame: bool = false
var _edge_hop_controller = EdgeHopControllerScript.new()
var _jump_controller = JumpControllerScript.new()
var _ground_locomotion_controller = GroundLocomotionControllerScript.new()
var _direction_animation_controller = DirectionAnimationControllerScript.new()
var _combat_controller = CombatControllerScript.new()
var _notification_controller = NotificationControllerScript.new()


# ==============================================================================
# Onready variables
# ==============================================================================

@onready var _animated_sprite: AnimatedSprite3D = $Sprite3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _attack_collision: CollisionShape3D = $AttackArea/CollisionShape3D
@onready var _detection_area: Area3D = $DetectionArea
@onready var _edge_hop_raycast: RayCast3D = get_node_or_null(NodePath(String(EDGE_HOP_RAYCAST_NAME)))


# ==============================================================================
# Built-in methods
# ==============================================================================

func _ready() -> void:
	if not player_config:
		push_error("PlayerConfig no asignado en player.tscn")
		return
	
	_apply_config()
	_notification_controller.cooldown_seconds = _notification_cooldown_time
	_setup_edge_hop_raycast()
	_setup_terrain_motion()
	_was_on_floor_last_frame = is_on_floor()
	current_health = max_health
	_initialize_weapon_state()
	
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
		_combat_controller.clear_invulnerability(_animated_sprite)
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
	_jump_controller.update_timers(delta, is_on_floor(), player_config)
	_edge_hop_controller.tick(delta)
	_update_current_state(delta)
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * _jump_controller.jump_profile.y * _jump_controller.get_air_gravity_multiplier(
			velocity.y,
			Input.is_action_pressed("jump"),
			player_config
		) * delta
	else:
		if current_state == State.DAMAGE and _damage_knockback_timer.is_stopped():
			velocity.y = 0
		else:
			_ground_locomotion_controller.apply_terrain_adhesion(self)

	if velocity.y <= 0.0 and current_state != State.ROLLING and not _jump_controller.is_jumping:
		apply_floor_snap()
	
	move_and_slide()
	if _ground_locomotion_controller.resolve_slope_edge_block(self):
		move_and_slide()
	_try_edge_hop()
	_was_on_floor_last_frame = is_on_floor()
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
	if current_state == State.ROLLING or _combat_controller.is_invulnerable:
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
	if not _notification_controller.can_emit(message):
		return

	notification_requested.emit(message)


func show_immediate_notification(message: String) -> void:
	immediate_notification_requested.emit(message)


# ==============================================================================
# Private methods - Input handling
# ==============================================================================

func _handle_actions_input() -> void:
	if Input.is_action_just_pressed(String(weapon_toggle_action)):
		toggle_sword_equipped()
		return

	if Input.is_action_just_pressed("attack") and _can_attack_with_current_weapon():
		set_state(State.ATTACKING)
	elif Input.is_action_just_pressed("roll") and _roll_cooldown_timer.is_stopped():
		set_state(State.ROLLING)


func _handle_buffer_input() -> void:
	if Input.is_action_just_pressed("attack") and _can_attack_with_current_weapon():
		_input_buffer = "attack"
	elif Input.is_action_just_pressed("roll"):
		_input_buffer = "roll"
		if _roll_cooldown_timer.is_stopped():
			set_state(State.ROLLING)


func toggle_sword_equipped() -> void:
	if current_state == State.ATTACKING:
		return

	if _equipped_weapon == WEAPON_SWORD:
		set_equipped_weapon(WEAPON_NONE)
		show_notification("Espada guardada")
		return

	if not _owned_weapons.get(WEAPON_SWORD, false):
		show_notification("No tienes espada")
		return

	set_equipped_weapon(WEAPON_SWORD)
	show_notification("Espada equipada")


func register_weapon(weapon_id: StringName) -> void:
	_owned_weapons[weapon_id] = true


func set_equipped_weapon(weapon_id: StringName) -> bool:
	if weapon_id != WEAPON_NONE and not _owned_weapons.get(weapon_id, false):
		return false

	_equipped_weapon = weapon_id
	if _equipped_weapon == WEAPON_NONE:
		_attack_collision.set_deferred("disabled", true)

	return true


func get_equipped_weapon_id() -> StringName:
	return _equipped_weapon


func get_owned_weapons_for_save() -> Array[StringName]:
	var result: Array[StringName] = []
	for weapon_id in _owned_weapons.keys():
		if _owned_weapons[weapon_id]:
			result.append(weapon_id)
	return result


func load_weapon_state_from_save(owned_weapons: Array, equipped_weapon: StringName) -> void:
	_owned_weapons.clear()
	for weapon_id in owned_weapons:
		_owned_weapons[StringName(weapon_id)] = true

	if equipped_weapon != WEAPON_NONE and _owned_weapons.get(equipped_weapon, false):
		_equipped_weapon = equipped_weapon
	else:
		_equipped_weapon = WEAPON_NONE

	if _equipped_weapon == WEAPON_NONE:
		_attack_collision.set_deferred("disabled", true)


func _can_attack_with_current_weapon() -> bool:
	return _equipped_weapon == WEAPON_SWORD


func _initialize_weapon_state() -> void:
	_owned_weapons.clear()

	if sword_starts_unlocked:
		register_weapon(WEAPON_SWORD)

	if sword_starts_equipped and sword_starts_unlocked:
		_equipped_weapon = WEAPON_SWORD
	else:
		_equipped_weapon = WEAPON_NONE

	if _equipped_weapon == WEAPON_NONE:
		_attack_collision.disabled = true
	else:
		_attack_collision.disabled = false


# ==============================================================================
# Private methods - Movement
# ==============================================================================

func _handle_move(speed_mult: float = 1.0) -> void:
	var input_dir: Vector2 = Input.get_vector(
			"move_left",
			"move_right",
			"move_up",
			"move_down"
	)
	if _ground_locomotion_controller.apply_move(self, input_dir, _get_move_speed() * speed_mult, _damage_knockback_timer, transform.basis):
		var facing_update: Dictionary = _direction_animation_controller.update_facing_from_input(
			_animated_sprite,
			_attack_area,
			input_dir,
			_last_move_input,
			_is_facing_right,
			ANIM_MOVE_SIDE,
			ANIM_MOVE_UP,
			ANIM_MOVE_DOWN
		)
		_last_move_input = facing_update["last_move_input"]
		_is_facing_right = facing_update["is_facing_right"]
		_last_move_animation = facing_update["last_move_animation"]


func _handle_jump() -> void:
	if _can_start_jump():
		_start_jump()


func _apply_roll_physics() -> void:
	_ground_locomotion_controller.apply_roll_physics(
		self,
		current_state == State.ROLLING,
		player_config.roll_speed,
		_direction_animation_controller.get_last_facing_direction_3d(_last_move_input, _is_facing_right)
	)


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
		_handle_move(player_config.attack_movement_multiplier)
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
	_combat_controller.start_attack(_animated_sprite, ANIM_ATTACK)
	
	get_tree().create_timer(player_config.attack_hit_delay).timeout.connect(_on_hitbox_activate)


func _on_hitbox_activate() -> void:
	if current_state != State.ATTACKING:
		return
	
	_combat_controller.activate_attack_hitbox(self, _attack_collision, State.ATTACKING)


func _on_attack_hit(body: Node3D) -> void:
	_combat_controller.handle_attack_hit(self, body, _attack_collision, player_config.attack_damage)


func _start_roll() -> void:
	_input_buffer = ""
	_animated_sprite.speed_scale = 2.0

	var roll_animation: StringName = _direction_animation_controller.get_roll_animation_name(
		Vector3(velocity.x, 0.0, velocity.z),
		_last_move_animation,
		ANIM_ROLL_SIDE,
		ANIM_ROLL_UP,
		ANIM_ROLL_DOWN
	)
	if not _direction_animation_controller.play_animation_with_fallback(_animated_sprite, roll_animation, &"roll"):
		var roll_timer: SceneTreeTimer = get_tree().create_timer(player_config.roll_duration)
		roll_timer.timeout.connect(func() -> void:
			_combat_controller.clear_invulnerability(_animated_sprite)
			_roll_cooldown_timer.start(player_config.roll_cooldown)
			set_state(State.NORMAL)
		)


func _start_damage() -> void:
	_combat_controller.start_damage(_animated_sprite, _damage_visual_timer, player_config.invulnerability_time, player_config.damage_visual_time)


# ==============================================================================
# Private methods - Animation
# ==============================================================================

func _update_animations() -> void:
	if current_state in [State.ATTACKING, State.ROLLING, State.DAMAGE]:
		return
	
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	var has_movement_input: bool = input_dir != Vector2.ZERO
	
	if not is_on_floor():
		# No fall animation: airborne state resolves to jump or regular movement/idle.
		if _jump_controller.is_jumping:
			_animated_sprite.speed_scale = 2.0
			var jump_animation: StringName = _direction_animation_controller.get_jump_animation_name(
				_last_move_animation,
				ANIM_MOVE_SIDE,
				ANIM_MOVE_UP,
				ANIM_MOVE_DOWN,
				ANIM_JUMP_SIDE,
				ANIM_JUMP_UP,
				ANIM_JUMP_DOWN
			)
			_direction_animation_controller.play_animation_with_fallback(_animated_sprite, jump_animation, ANIM_JUMP_SIDE)
			return
		
		# If actively moving with input but NOT jumping, show movement anim (climbing slopes)
		if has_movement_input and (velocity.x != 0 or velocity.z != 0):
			_animated_sprite.speed_scale = 1.0
			_direction_animation_controller.play_animation_with_fallback(_animated_sprite, _last_move_animation, ANIM_MOVE_SIDE)
			return
		
		# Grace period without movement
		if velocity.x != 0 or velocity.z != 0:
			_animated_sprite.speed_scale = 1.0
			var ground_move_animation: StringName = _direction_animation_controller.get_move_animation_name(Vector3(velocity.x, 0.0, velocity.z), ANIM_MOVE_SIDE, ANIM_MOVE_UP, ANIM_MOVE_DOWN)
			_direction_animation_controller.play_animation_with_fallback(_animated_sprite, ground_move_animation, ANIM_MOVE_SIDE)
		else:
			_animated_sprite.speed_scale = 1.0
			_direction_animation_controller.play_idle_from_last_direction(_animated_sprite, _last_move_animation, ANIM_MOVE_SIDE)
		return
	
	_animated_sprite.speed_scale = 1.0
	if has_movement_input or velocity.x != 0 or velocity.z != 0:
		_direction_animation_controller.play_animation_with_fallback(_animated_sprite, _last_move_animation, ANIM_MOVE_SIDE)
	else:
		_direction_animation_controller.play_idle_from_last_direction(_animated_sprite, _last_move_animation, ANIM_MOVE_SIDE)


func _on_animation_finished() -> void:
	if _animated_sprite.animation == ANIM_ATTACK:
		set_state(State.NORMAL)
	elif String(_animated_sprite.animation).begins_with("roll"):
		_combat_controller.clear_invulnerability(_animated_sprite)
		_roll_cooldown_timer.start(player_config.roll_cooldown)
		set_state(State.NORMAL)


# ==============================================================================
# Private methods - Configuration
# ==============================================================================

func _apply_config() -> void:
	if not player_config:
		return
	_jump_controller.configure(player_config, gravity, _get_world_grid_step())

	max_health = player_config.max_health


func _get_move_speed() -> float:
	return player_config.move_speed


func _get_world_grid_step() -> float:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return 1.0

	var grid_map: GridMap = _find_first_grid_map(scene_root)
	if grid_map == null:
		return 1.0

	var biggest_cell_axis: float = maxf(grid_map.cell_size.x, maxf(grid_map.cell_size.y, grid_map.cell_size.z))
	return maxf(biggest_cell_axis * grid_map.cell_scale, 0.001)


func _find_first_grid_map(node: Node) -> GridMap:
	if node is GridMap:
		return node as GridMap

	for child: Node in node.get_children():
		var found: GridMap = _find_first_grid_map(child)
		if found != null:
			return found

	return null








func _can_start_jump() -> bool:
	return _jump_controller.can_start_jump()


func _start_jump() -> void:
	_jump_controller.start_jump(self)


func _setup_terrain_motion() -> void:
	_ground_locomotion_controller.setup_terrain_motion(self, player_config)


func _setup_edge_hop_raycast() -> void:
	_edge_hop_raycast = _edge_hop_controller.setup_raycast(
		self,
		_edge_hop_raycast,
		EDGE_HOP_RAYCAST_NAME,
		player_config.edge_hop_probe_height,
		player_config.edge_hop_probe_depth
	)


func _try_edge_hop() -> void:
	if _edge_hop_controller.try_edge_hop(
		self,
		_edge_hop_raycast,
		player_config,
		_was_on_floor_last_frame,
		current_state,
		State.NORMAL,
		_jump_controller.is_jumping,
		_get_move_speed(),
		_damage_knockback_timer,
		_ground_locomotion_controller.get_horizontal_move_direction_3d(
			Input.get_vector("move_left", "move_right", "move_up", "move_down"),
			velocity,
			_direction_animation_controller.get_last_facing_direction_3d(_last_move_input, _is_facing_right)
		)
	):
		_jump_controller.consume_jump_by_external_boost()




# ==============================================================================
# Private methods - Level transitions
# ==============================================================================

func _on_area_entered_player(area: Area3D) -> void:
	"""Detecta cuando el jugador entra en un área de cambio de nivel."""
	if area.is_in_group("level_trigger"):
		if area.has_method("trigger_level_change"):
			area.trigger_level_change(self)
