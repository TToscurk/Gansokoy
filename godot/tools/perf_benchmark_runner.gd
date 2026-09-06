extends Node
## Temporary, deterministic render benchmark for maps/slice.
##
## Attach this node only for the A/B run. It creates a runtime-only camera when
## the scene has none, warms pipelines for 120 frames, samples 240 frames from
## the same view, prints Godot Performance monitors, then exits. The node is
## removed from the edited scene after both runs.

const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 240

var _frame := 0
var _fps: Array[float] = []
var _draw_calls: Array[float] = []
var _primitives: Array[float] = []
var _objects: Array[float] = []


func _ready() -> void:
	set_process(false)
	_setup_camera.call_deferred()


func _setup_camera() -> void:
	var viewport := get_viewport()
	if viewport.get_camera_3d() == null:
		var camera := Camera3D.new()
		camera.name = "PerfBenchmarkCamera"
		get_tree().current_scene.add_child(camera)
		camera.global_position = Vector3(320.0, 11.0, -72.0)
		camera.look_at(Vector3(345.0, 2.5, 15.0), Vector3.UP)
		camera.fov = 72.0
		camera.current = true
	set_process(true)
	print("[FPS基準] 暖機 %d 幀，採樣 %d 幀" % [WARMUP_FRAMES, SAMPLE_FRAMES])


func _process(_delta: float) -> void:
	_frame += 1
	if _frame <= WARMUP_FRAMES:
		return

	_fps.append(Performance.get_monitor(Performance.TIME_FPS))
	_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

	if _fps.size() < SAMPLE_FRAMES:
		return

	print("[FPS基準] FPS 平均 %.2f，中位 %.2f，最低 %.2f" % [
		_avg(_fps), _median(_fps), _min_value(_fps)])
	print("[FPS基準] Draw calls 平均 %.0f，Primitives 平均 %.0f，Objects 平均 %.0f" % [
		_avg(_draw_calls), _avg(_primitives), _avg(_objects)])
	set_process(false)
	_finish.call_deferred()


func _finish() -> void:
	# Let the debugger/logger flush the final metrics before exiting.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)


func _avg(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(values.size(), 1.0)


func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _min_value(values: Array[float]) -> float:
	var result := INF
	for value in values:
		result = minf(result, value)
	return result
