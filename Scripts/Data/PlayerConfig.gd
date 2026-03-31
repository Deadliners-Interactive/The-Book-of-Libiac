## Player tunable configuration resource.
## Allows balancing player stats without editing player.gd.
extends Resource
class_name PlayerConfig

# ==============================================================================
# Movement
# ==============================================================================

@export var move_speed: float = 1.0
@export var jump_speed: float = 2.0
@export var gravity_multiplier: float = 1.0
@export var ground_snap_length: float = 0.34
@export var max_floor_angle_degrees: float = 58.0
@export var floor_stop_on_slope: bool = false
@export var floor_constant_speed: bool = true
@export var collision_safe_margin: float = 0.0002

# ==============================================================================
# Combat
# ==============================================================================

@export var attack_damage: int = 10
@export var attack_movement_multiplier: float = 0.6
@export var attack_hit_delay: float = 0.1

# ==============================================================================
# Health
# ==============================================================================

@export var max_health: float = 30.0
@export var invulnerability_time: float = 1.0
@export var damage_visual_time: float = 0.5

# ==============================================================================
# Roll
# ==============================================================================

@export var roll_speed: float = 3.0
@export var roll_duration: float = 0.4
@export var roll_cooldown: float = 0.2

# ==============================================================================
# FSM Transitions
# ==============================================================================

@export_group("FSM Transitions")
@export var allow_normal_to_attacking: bool = true
@export var allow_normal_to_rolling: bool = true
@export var allow_normal_to_damage: bool = true

@export var allow_attacking_to_normal: bool = true
@export var allow_attacking_to_rolling: bool = true
@export var allow_attacking_to_damage: bool = true

@export var allow_rolling_to_normal: bool = true
@export var allow_rolling_to_damage: bool = true

@export var allow_damage_to_normal: bool = true
