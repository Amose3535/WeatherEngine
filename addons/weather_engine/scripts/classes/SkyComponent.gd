@tool
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
@export_group("Setup")
## The player node (or the one considered the current character, like the active camera). It's used for parallax and weather effects.
@export var player : Node3D
## The SAME resource that the WorldEnvironment of this scene is using for the sky. If on ANY side it's made unique then this won't work.[br]
## NOTE: This MUST be AndreySoldatov's sky shader or all this won't work.
@export var sky_res : ShaderMaterial
@export var celestial_bodies_pivot : Node3D
## The sun node. Used to map the stars cubemap. Moved trhough time passing.
@export var sun : DirectionalLight3D
## The moons (if any) present in the scene.
@export var moons : Array[DirectionalLight3D] = []

@export_group("Time")
## Wether the time should be processed or not.
@export var active : bool = true
## The current progress of this day. Goes from 0 (midnight) to 1 (the next midnight). 0.5 means noon etc etc.
@export_range(0.0, 1.0, 0.0001, "or_greater") var day_progress: float = 0:
	set = _set_day_progress
## How much time scales in game. 1 means that 1 in-game day = 24 hours, 2 = 12h, 3 = 8h, etc...[br]The default value is 60 (one full cycle in 24 minutes).
@export var time_scale : float = 60
# TODO (maybe in the future):
## IF realtime is on, time_scale is set to 1 and the progress is set to be the same as the current datetime
#@export var realtime : bool = false

@export_group("Atmosphere")
@export var wind_strength : float = 2.0


@export_group("Geography")
## The latitude is the angular distance (in degrees) from the equator considering the center of the earth as your reference frame.
@export_range(-90.0,90.0) var latitude : float = 0:
	set = _set_latitude

@export_category("DEBUG")
@export var metrics : bool = false
@export var day_updates : bool = false
@export var sun_updates : bool = false
@export var geography : bool = false
#endregion EXPORTS







#region VARIABLES

#endregion VARIABLES







#region SETTERS/GETTERS
func _set_day_progress(raw_value: float) -> void:
	if metrics:
		if day_updates:
			print("Updated: %f"%raw_value)
	var completed_days := 0
	
	if raw_value >= 1.0:
		completed_days = int(floor(raw_value))          # How many times i passed "1.0"
	# If raw_value < 0.0 it means we went backwards => No signal
	
	day_progress = fposmod(raw_value, 1.0)              # wrap in [0,1)
	
	if completed_days == 1:
		emit_signal("day_completed")
	elif completed_days > 1:
		emit_signal("days_skipped", completed_days)
	
	_update_sun_pos()


## Maps the progress 0-1 onto the rotation in degrees 0-360
func _update_sun_pos(daylight_cycle_progress : float = day_progress) -> void:
	if !is_inside_tree() || sun == null:
		return
	
	var sun_angle_deg : float = daylight_cycle_progress*360
	# No need to check for overflowing because when a daylight cycle bigger than 1 will get auto mapped onto [0,1)
	# Even if it slipped through, angles bigger than 360° get auto mapped onto their correct [0,360) angle.
	
	if metrics:
		if sun_updates:
			print("Updating Sun's angle: %f"%sun_angle_deg)
	
	# Z axis is the one going from north to south (-z, +z). Hence the rotation happens from east to west (+x, -x)
	sun.rotation.y = deg_to_rad(sun_angle_deg+180)

## Sets sun's latitude
func _set_latitude(new_latitude : float = latitude) -> void:
	if !is_inside_tree() || celestial_bodies_pivot == null:
		return
	# Safety check in case somebody didn't use the slider and tried to set forcefully the value.
	new_latitude = clamp(new_latitude,-90.0,90.0)
	latitude = new_latitude
	if metrics:
		if geography:
			print("Updating celestial bodies' latitude. New latitude: %f"%new_latitude)
	# Set the celestial bodies' x rotation as latitude offset by +90 degrees (to align on the +/-X axis (east/west) )
	celestial_bodies_pivot.global_rotation.x = deg_to_rad(new_latitude-90)

#endregion SETTERS/GETTERS







func _ready():
	pass


func _physics_process(delta: float) -> void:
	if active:
		# Increment the day by delta (real time passed between frames) times the time scale.
		advance_day(delta*time_scale)






#region FUNCTIONS

## API used to increment the day by a delta. By default used in physics process.
func advance_day(delta: float) -> void:
	day_progress += delta # setter function gets called automatically

#endregion FUNCTIONS
