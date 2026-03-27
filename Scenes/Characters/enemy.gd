## Melee enemy with patrol, chase, and attack behavior.
## Detects player and pursues to attack. Takes damage and can be stunned.
extends CharacterBody3D

# ==============================================================================
# Enums
# ==============================================================================

enum State { IDLE, WANDER, CHASE, ATTACKING, ATTACK_COOLDOWN, DAMAGE, DEAD }

# ==============================================================================
# Exports - Enemy Stats
# ==============================================================================

@export_group("Enemy Stats")
@export var max_hp: int = 30
@export var defense: int = 0
@export var move_speed: float = 0.3
@export var chase_speed: float = 1.0
@export var gravity_multiplier: float = 1.0

# ==============================================================================
# Exports - Attack
# ==============================================================================

@export_group("Attack")
@export var melee_range: float = 0.7
@export var attack_damage: float = 10
@export var attack_cooldown: float = 0.2
@export var attack_knockback_force: float = 0.2
@export var post_attack_wait_time: float = 1.0

# ==============================================================================
# Exports - Patrol
# ==============================================================================

@export var wander_radius: float = 2.5
@export var lost_player_distance: float = 8.0

# ==============================================================================
# Exports - Damage
# ==============================================================================

@export_group("Damage")
@export var damage_duration: float = 0.3
@export var post_damage_recovery_pause: float = 0.5

# ==============================================================================
# Member Variables
# ==============================================================================

var _current_state: State = State.IDLE
var _current_hp: int
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _player_ref: CharacterBody3D = null
var _cooldown_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _hit_registered: bool = false

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var _attack_area: Area3D = $AttackArea
@onready var _detection_area: Area3D = $DetectionArea

var _damage_recovery_timer: Timer


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	_current_hp = max_hp
	_detection_area.body_entered.connect(_on_detection_enter)
	_detection_area.body_exited.connect(_on_detection_exit)
	_attack_area.body_entered.connect(_on_attack_hit_player)

	var col: CollisionShape3D = _attack_area.get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)

	_damage_recovery_timer = Timer.new()
	add_child(_damage_recovery_timer)
	_damage_recovery_timer.one_shot = true
	_damage_recovery_timer.timeout.connect(_on_damage_recovery_timeout)

	set_state(State.WANDER)


func _physics_process(delta: float) -> void:
	if _current_state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta
	else:
		if _current_state not in [State.ATTACKING, State.ATTACK_COOLDOWN, State.DAMAGE]:
			velocity.y = 0

	if _cooldown_timer > 0:
		_cooldown_timer -= delta

	_state_machine(delta)
	move_and_slide()
	_update_animations()


# ==============================================================================
# Public Methods
# ==============================================================================

func set_state(s: State) -> void:
	_current_state = s

	match s:
		State.IDLE:
			velocity = Vector3.ZERO

		State.WANDER:
			_wander_target = Vector3.ZERO

		State.ATTACKING:
			_execute_attack()

		State.ATTACK_COOLDOWN:
			_start_post_attack_wait()

		State.DAMAGE:
			_damage_recovery_timer.start(damage_duration)

			velocity.x = move_toward(velocity.x, 0, 10.0)
			velocity.z = move_toward(velocity.z, 0, 10.0)

			if _animated_sprite.sprite_frames.has_animation("damage"):
				_animated_sprite.play("damage")

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
	if _current_state == State.WANDER:
		_process_wander()
		return

	if _current_state == State.CHASE:
		_process_chase()
		return

	if _current_state in [State.ATTACKING, State.ATTACK_COOLDOWN]:
		return

	if _current_state == State.DAMAGE:
		velocity.x = move_toward(velocity.x, 0, 3 * delta)
		velocity.z = move_toward(velocity.z, 0, 3 * delta)
		return


func _process_wander() -> void:
	if _player_ref:
		set_state(State.CHASE)
		return

	if _wander_target == Vector3.ZERO or global_position.distance_to(_wander_target) < 0.3:
		var angle: float = randf_range(0, TAU)
		var dist: float = randf_range(1.0, wander_radius)
		_wander_target = global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

	var dir: Vector3 = (_wander_target - global_position).normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed


func _process_chase() -> void:
	if not _player_ref:
		set_state(State.WANDER)
		return

	var dist: float = global_position.distance_to(_player_ref.global_position)

	if dist > lost_player_distance:
		_player_ref = null
		set_state(State.WANDER)
		return

	if _current_state not in [State.DAMAGE, State.ATTACK_COOLDOWN] and dist <= melee_range and _cooldown_timer <= 0:
		set_state(State.ATTACKING)
		return

	var dir: Vector3 = (_player_ref.global_position - global_position).normalized()
	dir.y = 0

	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	_look_at_player()


# ==============================================================================
# Private Methods - Attack
# ==============================================================================

func _execute_attack() -> void:
	_hit_registered = false
	velocity = Vector3.ZERO

	if _animated_sprite.sprite_frames.has_animation("attack"):
		_animated_sprite.play("attack")
	else:
		_animated_sprite.play("idle")

	_enable_attack_area()
	await get_tree().create_timer(0.15).timeout
	_disable_attack_area()

	if not _hit_registered:
		_cooldown_timer = attack_cooldown
		set_state(State.CHASE)


func _start_post_attack_wait() -> void:
	velocity = Vector3.ZERO
	await get_tree().create_timer(post_attack_wait_time).timeout
	_cooldown_timer = attack_cooldown
	set_state(State.CHASE)


func _enable_attack_area() -> void:
	var col: CollisionShape3D = _attack_area.get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", false)


func _disable_attack_area() -> void:
	var col: CollisionShape3D = _attack_area.get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)


# ==============================================================================
# Private Methods - Damage
# ==============================================================================

func _on_damage_recovery_timeout() -> void:
	if _current_state == State.DAMAGE:
		_cooldown_timer = max(_cooldown_timer, post_damage_recovery_pause)

		if _player_ref:
			set_state(State.CHASE)
		else:
			set_state(State.WANDER)


# ==============================================================================
# Private Methods - Utilities
# ==============================================================================

func _look_at_player() -> void:
	if _player_ref:
		var dir: Vector3 = _player_ref.global_position - global_position
		_animated_sprite.flip_h = dir.x < 0


func _update_animations() -> void:
	if _current_state in [State.DEAD, State.DAMAGE, State.ATTACKING, State.ATTACK_COOLDOWN]:
		return

	var anim: String = "idle"
	if velocity.length() > 0.05:
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


func _on_attack_hit_player(body: Node) -> void:
	if _current_state != State.ATTACKING or _hit_registered:
		return

	if body.is_in_group("player"):
		var direction: Vector3 = (body.global_position - global_position).normalized()
		if body.has_method("take_damage_hearts_with_knockback"):
			body.take_damage_hearts_with_knockback(attack_damage, direction, attack_knockback_force)

		_hit_registered = true
		set_state(State.ATTACK_COOLDOWN)
