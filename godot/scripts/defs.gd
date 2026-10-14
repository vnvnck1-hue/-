class_name Defs
extends RefCounted
## Game data tables ported from the HTML prototype (docs/html_game_spec.md).
## Times are kept in milliseconds exactly as the original; convert at use site.

const TEAM_HERO := 0
const TEAM_ENEMY := 1

const COL_HERO := Color("3fa9f5")
const COL_ENEMY := Color("f0506e")
const COL_GOLD := Color("ffd23f")
const COL_MANA := Color("5fd0ff")
const COL_CRYSTAL := Color("6fa8ff")
const COL_EXP := Color("8fe36a")

const HERO_ORDER := ["warrior", "ranger", "mage"]
const HERO_START := {"warrior": Vector2i(1, 1), "ranger": Vector2i(3, 2), "mage": Vector2i(5, 1)}

## speed = attack interval (ms), move = ms per tile (-> tiles/sec = 1000/move)
const HEROES := {
	"warrior": {"name": "워리어", "hp": 200, "atk": 30, "range": 1, "speed": 1600.0 / 3.0, "move": 400.0,
		"mana_per_attack": 25, "attack": "melee", "impact": 350, "scale": 1.05},
	"ranger": {"name": "레인저", "hp": 120, "atk": 40, "range": 3, "speed": 400.0, "move": 500.0,
		"mana_per_attack": 20, "attack": "arrow", "impact": 200, "scale": 0.98},
	"mage": {"name": "메이지", "hp": 100, "atk": 55, "range": 3, "speed": 600.0, "move": 800.0,
		"mana_per_attack": 15, "attack": "bolt", "impact": 460, "scale": 1.0},
}
const MAX_MANA := 100.0

const ENEMIES := {
	"normal": {"name": "졸개", "hp": 35, "atk": 8, "range": 1, "speed": 1400, "move": 1200, "scale": 0.9},
	"fast": {"name": "날쌘돌이", "hp": 25, "atk": 8, "range": 1, "speed": 1000, "move": 800, "scale": 0.82},
	"tank": {"name": "철갑병", "hp": 80, "atk": 12, "range": 1, "speed": 2000, "move": 1800, "scale": 1.12},
	"boss": {"name": "대장", "hp": 200, "atk": 25, "range": 2, "speed": 1500, "move": 1300, "scale": 1.3},
	"goblin": {"name": "고블린", "hp": 22, "atk": 7, "range": 1, "speed": 850, "move": 520, "scale": 0.78},
	"ninja": {"name": "닌자", "hp": 18, "atk": 13, "range": 1, "speed": 900, "move": 1000, "scale": 0.85},
	"splitter": {"name": "분열체", "hp": 55, "atk": 9, "range": 1, "speed": 1350, "move": 1150, "scale": 1.05},
	"splitling": {"name": "꼬마 분열체", "hp": 12, "atk": 5, "range": 1, "speed": 900, "move": 850, "scale": 0.6},
	"sprinter": {"name": "질주꾼", "hp": 28, "atk": 9, "range": 1, "speed": 900, "move": 760, "scale": 0.85},
	"giant": {"name": "거대 골렘", "hp": 620, "atk": 22, "range": 2, "speed": 2100, "move": 3000, "scale": 2.0,
		"size": 2, "knockback_immune": true},
	"hydra": {"name": "히드라", "hp": 50, "atk": 10, "range": 1, "speed": 1200, "move": 1000, "scale": 1.0},
	"illusionist": {"name": "환술사", "hp": 80, "atk": 12, "range": 1, "speed": 1000, "move": 900, "scale": 0.95},
	"illusion": {"name": "환영", "hp": 40, "atk": 12, "range": 1, "speed": 1000, "move": 900, "scale": 0.95},
	# ranged support (원거리): stay behind the front line and shoot; attack = projectile style (Combat.enemy_attack),
	# kite = back off when a hero gets close, splash = radius (tiles) of the impact blast (50% to others nearby).
	"slinger": {"name": "돌팔매 고블린", "hp": 24, "atk": 7, "range": 3, "speed": 1700, "move": 1100, "scale": 0.8,
		"attack": "rock", "kite": true},
	"crossbow": {"name": "석궁 저격수", "hp": 26, "atk": 15, "range": 4.2, "speed": 2700, "move": 1300, "scale": 0.88,
		"attack": "quarrel", "kite": true},
	"shaman": {"name": "화염 주술사", "hp": 42, "atk": 10, "range": 3.2, "speed": 2300, "move": 1300, "scale": 0.95,
		"attack": "hex", "splash": 1.0},
	"tut_easy": {"name": "허수아비", "hp": 5, "atk": 1, "range": 1, "speed": 2000, "move": 2000, "scale": 0.9, "flat": true},
	"tut_tough": {"name": "튼튼 허수아비", "hp": 280, "atk": 1, "range": 1, "speed": 3200, "move": 3200, "scale": 1.0, "flat": true},
	# --- March field creatures: same numbers as the classic role they stand in for ("role"), new bodies.
	# beasts (동물형)
	"wolf": {"name": "회색 늑대", "role": "normal", "hp": 35, "atk": 8, "range": 1, "speed": 1400, "move": 1200, "scale": 0.92},
	"hornbunny": {"name": "뿔토끼", "role": "fast", "hp": 25, "atk": 8, "range": 1, "speed": 1000, "move": 800, "scale": 0.86},
	"boar": {"name": "쇠엄니 멧돼지", "role": "tank", "hp": 80, "atk": 12, "range": 1, "speed": 2000, "move": 1800, "scale": 1.14},
	"bear": {"name": "우두머리 곰", "role": "boss", "hp": 200, "atk": 25, "range": 2, "speed": 1500, "move": 1300, "scale": 1.3},
	# monsters (괴물형)
	"imp": {"name": "외눈 도깨비", "role": "normal", "hp": 35, "atk": 8, "range": 1, "speed": 1400, "move": 1200, "scale": 0.9},
	"eyebat": {"name": "눈알박쥐", "role": "fast", "hp": 25, "atk": 8, "range": 1, "speed": 1000, "move": 800, "scale": 0.86, "bar_h": 1.25},
	"mimic": {"name": "보물상자 미믹", "role": "tank", "hp": 80, "atk": 12, "range": 1, "speed": 2000, "move": 1800, "scale": 1.12},
	"horror": {"name": "촉수 마물", "role": "boss", "hp": 200, "atk": 25, "range": 2, "speed": 1500, "move": 1300, "scale": 1.28},
	# mid-bosses: giant golem numbers, own silhouette and signature skill (BossSkills)
	"mammoth": {"name": "철갑 전쟁 맘모스", "role": "giant", "hp": 620, "atk": 22, "range": 2, "speed": 2100, "move": 3000, "scale": 2.0,
		"size": 2, "knockback_immune": true, "bar_h": 1.45},
	"abyss": {"name": "심연의 군주", "role": "giant", "hp": 620, "atk": 22, "range": 2, "speed": 2100, "move": 2700, "scale": 2.0,
		"size": 2, "knockback_immune": true, "bar_h": 1.75},
	# region bosses added with the boss raid (BossSkills): one per region theme, also the raid's targets
	"spider": {"name": "독니 거미 여왕", "role": "giant", "hp": 600, "atk": 20, "range": 2, "speed": 1800, "move": 2000, "scale": 2.0,
		"size": 2, "knockback_immune": true, "bar_h": 1.15},
	"warden": {"name": "화염 집행자", "role": "giant", "hp": 680, "atk": 22, "range": 2, "speed": 2300, "move": 3000, "scale": 2.0,
		"size": 2, "knockback_immune": true, "bar_h": 1.85},
	"flytrap": {"name": "세머리 파리지옥", "role": "giant", "hp": 640, "atk": 20, "range": 3.6, "speed": 2400, "move": 99999, "scale": 2.0,
		"size": 2, "knockback_immune": true, "bar_h": 1.6, "attack": "seed", "splash": 0.9, "rooted": true},
	# the murloc trio: three bosses fighting together (the archpriest leads and counts as the giant)
	"murPriest": {"name": "멀록 대사제", "role": "giant", "hp": 240, "atk": 11, "range": 3.4, "speed": 2200, "move": 1500, "scale": 1.45,
		"knockback_immune": true, "bar_h": 1.35, "attack": "bubble", "kite": true, "boss_key": "murlocs"},
	"murWhip": {"name": "멀록 조련사", "role": "boss", "hp": 260, "atk": 12, "range": 1.8, "speed": 1700, "move": 1300, "scale": 1.4,
		"knockback_immune": true, "bar_h": 1.3, "boss_key": "murlocs"},
	"murSpear": {"name": "멀록 작살병", "role": "boss", "hp": 280, "atk": 13, "range": 1.3, "speed": 1500, "move": 1150, "scale": 1.35,
		"knockback_immune": true, "bar_h": 1.2, "boss_key": "murlocs"},
}

