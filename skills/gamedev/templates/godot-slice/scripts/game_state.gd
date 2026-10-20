class_name GameState
extends RefCounted
## Rules of the slice: collect every coin before the timer runs out.

signal changed

var total: int
var collected := 0
var time_left: float
var points := 0

func _init(coins: int = 8, seconds: float = 60.0) -> void:
	total = coins
	time_left = seconds

func collect(value: int = 10) -> void:
	if is_over():
		return
	collected += 1
	points += value + int(time_left)
	changed.emit()

func tick(delta: float) -> void:
	if is_over():
		return
	time_left = maxf(time_left - delta, 0.0)

func won() -> bool:
	return collected >= total

func is_over() -> bool:
	return won() or time_left <= 0.0
