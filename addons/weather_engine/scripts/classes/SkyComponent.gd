extends Node
class_name SkyComponent
## Bridge between AndreySoldatov's procedural sky shader and game logic.
##
## This autoload acts as the only central endpoint to access and make the logic work.


#region SIGNALS
signal day_completed()
signal days_skipped(days_passed : int)
#endregion SIGNALS




#region EXPORTS.
@export_range(0.0, 1.0, 0.0001, "or_greater") var day_progress: float = 0:
	set = set_day_progress

@export var player : Node3D
@export var sun : DirectionalLight3D
#endregion EXPORTS

#region SETTERS/GETTERS
func set_day_progress(raw_value: float) -> void:
	var completed_days := 0
	
	if raw_value >= 1.0:
		completed_days = int(floor(raw_value))          # How many times i passed "1.0"
	# If raw_value < 0.0 it means we went backwards => No signal
	
	day_progress = fposmod(raw_value, 1.0)              # wrap in [0,1)
	
	if completed_days == 1:
		emit_signal("day_completed")
	elif completed_days > 1:
		emit_signal("days_skipped", completed_days)



#endregion SETTERS/GETTERS


#region VARIABLES
var  huh
#endregion VARIABLES


func _ready():
	pass
