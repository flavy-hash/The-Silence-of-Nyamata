extends Area3D
## Invisible volume that fires effects when the player walks into it.
## Use for "reach the hill"-style objectives and scripted moments.

signal triggered

@export var once := true
var requires: Array = []
var effects: Array = []
var _fired := false


func setup(radius: float, height: float = 4.0) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	try_fire()


func try_fire() -> bool:
	if (once and _fired) or not GameState.check(requires):
		return false
	_fired = true
	GameState.apply_effects(effects)
	triggered.emit()
	return true