## Region bosses and the boss raid's line-up. kinds: who steps out (the murlocs come as three).
const RAID_BOSSES := [
	{"key": "mammoth", "name": "철갑 전쟁 맘모스", "region": 0, "kinds": ["mammoth"], "col": Color("c98a5a")},
	{"key": "flytrap", "name": "세머리 파리지옥", "region": 1, "kinds": ["flytrap"], "col": Color("7cc85a")},
	{"key": "murlocs", "name": "멀록 삼총사", "region": 2, "kinds": ["murPriest", "murWhip", "murSpear"], "col": Color("4fb8c8")},
	{"key": "warden", "name": "화염 집행자", "region": 3, "kinds": ["warden"], "col": Color("ff8a3a")},
	{"key": "spider", "name": "독니 거미 여왕", "region": 4, "kinds": ["spider"], "col": Color("9ad43a")},
	{"key": "abyss", "name": "심연의 군주", "region": 5, "kinds": ["abyss"], "col": Color("c86bff")},
]

static func raid_boss(key: String) -> Dictionary:
	for b in RAID_BOSSES:
		if b["key"] == key:
			return b
	return {}

## The boss line-up of region r: [{kind, pos}] in camp coordinates (the trio stands around x 0, local z 0..4).
static func boss_lineup(key: String) -> Array:
	var b := raid_boss(key)
	if b.is_empty():
		return [{"kind": "giant", "pos": Vector3(0, 0, -4.4)}]
	if key == "murlocs":
		return [{"kind": "murPriest", "pos": Vector3(0, 0, -5.0)}, {"kind": "murWhip", "pos": Vector3(-1.6, 0, -3.8)},
			{"kind": "murSpear", "pos": Vector3(1.6, 0, -3.6)}]
	return [{"kind": b["kinds"][0], "pos": Vector3(0, 0, -4.4)}]

## Region bosses (giant role or the murloc trio) count as the camp's mid-boss.
static func is_region_boss(kind: String) -> bool:
	return is_huge(kind) or ENEMIES.get(kind, {}).has("boss_key")

## Which creature stands in for each classic role, per region roster (Regions.LIST "roster").
const ROSTERS := {
	"beast": {"normal": "wolf", "fast": "hornbunny", "tank": "boar", "boss": "bear", "giant": "mammoth"},
	"monster": {"normal": "imp", "fast": "eyebat", "tank": "mimic", "boss": "horror", "giant": "abyss"},
}

const BOSS_INFO := {
	"giant": {"title": "중간 보스!", "hint": "거대 골렘과 호위병 — 넉백 면역, 매우 높은 체력"},
	"mammoth": {"title": "중간 보스! 철갑 전쟁 맘모스", "hint": "앞발을 들면 피하세요 — 주변을 내리찍는 대지 진동"},
	"abyss": {"title": "중간 보스! 심연의 군주", "hint": "보랏빛 낙인이 찍힌 자리에 심연 폭발이 떨어집니다"},
	"spider": {"title": "중간 보스! 독니 거미 여왕", "hint": "초록 원이 생기면 그 자리로 뛰어듭니다 — 거미줄에 걸리면 느려져요"},
	"warden": {"title": "중간 보스! 화염 집행자", "hint": "망치를 치켜들면 한 줄로 용암이 터집니다 — 옆으로 비키세요"},
	"murlocs": {"title": "중간 보스! 멀록 삼총사", "hint": "대사제의 해일 · 조련사의 갈고리 · 작살병의 돌진 — 셋이 함께 싸워요"},
	"flytrap": {"title": "중간 보스! 세머리 파리지옥", "hint": "가시 씨앗이 떨어진 자리에 독안개가 남아요 — 안개 밖으로!"},
}

## Classic role a kind plays (rewards, drop rates, hit weight).
static func role(kind: String) -> String:
	return ENEMIES.get(kind, {}).get("role", kind)

## Roster creature for a classic kind ("" roster or special kinds pass through).
static func skin(kind: String, roster: String) -> String:
	return ROSTERS.get(roster, {}).get(kind, kind)

## Shoots projectiles instead of swinging (Combat.enemy_attack).
static func is_ranged(kind: String) -> bool:
	return ENEMIES.get(kind, {}).has("attack")

## 2x2 mid-boss bodies.
static func is_huge(kind: String) -> bool:
	return ENEMIES.get(kind, {}).get("size", 1) > 1

const DROP_RATES := {"normal": 0.2, "fast": 0.25, "tank": 0.4, "boss": 0.8, "hydra": 0.3, "illusionist": 0.6, "illusion": 0.15,
	"slinger": 0.22, "crossbow": 0.3, "shaman": 0.35}

