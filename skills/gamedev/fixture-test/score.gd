class_name Score
extends RefCounted
## Tracks points with a combo multiplier that resets on a miss.

var points := 0
var combo := 1

func hit(base: int) -> void:
	points += base * combo
	combo = mini(combo + 1, 4)

func miss() -> void:
	combo = 1
