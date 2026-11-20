extends "res://scripts/world/interactable.gd"
## An object the player can lift and carry (one at a time), e.g. a sack of beans.
## Pair with drop_zone.gd to deliver it somewhere.

@export var item_id := "bean_sack"
var visual: Node3D


func _ready() -> void:
	super()
	if visual:
		add_child(visual)


func is_interactable(by: Node) -> bool:
	return super(by) and by.get("carried_item") == ""


func interact(by: Node) -> void:
	if by.pick_up(item_id):
		hide()
		super(by)