static func gold_base(kind: String) -> int:
	match role(kind):
		"boss": return 80
		"tank": return 30
		"illusionist": return 40
		"illusion": return 20
		"crossbow", "shaman": return 20
	return 15

## Enemy hp / atk multiplier of wave (march group) w: one constant growth rate all the way, so every group is
## SCALE_RATE harder than the last (x1.97 per 10-group region, close to the gear ladder's x1.75 + levels and books).
## Was linear to 30 (felt growth fading 15% -> 4.7%) and then x1.15 per group (x4 per region: chapters 4-6 walled).
const SCALE_BASE := 1.2
const SCALE_RATE := 1.07

static func scaling(wave: int) -> float:
	return SCALE_BASE * pow(SCALE_RATE, maxi(1, wave) - 1)

static func sub_wave_count(wave: int) -> int:
	if wave >= 25:
		return 3
	if wave >= 20:
		return 2
	return 1

# ---------------------------------------------------------------- skill books (run growth)
## Skills are found, not trained: skill books drop in battle (and come from chests and the merchant) and are
## read from the bag whenever the player likes. A book is only a grade: reading it flips BOOK_PICKS cards (SkillGacha)
## that each show a random skill of grade <= the book's grade (BOOK_ROLL odds), and the player keeps one.
## A new skill takes one of SKILL_SLOTS slots; a known one goes up one level (max BOOK_MAX). BOOK_MERGE books of one
## grade merge in the bag into one book of the next grade, so saving books trades picks for a higher ceiling.
## Everything learned is lost when the run ends.
## grade: 1 일반 (basic passives) · 2 희귀 (stronger mixes) · 3 영웅 (signature skill upgrades) · 4 전설 (ultimate upgrades).
## fx values are per level. Hero-only keys: activeMult (signature skill damage), activeCount (extra arrows),
## activeStun / activeFreeze (seconds), ultDamageBonus, ultCooldownReduce, ultBounces, bonusHp (flat max HP).
const SKILL_SLOTS := 4
const BOOK_MAX := 5
const BOOK_GRADES := {1: ["일반", "common"], 2: ["희귀", "rare"], 3: ["영웅", "epic"], 4: ["전설", "legendary"]}
const BOOK_TOP := 4
const BOOK_PICKS := 3
const BOOK_MERGE := 3
## Skill-grade odds of one reel per book grade (index 0 = 일반 skill): a book never shows a skill above its grade.
const BOOK_ROLL := {1: [1.0], 2: [0.55, 0.45], 3: [0.3, 0.4, 0.3], 4: [0.1, 0.2, 0.35, 0.35]}
const SKILL_BOOKS := {
	# warrior
	"ironWall": {"cls": "warrior", "grade": 1, "name": "철벽", "desc": "받는 피해 -5%", "fx": {"dmgReduce": 0.05}},
	"counter": {"cls": "warrior", "grade": 1, "name": "반격", "desc": "피격 시 반격 확률 +8%", "fx": {"counterChance": 0.08}},
	"vitality": {"cls": "warrior", "grade": 1, "name": "생명력", "desc": "최대 체력 +30", "fx": {"bonusHp": 30}},
	"berserkerRage": {"cls": "warrior", "grade": 2, "name": "광전사의 분노", "desc": "주는 피해 +8%, 공격 속도 +4%", "fx": {"dmgBonus": 0.08, "atkSpeedBonus": 0.04}},
	"whirlSlash": {"cls": "warrior", "grade": 2, "name": "회전 베기", "desc": "폭발 확률 +8%, 주는 피해 +4%", "fx": {"explosionChance": 0.08, "dmgBonus": 0.04}},
	"ironTaunt": {"cls": "warrior", "grade": 2, "name": "철벽 도발", "desc": "받는 피해 -4%, 반격 확률 +5%", "fx": {"dmgReduce": 0.04, "counterChance": 0.05}},
	"slamMastery": {"cls": "warrior", "grade": 3, "name": "강습 숙련", "desc": "용맹한 강습 피해 +25%, 기절 +0.2초", "fx": {"activeMult": 0.25, "activeStun": 0.2}},
	"warCry": {"cls": "warrior", "grade": 3, "name": "투지", "desc": "마나 획득 +12% (강습을 더 자주)", "fx": {"manaGainMult": 0.12}},
	"earthFury": {"cls": "warrior", "grade": 4, "name": "대지의 분노", "desc": "충격파 피해 +20%, 쿨타임 -6%", "fx": {"ultDamageBonus": 0.20, "ultCooldownReduce": 0.06}},
	# ranger
	"rapidFire": {"cls": "ranger", "grade": 1, "name": "속사", "desc": "공격 속도 +6%", "fx": {"atkSpeedBonus": 0.06}},
	"pierce": {"cls": "ranger", "grade": 1, "name": "관통", "desc": "관통 확률 +8%", "fx": {"pierceChance": 0.08}},
	"critical": {"cls": "ranger", "grade": 1, "name": "치명타", "desc": "치명타 확률 +6%", "fx": {"critChance": 0.06}},
	"sniperMode": {"cls": "ranger", "grade": 2, "name": "저격 모드", "desc": "치명타 +5%, 주는 피해 +6%", "fx": {"critChance": 0.05, "dmgBonus": 0.06}},
	"splitArrow": {"cls": "ranger", "grade": 2, "name": "분열 화살", "desc": "관통 +6%, 폭발 확률 +5%", "fx": {"pierceChance": 0.06, "explosionChance": 0.05}},
	"shadowEvasion": {"cls": "ranger", "grade": 2, "name": "그림자 회피", "desc": "회피 +4%, 공격 속도 +3%", "fx": {"dodgeChance": 0.04, "atkSpeedBonus": 0.03}},
	"volleyMastery": {"cls": "ranger", "grade": 3, "name": "다중 사격 숙련", "desc": "다중 사격 화살 +1발, 피해 +10%", "fx": {"activeCount": 1, "activeMult": 0.10}},
	"hunterFocus": {"cls": "ranger", "grade": 3, "name": "사냥꾼의 집중", "desc": "마나 획득 +12% (다중 사격을 더 자주)", "fx": {"manaGainMult": 0.12}},
	"arrowStorm": {"cls": "ranger", "grade": 4, "name": "화살 폭풍", "desc": "집중 포화 피해 +20%, 쿨타임 -6%", "fx": {"ultDamageBonus": 0.20, "ultCooldownReduce": 0.06}},
	# mage
	"explosion": {"cls": "mage", "grade": 1, "name": "폭발", "desc": "폭발 확률 +8%", "fx": {"explosionChance": 0.08}},
	"freeze": {"cls": "mage", "grade": 1, "name": "빙결", "desc": "빙결 확률 +7%", "fx": {"freezeChance": 0.07}},
	"arcane": {"cls": "mage", "grade": 1, "name": "마력 증폭", "desc": "주는 피해 +7%", "fx": {"dmgBonus": 0.07}},
	"blackHole": {"cls": "mage", "grade": 2, "name": "블랙홀", "desc": "폭발 +6%, 빙결 +3%, 주는 피해 +4%", "fx": {"explosionChance": 0.06, "freezeChance": 0.03, "dmgBonus": 0.04}},
	"overcharge": {"cls": "mage", "grade": 2, "name": "과충전", "desc": "공격 속도 +5%, 주는 피해 +6%", "fx": {"atkSpeedBonus": 0.05, "dmgBonus": 0.06}},
	"absoluteFrost": {"cls": "mage", "grade": 2, "name": "절대 동결", "desc": "빙결 +6%, 받는 피해 -3%", "fx": {"freezeChance": 0.06, "dmgReduce": 0.03}},
	"frostMastery": {"cls": "mage", "grade": 3, "name": "절대 영도 숙련", "desc": "절대 영도 피해 +25%, 빙결 +0.2초", "fx": {"activeMult": 0.25, "activeFreeze": 0.2}},
	"manaFlow": {"cls": "mage", "grade": 3, "name": "마나 순환", "desc": "마나 획득 +12% (절대 영도를 더 자주)", "fx": {"manaGainMult": 0.12}},
	"stormLord": {"cls": "mage", "grade": 4, "name": "번개 군주", "desc": "체인 라이트닝 +1회 튕김, 피해 +15%", "fx": {"ultBounces": 1, "ultDamageBonus": 0.15}},
}

