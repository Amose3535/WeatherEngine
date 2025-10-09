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
## NOTE: This MUST be AndreySoldatov's sky shader or all this won't work.[br]
## This is an export mainly so that the user can see what parameteres are in the shader.
@export var sky_res : ShaderMaterial = preload("res://addons/weather_engine/resources/sky/TestScene1.tres")
## The NoiseTexture3D for the shape of the clouds. By default it's the same exact one used by the sky shader
@export var cloud_shape_res : NoiseTexture3D = preload("res://addons/weather_engine/resources/NoiseTexture3Ds/cloud_shape_1.tres")
## The NoiseTexture3D for the noise of the clouds. By default it's the same exact one used by the sky shader
@export var cloud_noise_res : NoiseTexture3D = preload("res://addons/weather_engine/resources/NoiseTexture3Ds/cloud_noise_1.tres")
## The Node3D (Can be anything, really, as long as it inherits Node3D) that contains all the celesdtial bodies (Sun, moon, etc). Used to simulate latitude.
@export var celestial_bodies_pivot : Node3D
## The sun node. Used to map the stars cubemap. Moved trhough time passing.
@export var sun : DirectionalLight3D
## The moons (if any) present in the scene.
@export var moons : Array[DirectionalLight3D] = []
## Decides wether the node should process anything or not
@export var active : bool = true


@export_group("Time")
## Wether the time should be processed or not.
@export var time_active : bool = true
## The current progress of this day. Goes from 0 (midnight) to 1 (the next midnight). 0.5 means noon etc etc.
@export_range(0.0, 1.0, 0.0001, "or_greater") var day_progress: float = 0:
	set = _set_day_progress
## How much time scales in game. 1 means that 1 in-game day = 24 hours, 2 = 12h, 3 = 8h, etc...[br]The default value is 60 (one full cycle in 24 minutes).
@export var time_scale : float = 60
# TODO (maybe in the future):
## IF realtime is on, time_scale is set to 1 and the progress is set to be the same as the current datetime
#@export var realtime : bool = false


@export_group("Atmosphere")
## Wether the clouds should be processed or not.
@export var clouds_active : bool = true
## Wether to enable or not cloud parallax when player node is moving.
@export var cloud_parallax : bool = true
## How strong should the cloud parallax be
@export var cloud_parallax_strength : float = 1.0
## The altitude (from sea level) at which the clouds appear and parallax should be simulated
@export var cloud_altitude : float = 800
## How often should winds be recalculated. For best realism and performance it's reccomended to be kept between 10 and 30 IRL seconds which translate (at time_scale = 60) to 10-30 in-game minutes
@export var wind_recalculation_time : float = 20
## Wether cloud winds are enabled or not
@export var cloud_winds : bool = true
## The strength at which wind is pushing clouds
@export var wind_strength : float = 2.0
## How radically can winds change: -1 means that the next wind direction can be completely random, 0 means that it's at most at a 90° angle from the previous one, 1 means that it won't change.
@export_range(-1.0,1.0,0.0001) var wind_randomicity : float = 0.5


@export_group("Weather")
## Wether the weather should be processed or not.
@export var weather_active : bool = true
## How often should the weather be recalculated. Default is 720 (== once every half day at time_scale = 60)
@export var weather_recalculation_time : float = 720
## How stable the weather's condition is: 0 is completely unstable (changes rapidly), 1 is completely stable (doesn't change).
@export_range(0.0,1.0,0.0001) var  weather_stability : float = 0.5
## How random can the weather be every time it's recalculated: values close to 0 will yield little to no changes in weather, while values close to 1 will yield nearly completely random weather
@export_range(0.0,1.0,0.0001) var weather_randomicity : float = 0.5
## The current condition of the weather: 0 is REALLY BAD weather, 100 is REALLY GOOD weather
@export_range(0.0,100.0,0.0001) var weather_condition_percentage : float = 25.0:
	set = _set_weather_condition_percentage

@export_group("Geography")
## The latitude is the angular distance (in degrees) from the equator considering the center of the earth as your reference frame.
@export_range(-90.0,90.0) var latitude : float = 0:
	set = _set_latitude


@export_category("DEBUG")
@export var metrics : bool = false
@export var day_updates : bool = false
@export var sun_updates : bool = false
@export var cloud_parallax_updates : bool = false
@export var cloud_wind_updates : bool = false
@export var geography : bool = false
#endregion EXPORTS







