class_name FinaleSchedule
extends RefCounted

var patterns: Array

func _init(data: Array) -> void:
	patterns = data

func stage(escort_count: int, boss_phase: int, seconds: float) -> int:
	if escort_count >= 495 or boss_phase >= 2 or seconds >= 212.0:
		return 2
	if escort_count >= 180 or boss_phase >= 1 or seconds >= 100.0:
		return 1
	return 0

func gap(escorts_dispatched: int, stage_index: int, living: int, boss_down: bool) -> float:
	var spec: Dictionary = patterns[stage_index]
	var pack := int(spec.pack)
	var inner := float(spec.inner)
	var interval := inner
	if escorts_dispatched > 0 and escorts_dispatched % pack == 0:
		interval = float(spec.mean) * pack - inner * (pack - 1)
	# Pressure stretches pauses modestly. A defeated boss releases reserves sooner.
	var pressure := clampf(float(living - 115) / 450.0, 0.0, 0.19)
	return interval * (1.0 + pressure) * (0.82 if boss_down else 1.0)

func elite_weight(stage_index: int) -> float:
	return float(patterns[stage_index].elite)