static func book(id: String) -> Dictionary:
	return SKILL_BOOKS.get(id, {})

static func book_grade_name(g: int) -> String:
	return BOOK_GRADES.get(g, ["?", "common"])[0]

static func book_rarity(g: int) -> String:
	return BOOK_GRADES.get(g, ["?", "common"])[1]

static func books_of(cls: String, grade: int) -> Array:
	var out := []
	for id in SKILL_BOOKS:
		if SKILL_BOOKS[id]["cls"] == cls and SKILL_BOOKS[id]["grade"] == grade:
			out.append(id)
	return out

const ACTIVE_SKILLS := {
	"warrior": {"name": "용맹한 강습", "desc": "가장 먼 적에게 도약해 강타하고 주변을 기절시킵니다.",
		"mult": 1.65, "impact_atk": 1.2, "impact_hp": 0.35, "stun": 1050, "guard": 2100},
	"ranger": {"name": "다중 사격", "desc": "뒤로 물러나며 가까운 적 3명에게 강한 화살을 쏩니다.", "mult": 2.5, "count": 3},
	"mage": {"name": "절대 영도", "desc": "모든 적에게 피해를 주고 1초간 얼립니다.", "mult": 1.5, "freeze": 1000},
}

const ULTIMATES := {
	"warrior": {"name": "충격파", "desc": "모든 적에게 큰 피해를 주고 밀어내며 기절시킵니다.", "type": "shockwave",
		"mult": 2.0, "stun": 1000, "cooldown": 8500},
	"ranger": {"name": "집중 포화", "desc": "조준한 방향의 부채꼴에 2초간 화살비를 퍼붓습니다.", "type": "cone",
		"length": 6.4, "angle": PI / 7.0, "tick_mult": 0.6, "tick": 250, "channel": 2000, "cooldown": 7000},
	"mage": {"name": "체인 라이트닝", "desc": "적 사이를 튕기는 번개를 날립니다.", "type": "chain",
		"bounces": 5, "mult": 1.45, "cooldown": 10000},
}

# ---------------------------------------------------------------- items
const ITEM_SELL := {1: 10, 2: 35, 3: 120, 4: 400, 5: 800, 6: 1800, 7: 3200}
const ITEM_BUY := {1: 30, 2: 100, 3: 350, 4: 1000, 5: 2000}
const MAX_INVENTORY := 14
const RARITY := {1: "common", 2: "uncommon", 3: "rare", 4: "legendary", 5: "mythic", 6: "transcendent", 7: "transcendent"}
const RARITY_COL := {"common": Color("c8ccd8"), "uncommon": Color("7ee07a"), "rare": Color("5fb4ff"),
	"epic": Color("b98cff"), "legendary": Color("ffb43c"), "mythic": Color("ff6fd0"), "ancient": Color("3fd8b0"),
	"primal": Color("ffe27a"), "transcendent": Color("ff5f5f")}

const FAMILIES := ["sword", "axe", "bow", "staff", "shield", "helmet", "ring", "amulet"]

