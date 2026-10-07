class_name Waves
extends RefCounted
## Wave composition (spec §4.3, §4.4). Board rows: HTML y -> r = 7 - y, so the spawn zone is r 6..7.

const GIMMICKS := ["hydra", "illusionist", "goblinRaid", "ninjaRaid", "splitterRaid", "sprinterRaid"]

const GIMMICK_INFO := {
	"hydra": {"title": "히드라 습격!", "hint": "쓰러뜨려도 2초 뒤 부활 — 4마리를 동시에 쓰러뜨리세요"},
	"illusionist": {"title": "환술사 등장!", "hint": "환영 4마리 중 진짜 환술사 1마리를 찾아 처치하세요"},
	"goblinRaid": {"title": "고블린 부대 습격!", "hint": "빠르지만 약한 적 6마리가 몰려옵니다"},
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

static func _free_tile(used: Dictionary, size := 1, tries := 50) -> Vector2i:
	for i in tries:
		var c := randi_range(0, 6 - size)
		var r := randi_range(6, 8 - size)
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

## Normal sub-wave: list of {kind, tile}.
static func normal(wave: int) -> Array:
	var cnt := mini(3 + int(floorf(wave * 0.5)), 10)
	if wave >= 20:
		cnt = mini(4 + int(floorf((wave - 20) * 0.3)), 8)
	var used := {}
	var out := []
	for i in cnt:
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
			for i in 6:
				_push(out, used, "goblin")
		"ninjaRaid":
			for i in 3:
				_push(out, used, "ninja")
		"splitterRaid":
			for i in 4:
				_push(out, used, "splitter")
		"sprinterRaid":
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
				var t := _free_tile(used)
				if t.x >= 0:
					out.append({"kind": "illusionist" if i == real else "illusion", "tile": t})
	return out

static func _push(out: Array, used: Dictionary, kind: String) -> void:
	var t := _free_tile(used)
	if t.x >= 0:
		out.append({"kind": kind, "tile": t})

## Tutorial enemies at HTML (1,0),(4,0).
static func tutorial(kind: String) -> Array:
	return [{"kind": kind, "tile": Vector2i(1, 7)}, {"kind": kind, "tile": Vector2i(4, 7)}]
