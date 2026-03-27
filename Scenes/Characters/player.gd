## Player character controller with state machine (FSM).
##
## Handles movement, combat, rolling, health, and level transitions.
## Uses a finite state machine for state management.
extends CharacterBody3D


# ==============================================================================
# Signals
# ==============================================================================
# (None currently)


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
# Export variables - Movement
# ==============================================================================

@export_group("Movement")
@export var move_speed: float = 1.0
@export var jump_speed: float = 2.0
@export var gravity_multiplier: float = 1.0


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
var _attack_combo_step: int = 0
var _input_buffer: String = ""
var _enemies_hit: Array = []
var _is_invulnerable: bool = false
var _ui_ref: CanvasLayer = null

var _damage_knockback_timer: Timer = Timer.new()
var _damage_visual_timer: Timer = Timer.new()
var _roll_cooldown_timer: Timer = Timer.new()
var _notification_cooldown: Dictionary = {}
var _notification_cooldown_time: float = 1.0


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
	
	call_deferred("_find_ui")


func _physics_process(delta: float) -> void:
	match current_state:
		State.NORMAL:
			_handle_move()
			_handle_jump()
			_handle_actions_input()
		State.ATTACKING:
			if _damage_knockback_timer.is_stopped():
				_handle_move(attack_movement_multiplier)
			_handle_buffer_input()
		State.ROLLING:
			_apply_roll_physics()
		State.DAMAGE:
			pass
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
	else:
		if current_state == State.DAMAGE and _damage_knockback_timer.is_stopped():
			velocity.y = 0
	
	move_and_slide()
	_update_animations()


# ==============================================================================
# Public methods - Input handling
# ==============================================================================

func add_key() -> void:
	key_count += 1
	show_notification("Llave conseguida (%d)" % key_count)
	
	if _ui_ref and _ui_ref.has_method("update_keys_display"):
		_ui_ref.update_keys_display()


func use_key() -> bool:
	if key_count > 0:
		key_count -= 1
		
		if _ui_ref and _ui_ref.has_method("update_keys_display"):
			_ui_ref.update_keys_display()
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
	
	if _ui_ref and _ui_ref.has_method("update_hearts_display"):
		_ui_ref.update_hearts_display()
	
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
		
		if _ui_ref and _ui_ref.has_method("update_hearts_display"):
			_ui_ref.update_hearts_display()


func increase_max_health(amount: float) -> void:
	max_health += amount
	current_health = max_health
	
	show_notification("Obtuviste una vida extra!")
	
	if _ui_ref and _ui_ref.has_method("update_max_hearts_display"):
		_ui_ref.update_max_hearts_display()


func die() -> void:
	if is_instance_valid(GameOverHandler):
		GameOverHandler.handle_player_death(self)
	else:
		get_tree().call_deferred("reload_current_scene")


# ==============================================================================
# Public methods - UI notifications
# ==============================================================================

func refresh_ui_state() -> void:
	if _ui_ref and _ui_ref.has_method("update_max_hearts_display"):
		_ui_ref.update_max_hearts_display()
	if _ui_ref and _ui_ref.has_method("update_hearts_display"):
		_ui_ref.update_hearts_display()
	if _ui_ref and _ui_ref.has_method("update_keys_display"):
		_ui_ref.update_keys_display()


func show_notification(message: String) -> void:
	var current_time: int = Time.get_ticks_msec()
	
	if _notification_cooldown.has(message):
		var last_shown_time: int = _notification_cooldown[message]
		if current_time - last_shown_time < int(_notification_cooldown_time * 1000):
			return
	
	_notification_cooldown[message] = current_time
	
	if _ui_ref and _ui_ref.has_method("show_notification"):
		_ui_ref.show_notification(message)