## stat keys: atk, hp, critChance, range, atkSpeedBonus, dmgBonus, explosionChance, dmgReduce, counterChance
const ITEMS := {
	"sword1": {"name": "낡은 검", "slot": "weapon", "tier": 1, "stats": {"atk": 5}},
	"sword2": {"name": "강철검", "slot": "weapon", "tier": 2, "stats": {"atk": 12}},
	"sword3": {"name": "미스릴검", "slot": "weapon", "tier": 3, "stats": {"atk": 25}},
	"sword4": {"name": "영웅의 검", "slot": "weapon", "tier": 4, "stats": {"atk": 50, "critChance": 0.15}},
	"axe1": {"name": "손도끼", "slot": "weapon", "tier": 1, "stats": {"atk": 7}},
	"axe2": {"name": "전투도끼", "slot": "weapon", "tier": 2, "stats": {"atk": 15}},
	"axe3": {"name": "처형자의 도끼", "slot": "weapon", "tier": 3, "stats": {"atk": 30, "critChance": 0.10}},
	"axe4": {"name": "심판의 도끼", "slot": "weapon", "tier": 4, "stats": {"atk": 55, "critChance": 0.25}},
	"bow1": {"name": "단궁", "slot": "weapon", "tier": 1, "stats": {"atk": 4, "range": 1}},
	"bow2": {"name": "장궁", "slot": "weapon", "tier": 2, "stats": {"atk": 10, "range": 1}},
	"bow3": {"name": "정밀 석궁", "slot": "weapon", "tier": 3, "stats": {"atk": 20, "range": 2}},
	"bow4": {"name": "바람의 활", "slot": "weapon", "tier": 4, "stats": {"atk": 35, "range": 2, "atkSpeedBonus": 0.20}},
	"staff1": {"name": "나무 지팡이", "slot": "weapon", "tier": 1, "stats": {"atk": 3, "dmgBonus": 0.05}},
	"staff2": {"name": "마법 지팡이", "slot": "weapon", "tier": 2, "stats": {"atk": 8, "dmgBonus": 0.12}},
	"staff3": {"name": "대마법사의 지팡이", "slot": "weapon", "tier": 3, "stats": {"atk": 15, "dmgBonus": 0.25}},
	"staff4": {"name": "아크메이지 스태프", "slot": "weapon", "tier": 4, "stats": {"atk": 25, "dmgBonus": 0.40, "explosionChance": 0.20}},
	"shield1": {"name": "나무 방패", "slot": "armor", "tier": 1, "stats": {"hp": 15, "dmgReduce": 0.05}},
	"shield2": {"name": "철 방패", "slot": "armor", "tier": 2, "stats": {"hp": 35, "dmgReduce": 0.10}},
	"shield3": {"name": "수호자의 방패", "slot": "armor", "tier": 3, "stats": {"hp": 60, "dmgReduce": 0.18}},
	"shield4": {"name": "불멸의 방패", "slot": "armor", "tier": 4, "stats": {"hp": 100, "dmgReduce": 0.30, "counterChance": 0.20}},
	"helmet1": {"name": "가죽 모자", "slot": "armor", "tier": 1, "stats": {"hp": 10}},
	"helmet2": {"name": "철 투구", "slot": "armor", "tier": 2, "stats": {"hp": 25}},
	"helmet3": {"name": "강철 투구", "slot": "armor", "tier": 3, "stats": {"hp": 50, "dmgReduce": 0.08}},
	"helmet4": {"name": "용의 투구", "slot": "armor", "tier": 4, "stats": {"hp": 80, "dmgReduce": 0.15, "atk": 15}},
	"ring1": {"name": "구리 반지", "slot": "accessory", "tier": 1, "stats": {"atkSpeedBonus": 0.08}},
	"ring2": {"name": "은 반지", "slot": "accessory", "tier": 2, "stats": {"atkSpeedBonus": 0.15}},
	"ring3": {"name": "민첩의 반지", "slot": "accessory", "tier": 3, "stats": {"atkSpeedBonus": 0.25, "atk": 8}},
	"ring4": {"name": "폭풍의 반지", "slot": "accessory", "tier": 4, "stats": {"atkSpeedBonus": 0.40, "atk": 20, "critChance": 0.10}},
	"amulet1": {"name": "나무 목걸이", "slot": "accessory", "tier": 1, "stats": {"hp": 12}},
	"amulet2": {"name": "은 목걸이", "slot": "accessory", "tier": 2, "stats": {"hp": 30}},
	"amulet3": {"name": "생명의 목걸이", "slot": "accessory", "tier": 3, "stats": {"hp": 55, "dmgReduce": 0.08}},
	"amulet4": {"name": "불사의 목걸이", "slot": "accessory", "tier": 4, "stats": {"hp": 90, "dmgReduce": 0.15, "atk": 10}},
}

## effects: sharedMana, killMana, knockback, swap, lightning
const LEGENDARY := {
	"resonanceOrb": {"name": "공명의 오브", "slot": "accessory", "tier": 5, "stats": {"hp": 30}, "effects": ["sharedMana"]},
	"soulReaper": {"name": "영혼 착취자", "slot": "weapon", "tier": 5, "stats": {"atk": 35}, "effects": ["killMana"]},
	"stormFist": {"name": "폭풍의 주먹", "slot": "weapon", "tier": 5, "stats": {"atk": 30}, "effects": ["knockback"]},
	"dimensionMirror": {"name": "차원의 거울", "slot": "accessory", "tier": 5, "stats": {"hp": 20, "atkSpeedBonus": 0.15}, "effects": ["swap"]},
	"thunderHeart": {"name": "천둥의 심장", "slot": "accessory", "tier": 5, "stats": {"atk": 15, "critChance": 0.10}, "effects": ["lightning"]},
	"eclipseBlade": {"name": "일식검", "slot": "weapon", "tier": 6, "ultra": true, "price": 5200, "stats": {"atk": 90, "critChance": 0.35, "dmgBonus": 0.25}, "effects": ["lightning", "killMana"]},
	"worldTreeSeed": {"name": "세계수의 씨앗", "slot": "accessory", "tier": 6, "ultra": true, "price": 5400, "stats": {"hp": 280, "dmgReduce": 0.28, "atkSpeedBonus": 0.25}, "effects": ["sharedMana"]},
	"voidAnchor": {"name": "공허의 닻", "slot": "armor", "tier": 6, "ultra": true, "price": 5600, "stats": {"hp": 360, "atk": 35, "dmgReduce": 0.42}, "effects": ["knockback"]},
	"chronosHourglass": {"name": "크로노스의 모래시계", "slot": "accessory", "tier": 6, "ultra": true, "price": 5800, "stats": {"atkSpeedBonus": 0.60, "hp": 160, "critChance": 0.25}, "effects": ["sharedMana", "lightning"]},
	"royalDecree": {"name": "왕의 칙령", "slot": "accessory", "tier": 6, "ultra": true, "price": 6000, "stats": {"atk": 100, "hp": 260, "dmgReduce": 0.30, "critChance": 0.30}, "effects": ["killMana", "sharedMana"]},
}

const TRANSCENDENT := {
	"ascendedResonanceOrb": {"from": "resonanceOrb", "name": "초월한 공명의 오브", "slot": "accessory", "tier": 6, "stats": {"hp": 140, "atkSpeedBonus": 0.35}, "effects": ["sharedMana", "lightning"]},
	"ascendedSoulReaper": {"from": "soulReaper", "name": "초월한 영혼 착취자", "slot": "weapon", "tier": 6, "stats": {"atk": 105, "critChance": 0.25}, "effects": ["killMana", "lightning"]},
	"ascendedStormFist": {"from": "stormFist", "name": "초월한 폭풍의 주먹", "slot": "weapon", "tier": 6, "stats": {"atk": 95, "dmgBonus": 0.35, "hp": 80}, "effects": ["knockback", "lightning"]},
	"ascendedDimensionMirror": {"from": "dimensionMirror", "name": "초월한 차원의 거울", "slot": "accessory", "tier": 6, "stats": {"hp": 120, "atkSpeedBonus": 0.45, "dmgReduce": 0.18}, "effects": ["swap", "sharedMana"]},
	"ascendedThunderHeart": {"from": "thunderHeart", "name": "초월한 천둥의 심장", "slot": "accessory", "tier": 6, "stats": {"atk": 75, "critChance": 0.35, "atkSpeedBonus": 0.35}, "effects": ["lightning", "killMana"]},
	"ascendedCrown": {"from": "crown", "name": "초월한 왕관", "slot": "accessory", "tier": 6, "stats": {"atk": 140, "hp": 380, "atkSpeedBonus": 0.55, "critChance": 0.40, "dmgReduce": 0.35}, "effects": ["sharedMana", "killMana"]},
	"ascendedEclipseBlade": {"from": "eclipseBlade", "name": "초월한 일식검", "slot": "weapon", "tier": 7, "stats": {"atk": 180, "critChance": 0.50, "dmgBonus": 0.45}, "effects": ["lightning", "killMana"]},
	"ascendedWorldTreeSeed": {"from": "worldTreeSeed", "name": "초월한 세계수의 씨앗", "slot": "accessory", "tier": 7, "stats": {"hp": 520, "dmgReduce": 0.45, "atkSpeedBonus": 0.35}, "effects": ["sharedMana", "lightning"]},
	"ascendedVoidAnchor": {"from": "voidAnchor", "name": "초월한 공허의 닻", "slot": "armor", "tier": 7, "stats": {"hp": 680, "atk": 70, "dmgReduce": 0.55}, "effects": ["knockback", "sharedMana"]},
	"ascendedChronosHourglass": {"from": "chronosHourglass", "name": "초월한 크로노스의 모래시계", "slot": "accessory", "tier": 7, "stats": {"atkSpeedBonus": 0.85, "hp": 280, "critChance": 0.42, "atk": 60}, "effects": ["sharedMana", "lightning", "killMana"]},
	"ascendedRoyalDecree": {"from": "royalDecree", "name": "초월한 왕의 칙령", "slot": "accessory", "tier": 7, "stats": {"atk": 220, "hp": 520, "dmgReduce": 0.45, "critChance": 0.45, "atkSpeedBonus": 0.35}, "effects": ["killMana", "sharedMana", "lightning"]},
}

