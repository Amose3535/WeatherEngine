extends Node3D


@onready var _active = false
@onready var _day_progress = 0.0
@onready var _time_scale = 0.0
@onready var _wind_strength = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_active_check_box_toggled(toggled_on: bool) -> void:
	pass # Replace with function body.