func show_immediate_notification(message: String) -> void:
	if _ui_ref and _ui_ref.has_method("show_immediate_notification"):
		_ui_ref.show_immediate_notification(message)


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
		velocity.x = direction.x * final_speed
		velocity.z = direction.z * final_speed
		_flip_sprite(velocity.x)
	else:
		velocity.x = move_toward(velocity.x, 0.0, final_speed)
		velocity.z = move_toward(velocity.z, 0.0, final_speed)


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_speed


func _apply_roll_physics() -> void:
	if current_state == State.ROLLING:
		var current_vel_xz: float = Vector3(velocity.x, 0, velocity.z).length()
		
		if current_vel_xz < 0.1:
			var facing_dir: float = 1.0 if _is_facing_right else -1.0
			velocity.x = facing_dir * roll_speed
			velocity.z = 0.0
		else:
			var roll_dir_xz: Vector3 = Vector3(velocity.x, 0, velocity.z).normalized()
			velocity.x = roll_dir_xz.x * roll_speed
			velocity.z = roll_dir_xz.z * roll_speed


func _flip_sprite(x_velocity: float) -> void:
	if abs(x_velocity) < 0.1:
		return
	
	var moving_right: bool = x_velocity > 0
	if moving_right != _is_facing_right:
		_is_facing_right = moving_right
		_animated_sprite.flip_h = not _is_facing_right
		_attack_area.scale.x = 1.0 if _is_facing_right else -1.0


# ==============================================================================
# Private methods - State management
# ==============================================================================

func set_state(new_state: State) -> void:
	# Exit previous state
	if current_state == State.ATTACKING:
		_attack_collision.set_deferred("disabled", true)
		_animated_sprite.speed_scale = 1.0
	
	current_state = new_state
	
	# Enter new state
	match new_state:
		State.NORMAL:
			if _damage_knockback_timer.is_stopped():
				if _input_buffer == "attack":
					_input_buffer = ""
					set_state(State.ATTACKING)
				elif _input_buffer == "roll" and _roll_cooldown_timer.is_stopped():
					_input_buffer = ""
					set_state(State.ROLLING)
		State.ATTACKING:
			_start_attack()
		State.ROLLING:
			_start_roll()
		State.DAMAGE:
			_start_damage()


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
	
	if _animated_sprite.sprite_frames.has_animation("roll"):
		_animated_sprite.play("roll")
	
	if not _animated_sprite.sprite_frames.has_animation("roll"):
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
		_animated_sprite.speed_scale = 2.0
		if velocity.y > 0:
			_animated_sprite.play("jump")
		else:
			_animated_sprite.play("fall")
		return
	
	_animated_sprite.speed_scale = 1.0
	if velocity.x != 0 or velocity.z != 0:
		_animated_sprite.play("run")
	else:
		_animated_sprite.play("idle")


func _on_animation_finished() -> void:
	if _animated_sprite.animation == "attack":
		set_state(State.NORMAL)
	elif _animated_sprite.animation == "roll":
		_is_invulnerable = false
		_roll_cooldown_timer.start(roll_cooldown)
		set_state(State.NORMAL)


# ==============================================================================
# Private methods - UI
# ==============================================================================

func _find_ui() -> void:
	_ui_ref = get_tree().get_first_node_in_group("ui")
	
	if not _ui_ref:
		for child in get_tree().root.get_children():
			if (child.name == "player_ui" or child.name == "Player_UI"
					or child is CanvasLayer):
				_ui_ref = child
				break
	
	if _ui_ref:
		if _ui_ref.has_method("update_max_hearts_display"):
			_ui_ref.update_max_hearts_display()
	else:
		push_warning("Player: No se encontró UI.")


# ==============================================================================
# Private methods - Level transitions
# ==============================================================================

func _on_area_entered_player(area: Area3D) -> void:
	"""Detecta cuando el jugador entra en un área de cambio de nivel."""
	if area.is_in_group("level_trigger"):
		if area.has_method("trigger_level_change"):
			area.trigger_level_change(self)
