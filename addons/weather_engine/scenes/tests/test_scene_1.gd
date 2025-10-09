extends Node3D


@onready var sky_component: SkyComponent = $SkyComponent
@onready var container: Container = $CanvasLayer/Base/Container
@onready var panel_container: PanelContainer = $CanvasLayer/Base/Container/HBoxContainer/PanelContainer

@onready var base: MarginContainer = $CanvasLayer/Base
@onready var toggler: Button = $CanvasLayer/Base/Container/HBoxContainer/Toggler






# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_active_check_box_toggled(toggled_on: bool) -> void:
	pass # Replace with function body.



func _on_toggler_toggled(toggled_on: bool) -> void:
	print("ME BOOOMBOOOCLLLAAAATT")
	if !toggled_on:
		var in_tweener: Tween = base.create_tween()
		in_tweener.set_ease(Tween.EASE_IN)
		in_tweener.tween_property(base,"global_position:x",0,0.2)
	else:
		var out_tweener: Tween = base.create_tween()
		out_tweener.set_ease(Tween.EASE_IN)
		out_tweener.tween_property(base,"global_position:x",-panel_container.size.x-10,0.2)
