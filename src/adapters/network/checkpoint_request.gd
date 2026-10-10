extends SimulationCommand
class_name CheckpointRequest

## Remote I/O intent. The host handles it outside simulation command execution.
var operation: String = "checkpoint"
var payload: Dictionary = {}