#region VARIABLES AND CONSTANTS
## The global player position in the PREVIOUS frame 
var old_player_pos : Vector3 = Vector3.ZERO
## The time elapsed since the last wind recomputation
var last_wind_update : float = 0.0
## The last wind direction (Clouds, although 3d, move along a 2d plane)
var wind_direction : Vector3
## The cumulative offset copmuted for the shader
var clouds_cumulative_offset : Vector3 = Vector3.ZERO
## The time elapsed since the last weather recomputation
var last_weather_update : float = 0.0
#endregion VARIABLES AND CONSTANTS







#region SETTERS/GETTERS
## Sets the current progress to a a value in the period [0 + 2k*π, 1 + 2k*π) + emits correct signals based on initial conditions
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
	
	# Also update stars rotation to simulate a spinning planet
	if sky_res != null:
		sky_res.set_shader_parameter("stars_rotation",sun.global_basis)
	
	# Code i took from [https://github.com/AndreySoldatov/Godot-Sky-Plus-Plus/blob/main/scripts/sky.gd : 51]
	# Creates a weight based on the sun's angular distance from the azimut
	var sun_weight : float = sun.global_basis.z.normalized().dot(Vector3.UP)
	# Interpolates with smoothstep
	var sun_energy : float = smoothstep(-0.09, -0.00, sun_weight)
	# Compute weight through the formula weight = sqrt(weight_clamped_in_0-1)
	sun_weight = pow(clamp(sun_weight, 0.0, 1.0), 0.5)
	# Use the computed weight to get the color that the sun should have
	var sun_color = kelvin_to_rgb(lerpf(1500, 6500, sun_weight))
	# Apply params
	sun.light_color = sun_color
	sun.light_energy = sun_energy

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

## Sets the weather condition and some other parameters
func _set_weather_condition_percentage(new_value) -> void:
	if !is_inside_tree() || sky_res == null:
		return
	new_value = clamp(new_value,0.0,100.0)
	weather_condition_percentage = new_value
	# Set sky_res' properties for it to actually make sense
	# Sky coverage: Map it from 0.0 -> 0.0 to  100.0 -> 0.6
	var coverage_value = (new_value / 100.0) * 0.6
	sky_res.set_shader_parameter(&"coverage", coverage_value)

## Simulates the shader's 'take_cloud_sample' function to get the cloud density at a specific 3D point.
## Reads all configuration parameters directly from the linked 'sky_res' ShaderMaterial.
func get_cloud_pixel_at_pos(position : Vector3) -> float:
	if !is_instance_valid(sky_res):
		return 0.0
		
	# Check for valid Noise resources (needed for CPU sampling)
	if !is_instance_valid(cloud_shape_res) or !is_instance_valid(cloud_noise_res):
		return 0.0
	if !is_instance_valid(cloud_shape_res.noise) or !is_instance_valid(cloud_noise_res.noise):
		return 0.0
	
	# 1. Read Shader Uniforms directly from the ShaderMaterial
	# These names MUST match the uniform names in the GLSL shader
	const SHADER_SCALE = 0.01 # Hardcoded constant from shader: (coord * size * 0.01)
	
	var cloud_shape_size_g: float = sky_res.get_shader_parameter("cloud_shape_size")
	var cloud_noise_size_g: float = sky_res.get_shader_parameter("cloud_noise_size")
	var cloud_noise_factor_g: float = sky_res.get_shader_parameter("cloud_noise_factor")
	var coverage_g: float = sky_res.get_shader_parameter("coverage")
	var cloud_smoothness_g: float = sky_res.get_shader_parameter("cloud_smoothness")
	var hole_in_center_g: bool = sky_res.get_shader_parameter("hole_in_center")
	var hole_radius_g: float = sky_res.get_shader_parameter("hole_radius")
	var hole_feather_g: float = sky_res.get_shader_parameter("hole_feather")
	
	# 2. Calculate the sampled coordinates in Noise Space (position * size * 0.01 + offset)
	var shape_coord = (position * cloud_shape_size_g * SHADER_SCALE) + clouds_cumulative_offset
	var noise_coord = (position * cloud_noise_size_g * SHADER_SCALE) + clouds_cumulative_offset
	
	# 3. Sample the Noise Resources
	var shape_sample: float = cloud_shape_res.noise.get_noise_3d(shape_coord.x, shape_coord.y, shape_coord.z)
	var noise_sample: float = cloud_noise_res.noise.get_noise_3d(noise_coord.x, noise_coord.y, noise_coord.z)
	
	# Map Godot's get_noise_3d() output from [-1, 1] to the shader's texture range [0, 1]
	shape_sample = (shape_sample + 1.0) / 2.0
	noise_sample = (noise_sample + 1.0) / 2.0

	# 4. Blending (cloud_shape * (1.0 - factor) + cloud_noise * factor)
	var mixed_sample: float = lerp(shape_sample, noise_sample, cloud_noise_factor_g)

	# 5. Hole in Center (optional logic from shader)
	if hole_in_center_g:
		var hole_factor: float = smoothstep(hole_radius_g - hole_feather_g, hole_radius_g + hole_feather_g, Vector2(position.x,position.z).length())
		mixed_sample *= hole_factor
	
	# 6. Apply Coverage and Smoothness (smoothstep(1.0 - coverage - smoothness, 1.0 - coverage + smoothness, mixed_sample))
	var invert_coverage: float = 1.0 - coverage_g
	
	# The final density for this specific point in space
	return smoothstep(invert_coverage - cloud_smoothness_g, invert_coverage + cloud_smoothness_g, mixed_sample)

