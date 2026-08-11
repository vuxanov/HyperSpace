extends Node

## Tiny process pump for AssetCache threaded load completion.


func _ready() -> void:
	AssetCache.set_poll_host(self)
	set_process(true)


func _process(_delta: float) -> void:
	AssetCache.poll()