const RELICS := {
	"vampireChalice": {"name": "핏빛 성배", "rarity": "legendary", "price": 3600, "fx": {"lifeSteal": 0.20}, "desc": "가한 피해의 20%만큼 회복"},
	"crescendoGear": {"name": "가속의 태엽심장", "rarity": "legendary", "price": 3800, "fx": {"atkSpeedBonus": 0.10}, "tempo": true, "desc": "공속 +10%, 공격할수록 최대 +30% 가속"},
	"windPilgrimBoots": {"name": "바람 순례자의 장화", "rarity": "legendary", "price": 3400, "fx": {"moveSpeedBonus": 0.50}, "desc": "이동 속도 +50%"},
	"echoCrystal": {"name": "메아리 결정핵", "rarity": "legendary", "price": 3900, "fx": {"doubleAttackChance": 0.10}, "desc": "10% 확률로 추가 공격"},
	"moonlitPendant": {"name": "달빛 펜던트", "rarity": "rare", "price": 1200, "fx": {"manaGainMult": 0.20}, "desc": "마나 획득 +20%"},
	"guardianIdol": {"name": "수호자의 작은 우상", "rarity": "rare", "price": 1100, "fx": {"dmgReduce": 0.08}, "desc": "받는 피해 -8%"},
	"luckyCompass": {"name": "행운의 나침반", "rarity": "rare", "price": 1300, "fx": {"dropBonus": 0.10, "goldMult": 0.10}, "desc": "드랍률 +10%, 골드 +10%"},
}

## Relics are permanent (Meta): kept in the lobby [유물] collection, RELIC_SLOTS of them are worn there and
## apply to the whole party in every run. Three of the same relic at the same ★ merge into the next ★
## (up to RELIC_MAX_STAR); each ★ above 1 adds RELIC_STAR_STEP of the base effect.
const RELIC_SLOTS := 3
const RELIC_MAX_STAR := 5
const RELIC_STAR_STEP := 0.25   # ★5 = x2.0 of the base effect (was 0.4 -> x2.6)
## fx key -> [label, is percent, sign]
const RELIC_FX_NAME := {
	"lifeSteal": ["가한 피해 흡혈", true, "+"], "atkSpeedBonus": ["공격 속도", true, "+"], "moveSpeedBonus": ["이동 속도", true, "+"],
	"doubleAttackChance": ["추가 공격 확률", true, "+"], "manaGainMult": ["마나 획득", true, "+"], "dmgReduce": ["받는 피해", true, "-"],
	"dropBonus": ["드랍률", true, "+"], "goldMult": ["골드", true, "+"]}

static func relic_mult(star: int) -> float:
	return 1.0 + RELIC_STAR_STEP * float(clampi(star, 1, RELIC_MAX_STAR) - 1)

## The relic's effect at ★ `star`.
static func relic_fx(key: String, star: int) -> Dictionary:
	var out := {}
	var fx: Dictionary = RELICS[key]["fx"]
	for k in fx:
		out[k] = fx[k] * relic_mult(star)
	return out

## crescendoGear: the extra attack speed it builds up as the party attacks (cap) at ★ `star`.
static func relic_tempo_cap(star: int) -> float:
	return 0.30 * relic_mult(star)

## One-line effect text at ★ `star` (numbers scaled), e.g. "공격 속도 +14% · 공격할수록 최대 +42% 가속".
static func relic_desc(key: String, star: int) -> String:
	var parts := []
	var fx := relic_fx(key, star)
	for k in fx:
		var n: Array = RELIC_FX_NAME.get(k, [k, true, "+"])
		parts.append("%s %s%d%%" % [n[0], n[2], roundi(fx[k] * 100.0)])
	if RELICS[key].get("tempo", false):
		parts.append("공격할수록 최대 +%d%% 가속" % roundi(relic_tempo_cap(star) * 100.0))
	return " · ".join(parts)

const SPECIAL := {
	"revive": {"name": "부활의 깃털", "price": 500, "desc": "쓰러진 동료 1명을 체력 100%로 부활"},
	"fullHeal": {"name": "여신의 축복", "price": 300, "desc": "모든 아군 체력 100% 회복"},
	"massKill": {"name": "심판의 번개", "price": 800, "desc": "전투 중 모든 적을 즉시 제거"},
	"inventoryExpand": {"name": "공간 확장 키트", "price": 900, "desc": "인벤토리 칸 +3"},
	"crown": {"name": "전설의 왕관", "price": 1500, "equip": true, "slot": "accessory", "tier": 5,
		"stats": {"atk": 50, "hp": 150, "atkSpeedBonus": 0.30, "critChance": 0.20, "dmgReduce": 0.20}},
}

## Returns a unified item definition for an equipment key (normal / legendary / transcendent / crown).
static func item(key: String) -> Dictionary:
	if ITEMS.has(key):
		return ITEMS[key]
	var gd := Gear.def(key)   # family gear of grade 5+ (전설 ~ 초월★)
	if not gd.is_empty():
		return gd
	if LEGENDARY.has(key):
		return LEGENDARY[key]
	if TRANSCENDENT.has(key):
		return TRANSCENDENT[key]
	if SPECIAL.has(key) and SPECIAL[key].get("equip", false):
		return SPECIAL[key]
	return {}

static func transcendent_of(key: String) -> String:
	for k in TRANSCENDENT:
		if TRANSCENDENT[k]["from"] == key:
			return k
	return ""