## Calculates the total volumetric cloud density in the column above the given XZ position.
## This simulates the vertical integration (ray marching) of the clouds.
func get_cloud_column_density(pos_xz : Vector2) -> float:
	# NOTE: These are based on typical cumulus cloud heights.
	const CLOUD_MIN_HEIGHT = 500.0   # Start sampling at a reasonable altitude
	const CLOUD_MAX_HEIGHT = 8000.0  # End sampling (Max height for cumulus)
	const NUM_SAMPLES = 64           # Matches the shader's default 'cloud_marches'
	
	var total_density: float = 0.0
	var cloud_height_range: float = CLOUD_MAX_HEIGHT - CLOUD_MIN_HEIGHT
	var step_size: float = cloud_height_range / float(NUM_SAMPLES)
	
	# Initialize the 3D position at the bottom of the column
	var sample_pos = Vector3(pos_xz.x, CLOUD_MIN_HEIGHT, pos_xz.y)
	
	# Simulate Vertical Ray Marching (Column Integration)
	for i in range(NUM_SAMPLES):
		# Get the density at the current point
		var density_at_point = get_cloud_pixel_at_pos(sample_pos)
		
		# Accumulate the density along the vertical ray
		total_density += density_at_point
		
		# Move up to the next sample point
		sample_pos.y += step_size
		
	# Normalize the accumulated density. Max possible is NUM_SAMPLES * 1.0
	var max_possible_density = float(NUM_SAMPLES)
	
	# Returns a value between [0.0 (clear sky), 1.0 (max density)]
	return clamp(total_density / max_possible_density, 0.0, 1.0)

## Function used to get a random float value inside a neighbourhood delta with an upper and lower bound
func randf_delta_range(initial: float, delta: float, upper_bound: float, lower_bound: float) -> float:
	# define upper and lower bounds
	var upper : float = initial + delta
	var lower : float = initial - delta
	if upper > upper_bound: upper = upper_bound
	if lower < lower_bound: lower = lower_bound
	
	return randf_range(lower,upper)

#endregion SETTERS/GETTERS







func _ready():
	pass


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): # Insert editor logic here
		pass
	
	if active:
		if time_active:
			# Increment the day by delta day (game time equivalent of real time passed between frames) times the time scale.
			var delta_day = (delta*time_scale)/86400
			advance_day(delta_day)
		
		if clouds_active:
			# Update the clouds position through parallax
			_update_clouds(delta)
		
		if weather_active:
			_update_weather(delta)




#region FUNCTIONS

## API used to increment the day by a delta. By default used in physics process.
func advance_day(in_game_delta: float) -> void:
	_set_day_progress(day_progress + in_game_delta)

## This function was neatly implemented here by AndreySoldatov: [https://github.com/AndreySoldatov/Godot-Sky-Plus-Plus/blob/main/scripts/sky.gd : line 13]
func kelvin_to_rgb(temp_kelvin: float) -> Color:
	var temperature = temp_kelvin / 100.0
	
	var red: float
	var green: float
	var blue: float
	
	# Compute red, green and blue contribution based on the temperature
	if temperature <= 66.0:
		red = 255.0
	else:
		red = temperature - 60.0
		red = 329.698727446 * pow(red, -0.1332047592)
		red = clamp(red, 0.0, 255.0)
	
	if temperature <= 66.0:
		green = 99.4708025861 * log(temperature) - 161.1195681661
		green = clamp(green, 0.0, 255.0)
	else:
		green = temperature - 60.0
		green = 288.1221695283 * pow(green, -0.0755148492)
		green = clamp(green, 0.0, 255.0)
	
	if temperature >= 66.0:
		blue = 255.0
	elif temperature <= 19.0:
		blue = 0.0
	else:
		blue = temperature - 10.0
		blue = 138.5177312231 * log(blue) - 305.0447927307
		blue = clamp(blue, 0.0, 255.0)
	
	# return the colors given by the computed RGB
	return Color(red / 255.0, green / 255.0, blue / 255.0)

## Generates a random normalized 3D vector biased towards 'initial_direction'.[br]
## [br]
## [code]initial_direction[/code]: The normalized base vector (the target direction).[br]
## [code]bias_factor[/code]: The weight of the bias, ranging from -1.0 to 1.0.[br]
##   - [code]1.0[/code]: Returns exactly 'initial_direction' (0 degrees deviation).[br]
##   - [code]0.0[/code]: Returns a random vector within the hemisphere pointed by 'initial_direction' (max 90 degrees deviation).[br]
##   - [code]-1.0[/code]: Returns a completely random vector across the entire sphere (max 180 degrees deviation).[br]
##[br]
## Returns: a random normalized 3D vector.
func get_biased_random_vector(initial_direction: Vector3, bias_factor: float) -> Vector3:
	
	# Ensure the initial vector is normalized for correct spherical calculations.
	var base_direction = initial_direction.normalized()
	
	# 1. Handle Edge Cases
	
	# Case 1.0: Full bias - return the exact direction.
	if bias_factor >= 1.0:
		return base_direction
	
	# Case -1.0: Zero bias - return a fully random vector on the entire sphere.
	if bias_factor <= -1.0:
		# Random point inside a cube, then normalized (a simple way to get uniform random on a sphere)
		var random_vec = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		return random_vec.normalized()
	
	# 2. Generate Base Random Vector
	
	# Generate an initial random vector on the full sphere.
	var random_vector = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	
	# 3. Apply Bias and Correct Direction (SLERP)
	
	# Clamp the effective bias to [0, 1] for deviation angle calculation.
	var effective_bias = clampf(bias_factor, 0.0, 1.0)
	
	# Calculate the maximum deviation angle (in radians).
	# This maps the bias factor (1.0 to 0.0) to the maximum angle (0 to 90 degrees/PI/2).
	# This defines the "cone" of acceptable random directions.
	var max_deviation_angle = (PI / 2.0) * (1.0 - effective_bias)
	
	# Calculate the angle between the random vector and the target direction.
	var angle_between = base_direction.angle_to(random_vector)
	
	# Calculate the slerp weight needed to pull the random vector back into the cone.
	var slerp_weight = 0.0
	if angle_between > max_deviation_angle:
		# If the random vector is outside the cone, calculate how much it needs to be
		# pulled back toward the base_direction to be exactly at max_deviation_angle.
		slerp_weight = (angle_between - max_deviation_angle) / angle_between
	
	# Spherical Linear Interpolation (SLERP): moves the random vector along the sphere's surface
	# toward the target direction, limiting the final result to the max_deviation_angle cone.
	var result_vector = random_vector.slerp(base_direction, slerp_weight)
	
	# 4. Handle Negative Bias Case (Expanding Beyond Hemisphere)
	
	# If the bias is negative (e.g., -0.5), we allow the vector to exist in the "back hemisphere"
	# as well, effectively relaxing the constraint towards the fully random sphere.
	# Since the SLERP above ensures the vector is within 90 degrees, we don't need
	# complex calculation here, as the initial random_vector generation handles the full sphere.
	# The effective_bias clamp to 0 ensures max_deviation_angle is max 90 degrees.
	# The initial check for bias <= -1.0 already covers the full random case.
	
	return result_vector.normalized()

