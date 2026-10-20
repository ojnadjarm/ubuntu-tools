extends GutTest
## Bot steering.

func test_nearest_target() -> void:
	var t: Array[Vector3] = [Vector3(5, 0, 0), Vector3(1, 0, 1), Vector3(-4, 0, 0)]
	assert_eq(Bot.nearest(Vector3.ZERO, t), 1)

func test_steer_is_flat_unit() -> void:
	var t: Array[Vector3] = [Vector3(3, 2, 4)]
	var d := Bot.steer(Vector3.ZERO, t)
	assert_almost_eq(d.length(), 1.0, 0.001)
	assert_eq(d.y, 0.0)

func test_no_targets_stops() -> void:
	var t: Array[Vector3] = []
	assert_eq(Bot.steer(Vector3.ZERO, t), Vector3.ZERO)
