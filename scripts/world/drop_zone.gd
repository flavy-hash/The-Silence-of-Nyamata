extends "res://scripts/world/interactable.gd"
## Accepts a carried item (e.g. sacks into a storehouse) and applies `effects`.

signal delivered(item_id: String)

@export var accepts := "bean_sack"


func is_interactable(by: Node) -> bool:
	return super(by) and by.get("carried_item") == accepts


func interact(by: Node) -> void:
	var id: String = by.drop_carried()
	delivered.emit(id)
	super(by)