## Function used to update clouds position using parallax and wind simulation.
func _update_clouds(delta : float) -> void:
	if (metrics == true):
		if (cloud_wind_updates == true || cloud_parallax_updates == true):
			print("------------------- CLOUDS -------------------")
	# NOTE: Total offset = player offset + (previous cloud offset + new wind displacement)
	# The vector that stores the cloud movement 
	var cloud_offset_vector : Vector3 = Vector3.ZERO
	
	# Compute parallax
	if (cloud_parallax == true):
		# By default player node is set to player
		var player_node : Node3D = player
		# If however player is null, set player_node to the current active camera as a fallback
		if (player == null):
			player_node = get_viewport().get_camera_3d()
		# If somehow it's still null, skip entirely
		if (player_node != null):
			# Compute player contribution: -(pos/altitude)*parallax_strength
			var player_contribution : Vector3 = Vector3(-((player_node.global_position-old_player_pos)/cloud_altitude) * cloud_parallax_strength)
			# Add to offset vector an offset EXCLUSIVELY on the XZ plane: Disregard y component and normalize
			cloud_offset_vector += Vector3(player_contribution.x,0,player_contribution.z)
			# Metrics
			if (metrics == true):
				if (cloud_parallax_updates == true):
					print("Updated parallax: Old pos: %s - New pos: %s - Delta pos: %s - Contribution: %s"%[str(old_player_pos),str(player_node.global_position),str(player_node.global_position-old_player_pos),str(player_contribution)])
			# Update old player pos with the current one to be used in the next frame
			if (player_node != null): old_player_pos = player_node.global_position
		
	
	# Compute winds
	if (cloud_winds == true):
		# If cloud winds are enabled, add it's contribution => contribution = direction*strength*delta
		var wind_contribution : Vector3 = wind_direction*wind_strength*delta
		# Add to offset vector an offset EXCLUSIVELY on the XZ plane: Disregard y component and normalize
		cloud_offset_vector += Vector3(wind_contribution.x,0,wind_contribution.z)
		# Metrics
		if (metrics == true):
			if (cloud_wind_updates == true):
				print("Updated wind: Last update: %s, Recalculation time: %s	")
		# Update wind direction when last update >= wind recalc time
		last_wind_update += delta
		if (last_wind_update >= wind_recalculation_time):
			last_wind_update -= wind_recalculation_time
			# If the wind_direction == null or 0,0, get a completely random direction
			if wind_direction == null || wind_direction == Vector3.ZERO: 
				wind_direction = get_biased_random_vector(Vector3.UP,-1)
			# Otherwise, compute the next random direction from the previous one using the wind randomicity
			else:
				wind_direction = get_biased_random_vector(wind_direction, wind_randomicity)
	
	# After computing the offset for the current frame, subtract the previous offset for the frame delta offset
	clouds_cumulative_offset += cloud_offset_vector
	
	sky_res.set_shader_parameter("cloud_shape_offset",clouds_cumulative_offset)
	sky_res.set_shader_parameter("cloud_noise_offset",clouds_cumulative_offset)
	
	if (metrics == true):
		if (cloud_wind_updates == true || cloud_parallax_updates == true):
			print("----------------------------------------------")

## Function used to update the weather conditions using time as a reference frame
func _update_weather(delta : float) -> void:
	# Logic to update the weather stability
	last_weather_update += delta
	if last_weather_update >= weather_recalculation_time:
		# Reset timer
		last_weather_update -= weather_recalculation_time
		# Get the weather stability
		weather_stability = randf_delta_range(weather_stability,weather_randomicity/2,1.0,0.0)
		# Update conditions: First define a target value based on weather staibility, then tween towards the values.
		# NOTE: This formula is arbitrary and it's pulled right out of my ASS so if it don't work feel free to change it to something else
		var target_weather_condition = weather_condition_percentage + randf_range(-1.0, 1.0)*(1 / weather_stability)
		var weather_tweener : Tween = Tween.new()
		weather_tweener.tween_property(self, ^"weather_condition_percentage", target_weather_condition, weather_stability*100.0)
	

#endregion FUNCTIONS