# ---------------------------------------------------------------- perks (run)
const PERKS := {
	"atkAll": {"name": "전투 훈련", "rarity": "common", "fx": {"atkMult": 0.12}, "desc": "공격력 +12%"},
	"hpAll": {"name": "강인함", "rarity": "common", "fx": {"hpMult": 0.16}, "desc": "최대 체력 +16%"},
	"speedAll": {"name": "신속 훈련", "rarity": "common", "fx": {"atkSpeedBonus": 0.12}, "desc": "공격 속도 +12%"},
	"critAll": {"name": "약점 포착", "rarity": "common", "fx": {"critChance": 0.08}, "desc": "치명타 확률 +8%"},
	"dmgReduce": {"name": "기초 방어술", "rarity": "common", "fx": {"dmgReduce": 0.08}, "desc": "받는 피해 -8%"},
	"expBonus": {"name": "전투 기록", "rarity": "common", "fx": {"expMult": 0.25}, "desc": "경험치 +25%"},
	"goldBonus": {"name": "잔돈 회수", "rarity": "common", "fx": {"goldMult": 0.20}, "desc": "골드 +20%"},
	"dropRate": {"name": "작은 행운", "rarity": "common", "fx": {"dropBonus": 0.10}, "desc": "아이템 드랍률 +10%"},
	"lifeSteal": {"name": "응급 흡혈", "rarity": "common", "fx": {"lifeSteal": 0.07}, "desc": "가한 피해의 7% 회복"},
	"rangeAll": {"name": "시야 확보", "rarity": "common", "fx": {"range": 1}, "desc": "사거리 +1"},
	"rareBattleRhythm": {"name": "전투 리듬", "rarity": "rare", "fx": {"atkMult": 0.18, "atkSpeedBonus": 0.10}, "desc": "공격력 +18%, 공속 +10%"},
	"rareGuardianFormation": {"name": "수호 진형", "rarity": "rare", "fx": {"hpMult": 0.25, "dmgReduce": 0.08}, "desc": "체력 +25%, 받는 피해 -8%"},
	"rareExplosiveArms": {"name": "폭발 장비", "rarity": "rare", "fx": {"splashChance": 0.20}, "desc": "20% 확률로 주변 폭발"},
	"rareTreasureHunter": {"name": "보물 사냥꾼", "rarity": "rare", "fx": {"goldMult": 0.25, "dropBonus": 0.12}, "desc": "골드 +25%, 드랍률 +12%"},
	"rareUltMaster": {"name": "궁극기 숙련", "rarity": "rare", "fx": {"ultCooldownReduce": 0.18, "critChance": 0.06}, "desc": "궁 쿨타임 -18%, 치명 +6%"},
	"legendDragonSoul": {"name": "용의 심장", "rarity": "legendary", "fx": {"atkMult": 0.30, "hpMult": 0.30, "dmgReduce": 0.10}, "desc": "공격력·체력 +30%, 받는 피해 -10%"},
	"legendStormArmy": {"name": "폭풍 군단", "rarity": "legendary", "fx": {"atkSpeedBonus": 0.30, "critChance": 0.18, "ultCooldownReduce": 0.20}, "desc": "공속 +30%, 치명 +18%, 궁 쿨 -20%"},
	"legendGoldenFate": {"name": "황금 운명", "rarity": "legendary", "fx": {"goldMult": 0.50, "dropBonus": 0.25, "expMult": 0.30}, "desc": "골드 +50%, 드랍 +25%, 경험치 +30%"},
}

