extends Node3D
## Base for anything the player can use with the interact key.
## The player finds these through the "interactable" group (see player.gd).
##
## `requires` is a GameState condition list; the object is only usable when it passes.
## `effects` is a GameState effect list applied on use.
## A non-empty `marker_id` lets objectives point at this object (HUD diamond).

signal used(by: Node)

@export var prompt := "Interact"
@export var interact_radius := 2.2
@export var enabled := true
@export var marker_id := ""

var requires: Array = []
var effects: Array = []


func _ready() -> void:
	add_to_group("interactable")
	if marker_id != "":
		add_to_group("markers")


func is_interactable(_by: Node) -> bool:
	return enabled and is_visible_in_tree() and not DialogueManager.is_active() and GameState.check(requires)


func get_prompt(_by: Node) -> String:
	return prompt


func get_interact_position() -> Vector3:
	return global_position


func interact(by: Node) -> void:
	GameState.apply_effects(effects)
	used.emit(by)
