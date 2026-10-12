class_name Waves
extends RefCounted
## Wave composition (spec §4.3, §4.4). Board rows: HTML y -> r = 7 - y, so the spawn zone is r 6..7.

const GIMMICKS := ["hydra", "illusionist", "goblinRaid", "ninjaRaid", "splitterRaid", "sprinterRaid"]

const GIMMICK_INFO := {
	"hydra": {"title": "히드라 습격!", "hint": "쓰러뜨려도 2초 뒤 부활 — 4마리를 동시에 쓰러뜨리세요"},
	"illusionist": {"title": "환술사 등장!", "hint": "환영 4마리 중 진짜 환술사 1마리를 찾아 처치하세요"},
	"goblinRaid": {"title": "고블린 부대 습격!", "hint": "고블린 6마리 돌격, 뒤에서 돌팔매꾼이 엄호합니다"},
	"ninjaRaid": {"title": "닌자 습격!", "hint": "가장 멀리 있는 아군에게 순간 도약합니다"},
	"splitterRaid": {"title": "분열체 무리 등장!", "hint": "쓰러지면 작은 개체 2마리로 갈라집니다"},
	"sprinterRaid": {"title": "질주 몬스터 등장!", "hint": "순식간에 2칸씩 돌진합니다"},
	"giantBoss": {"title": "거대 중간보스 등장!", "hint": "2×2 크기, 넉백 면역, 매우 높은 체력"},
}

static func pick_gimmick(wave: int) -> String:
	if wave >= 35 and wave % 5 == 0:
		return "giantBoss"
	if wave >= 3 and randf() < 0.45:
		return GIMMICKS[randi() % GIMMICKS.size()]
	return ""

## r_min = 7 keeps a unit on the back row (ranged support behind the melee line).
static func _free_tile(used: Dictionary, size := 1, tries := 50, r_min := 6) -> Vector2i:
	for i in tries:
		var c := randi_range(0, 6 - size)
		var r := randi_range(r_min, 8 - size)
		var ok := true
		for dx in size:
			for dy in size:
				if used.has(Vector2i(c + dx, r + dy)):
					ok = false
		if ok:
			for dx in size:
				for dy in size:
					used[Vector2i(c + dx, r + dy)] = true
			return Vector2i(c, r)
	return Vector2i(-1, -1)

## Ranged support per group: 1 early on, up to 3 later, never more than half the group.
static func ranged_count(wave: int, cnt: int) -> int:
	return clampi(1 + int(wave / 8.0), 1, mini(3, int(cnt / 2.0)))

## Ranged kind for a group: slingers from the start, crossbow snipers from wave 6, fire shamans from wave 12.
static func pick_ranged(wave: int) -> String:
	var pool := [["slinger", 1.0]]
	if wave >= 6:
		pool.append(["crossbow", 0.7])
	if wave >= 12:
		pool.append(["shaman", 0.6])
	var total := 0.0
	for e in pool:
		total += e[1]
	var r := randf() * total
	for e in pool:
		r -= e[1]
		if r <= 0.0:
			return e[0]
	return "slinger"

## Normal sub-wave: list of {kind, tile}. The first ranged_count units are ranged support on the back row.
static func normal(wave: int) -> Array:
	var cnt := mini(3 + int(floorf(wave * 0.5)), 10)
	if wave >= 20:
		cnt = mini(4 + int(floorf((wave - 20) * 0.3)), 8)
	var used := {}
	var out := []
	var rn := ranged_count(wave, cnt)
	for i in rn:
		_push(out, used, pick_ranged(wave), 7)
	for i in cnt - rn:
		var roll := randf()
		var kind := "normal"
		if wave >= 30 and roll > 0.70:
			kind = "boss"
		elif wave >= 15 and roll > 0.85:
			kind = "boss"
		elif wave >= 10 and roll > 0.75:
			kind = "tank"
		elif wave >= 5 and roll > 0.70:
			kind = "fast"
		var t := _free_tile(used, 1, 20)
		if t.x >= 0:
			out.append({"kind": kind, "tile": t})
	return out

static func gimmick(g: String) -> Array:
	var used := {}
	var out := []
	match g:
		"goblinRaid":
			for i in 2:
				_push(out, used, "slinger", 7)
			for i in 6:
				_push(out, used, "goblin")
		"ninjaRaid":
			_push(out, used, "crossbow", 7)
			for i in 3:
				_push(out, used, "ninja")
		"splitterRaid":
			_push(out, used, "shaman", 7)
			for i in 4:
				_push(out, used, "splitter")
		"sprinterRaid":
			_push(out, used, "slinger", 7)
			for i in 3:
				_push(out, used, "sprinter")
		"giantBoss":
			var t := Vector2i(randi_range(0, 4), 6)
			out.append({"kind": "giant", "tile": t})
		"hydra":
			for t in [Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 6), Vector2i(4, 6)]:
				out.append({"kind": "hydra", "tile": t})
		"illusionist":
			var real := randi() % 5
			for i in 5:
				_push(out, used, "illusionist" if i == real else "illusion")
	return out

static func _push(out: Array, used: Dictionary, kind: String, r_min := 6) -> void:
	var t := _free_tile(used, 1, 50, r_min)
	if t.x >= 0:
		out.append({"kind": kind, "tile": t})

## Tutorial enemies at HTML (1,0),(4,0).
static func tutorial(kind: String) -> Array:
	return [{"kind": kind, "tile": Vector2i(1, 7)}, {"kind": kind, "tile": Vector2i(4, 7)}]