# ---------------------------------------------------------------- permanent talent tree
## fx: per-level values. "cls" scopes it to a hero class. "flag" is boolean.
const TALENTS := [
	{"id": "root", "branch": "core", "name": "시간의 뿌리", "max": 1, "costs": [0], "req": [], "pos": Vector2(450, 315), "desc": "모든 특성의 시작점"},
	{"id": "startGold", "branch": "core", "name": "시간의 축복", "max": 5, "costs": [2, 3, 5, 8, 12], "req": ["root"], "pos": Vector2(450, 230), "fx": {"startGold": 50}, "desc": "시작 골드 +50"},
	{"id": "allAtk", "branch": "core", "name": "반복 전투술", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["root"], "pos": Vector2(360, 280), "fx": {"atkMult": 0.02}, "desc": "모든 영웅 공격력 +2%"},
	{"id": "allHp", "branch": "core", "name": "생존 기억", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["root"], "pos": Vector2(540, 280), "fx": {"hpMult": 0.02}, "desc": "모든 영웅 체력 +2% (다음 런부터)"},
	{"id": "waveHeal", "branch": "core", "name": "빠른 정비", "max": 5, "costs": [3, 5, 8, 12, 16], "req": ["root"], "pos": Vector2(450, 395), "fx": {"waveHealBonus": 10}, "desc": "웨이브 종료 회복 +10"},
	{"id": "crystalSense", "branch": "core", "name": "결정 감응", "max": 5, "costs": [5, 8, 12, 18, 25], "req": ["startGold"], "pos": Vector2(450, 145), "fx": {"crystalDropBonus": 0.005}, "desc": "결정 드랍 확률 +0.5%"},
	{"id": "itemSense", "branch": "core", "name": "장비 감별", "max": 5, "costs": [4, 7, 11, 16, 22], "req": ["allAtk"], "pos": Vector2(295, 230), "fx": {"dropBonus": 0.01}, "desc": "아이템 드랍률 +1%"},
	{"id": "battleRecord", "branch": "core", "name": "전투 기록", "max": 5, "costs": [3, 5, 8, 12, 16], "req": ["allHp"], "pos": Vector2(605, 230), "fx": {"expMult": 0.03}, "desc": "경험치 +3%"},
	{"id": "emergencySupply", "branch": "core", "name": "비상 보급", "max": 1, "costs": [15], "req": ["waveHeal"], "pos": Vector2(360, 395), "flag": true, "desc": "런 시작 시 일반 스킬북 1권"},
	{"id": "secondChance", "branch": "core", "name": "두 번째 기회", "max": 1, "costs": [30], "req": ["waveHeal"], "pos": Vector2(540, 395), "flag": true, "desc": "런 중 첫 사망 영웅 1회 30% 부활"},
	{"id": "timeCore", "branch": "core", "name": "시간의 핵", "max": 1, "costs": [40], "req": ["crystalSense"], "pos": Vector2(450, 60), "flag": true, "desc": "직업 최종 특성의 열쇠"},
	{"id": "warAtk", "branch": "warrior", "name": "붉은 단련", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["root"], "pos": Vector2(585, 350), "cls": "warrior", "fx": {"atkMult": 0.03}, "desc": "워리어 공격력 +3%"},
	{"id": "warHp", "branch": "warrior", "name": "강철 체력", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["warAtk"], "pos": Vector2(660, 405), "cls": "warrior", "fx": {"hpMult": 0.04}, "desc": "워리어 체력 +4% (다음 런부터)"},
	{"id": "warReduce", "branch": "warrior", "name": "방패 숙련", "max": 5, "costs": [3, 5, 8, 12, 16], "req": ["warHp"], "pos": Vector2(735, 460), "cls": "warrior", "fx": {"dmgReduce": 0.02}, "desc": "워리어 받는 피해 -2%"},
	{"id": "warCounter", "branch": "warrior", "name": "반격 자세", "max": 5, "costs": [4, 7, 11, 16, 22], "req": ["warReduce"], "pos": Vector2(675, 515), "cls": "warrior", "fx": {"counterChance": 0.04}, "desc": "워리어 반격 확률 +4%"},
	{"id": "warUlt", "branch": "warrior", "name": "충격파 강화", "max": 3, "costs": [8, 15, 25], "req": ["warReduce"], "pos": Vector2(800, 555), "cls": "warrior", "fx": {"ultDamageBonus": 0.10}, "desc": "충격파 피해 +10%"},
	{"id": "warTaunt", "branch": "warrior", "name": "도발의 함성", "max": 1, "costs": [18], "req": ["warHp"], "pos": Vector2(775, 385), "flag": true, "desc": "워리어 생존 시 모든 아군 받는 피해 -3%"},
	{"id": "warLastStand", "branch": "warrior", "name": "불굴", "max": 1, "costs": [25], "req": ["warTaunt"], "pos": Vector2(835, 465), "flag": true, "desc": "워리어 체력 30% 이하일 때 피해 -15%"},
	{"id": "warFinal", "branch": "warrior", "name": "영원의 방패", "max": 1, "costs": [50], "req": ["timeCore", "warLastStand"], "pos": Vector2(840, 300), "flag": true, "desc": "워리어 사망 시 1회 50% 부활"},
	{"id": "rngAtk", "branch": "ranger", "name": "초록 단련", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["root"], "pos": Vector2(315, 350), "cls": "ranger", "fx": {"atkMult": 0.03}, "desc": "레인저 공격력 +3%"},
	{"id": "rngSpeed", "branch": "ranger", "name": "빠른 손놀림", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["rngAtk"], "pos": Vector2(240, 405), "cls": "ranger", "fx": {"atkSpeedBonus": 0.03}, "desc": "레인저 공속 +3%"},
	{"id": "rngCrit", "branch": "ranger", "name": "명중 훈련", "max": 5, "costs": [3, 5, 8, 12, 16], "req": ["rngSpeed"], "pos": Vector2(165, 460), "cls": "ranger", "fx": {"critChance": 0.02}, "desc": "레인저 치명타 +2%"},
	{"id": "rngRange", "branch": "ranger", "name": "긴 사거리", "max": 1, "costs": [18], "req": ["rngCrit"], "pos": Vector2(225, 515), "cls": "ranger", "fx": {"range": 1}, "desc": "레인저 사거리 +1"},
	{"id": "rngBoss", "branch": "ranger", "name": "약점 추적", "max": 3, "costs": [7, 14, 24], "req": ["rngCrit"], "pos": Vector2(100, 555), "cls": "ranger", "fx": {"bossDmgBonus": 0.05}, "desc": "레인저 보스·정예 피해 +5%"},
	{"id": "rngGold", "branch": "ranger", "name": "화살 회수", "max": 5, "costs": [4, 7, 11, 16, 22], "req": ["rngSpeed"], "pos": Vector2(125, 385), "cls": "ranger", "fx": {"rangerGoldBonus": 0.02}, "desc": "레인저 처치 시 추가 골드"},
	{"id": "rngLoot", "branch": "ranger", "name": "전리품 감각", "max": 1, "costs": [35], "req": ["rngGold"], "pos": Vector2(65, 465), "fx": {"dropBonus": 0.05}, "desc": "아이템 드랍률 +5%"},
	{"id": "rngFinal", "branch": "ranger", "name": "시간 사냥꾼", "max": 1, "costs": [50], "req": ["timeCore", "rngLoot"], "pos": Vector2(60, 300), "fx": {"crystalDropBonus": 0.02}, "desc": "결정 드랍 확률 +2%"},
	{"id": "magAtk", "branch": "mage", "name": "보라 단련", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["root"], "pos": Vector2(450, 500), "cls": "mage", "fx": {"atkMult": 0.03}, "desc": "메이지 공격력 +3%"},
	{"id": "magMana", "branch": "mage", "name": "마나 순환", "max": 5, "costs": [2, 4, 6, 9, 13], "req": ["magAtk"], "pos": Vector2(370, 560), "cls": "mage", "fx": {"manaGainMult": 0.03}, "desc": "메이지 마나 획득 +3%"},
	{"id": "magSpeed", "branch": "mage", "name": "주문 가속", "max": 5, "costs": [3, 5, 8, 12, 16], "req": ["magAtk"], "pos": Vector2(530, 560), "cls": "mage", "fx": {"atkSpeedBonus": 0.02}, "desc": "메이지 공속 +2%"},
	{"id": "magFrost", "branch": "mage", "name": "냉기 숙련", "max": 3, "costs": [5, 10, 18], "req": ["magMana"], "pos": Vector2(285, 620), "cls": "mage", "fx": {"freezeChance": 0.05}, "desc": "메이지 빙결 확률 +5%"},
	{"id": "magChain", "branch": "mage", "name": "연쇄 전류", "max": 3, "costs": [10, 18, 30], "req": ["magSpeed"], "pos": Vector2(615, 620), "cls": "mage", "fx": {"mageUltBounces": 1}, "desc": "체인 라이트닝 튕김 +1"},
	{"id": "magUltCool", "branch": "mage", "name": "폭풍의 눈", "max": 1, "costs": [40], "req": ["magFrost", "magChain"], "pos": Vector2(450, 675), "cls": "mage", "fx": {"ultCooldownReduce": 0.20}, "desc": "체인 라이트닝 쿨타임 -20%"},
	{"id": "magFinal", "branch": "mage", "name": "시간 마도사", "max": 1, "costs": [55], "req": ["timeCore", "magUltCool"], "pos": Vector2(450, 745), "flag": true, "desc": "궁 사용 시 10% 확률로 결정 +1"},
]
const TALENT_BRANCH := {"core": {"name": "시간", "col": Color("6fa8ff")}, "warrior": {"name": "워리어", "col": Color("ff7a5a")},
	"ranger": {"name": "레인저", "col": Color("6fdc6a")}, "mage": {"name": "메이지", "col": Color("b07aff")}}

static func talent(id: String) -> Dictionary:
	for t in TALENTS:
		if t["id"] == id:
			return t
	return {}
