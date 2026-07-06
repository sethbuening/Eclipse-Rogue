class_name ClassData
extends Resource

## Stub character/class definition used by the mission setup flow.
## Design note: there will likely just be a flat list of individual classes
## rather than a deep class -> subclass tree. `key_class` is reserved for the
## future case where a handful of "key classes" gain multiple subclass
## variants; leave it empty (&"") for a standalone class like the stubs below.

@export var id:           StringName = &""
@export var display_name: String     = ""
@export var description:  String     = ""
@export var portrait:     Texture2D  = null
@export var key_class:    StringName = &""
