extends GutTest
## GameState rules.

func test_collect_all_wins() -> void:
	var g := GameState.new(2, 30.0)
	g.collect()
	assert_false(g.won())
	g.collect()
	assert_true(g.won())
	assert_true(g.is_over())

func test_time_bonus_in_points() -> void:
	var g := GameState.new(3, 20.0)
	g.collect(10)
	assert_eq(g.points, 30)

func test_timeout_ends_and_blocks_collect() -> void:
	var g := GameState.new(3, 1.0)
	g.tick(2.0)
	assert_eq(g.time_left, 0.0)
	g.collect()
	assert_eq(g.collected, 0)
