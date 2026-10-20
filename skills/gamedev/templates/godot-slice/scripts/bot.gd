class_name Bot
extends RefCounted
## Autoplay steering: a flat unit direction toward the nearest target.

static func nearest(from: Vector3, targets: Array[Vector3]) -> int:
	var best := -1
	var best_d := INF
	for i in targets.size():
		var d := from.distance_squared_to(targets[i])
		if d < best_d:
			best_d = d
			best = i
	return best

static func steer(from: Vector3, targets: Array[Vector3]) -> Vector3:
	var i := nearest(from, targets)
	if i < 0:
		return Vector3.ZERO
	var d := targets[i] - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO
