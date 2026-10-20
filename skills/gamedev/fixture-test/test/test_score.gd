extends GutTest
## Sample unit tests for Score.

func test_hits_stack_combo() -> void:
	var s := Score.new()
	s.hit(10)
	s.hit(10)
	assert_eq(s.points, 30)

func test_combo_caps_at_four() -> void:
	var s := Score.new()
	for i in 6:
		s.hit(1)
	assert_eq(s.combo, 4)

func test_miss_resets_combo() -> void:
	var s := Score.new()
	s.hit(5)
	s.miss()
	assert_eq(s.combo, 1)
