class_name Gear
extends RefCounted
## Equipment grade ladder + stage drop design (merge economy). Design doc: docs/gear_merge_design.md
##
## Family gear (sword/axe/bow/staff/shield/helmet/ring/amulet) climbs an open-ended grade ladder:
##   1 일반 · 2 고급 · 3 희귀 · 4 영웅 · 5 전설 · 6 신화 · 7 고대 · 8 태초 · 9+ 초월 ★1, ★2, ... (endless)
## Grades 1-4 are the hand-written Defs.ITEMS; 5+ are generated here from the grade-4 item
## (flat stats x GROWTH per grade, percentage stats +small step with caps), so any 3 of a group always merge up.
## Merging is by slot + grade (see group()), not by exact item: 3 weapons of one grade -> 1 weapon one grade up.
##
## Drop window: encounter group k sits in region r = (k-1)/10 (laps keep counting), whose base grade is B = r + 1.
## Drops roll a grade offset from B; early in a region most drops are B-1 (merge fodder), by the mid-boss
## more are B and B+1 — so each region turns the previous base grade into the next one by merging, and the
## next region starts exactly where the merges left off. B-2 keeps trickling so leftovers still complete.

const GROWTH := 1.75          # flat stat (atk / hp) multiplier per grade above 4
const STAR_FROM := 8          # grade 9 = 초월 ★1
const NAMES := {1: "일반", 2: "고급", 3: "희귀", 4: "영웅", 5: "전설", 6: "신화", 7: "고대", 8: "태초"}
const RARITY := {1: "common", 2: "uncommon", 3: "rare", 4: "epic", 5: "legendary", 6: "mythic", 7: "ancient", 8: "primal"}

## Percentage stats: per-grade step above grade 4, and the cap a single item may reach.
const PCT_STEP := {"critChance": [0.02, 0.45], "dmgReduce": [0.015, 0.42], "atkSpeedBonus": [0.025, 0.6],
	"dmgBonus": [0.06, 1.6], "explosionChance": [0.02, 0.4], "counterChance": [0.02, 0.4]}

const HIGH_NAMES := {
	"sword": ["용살자의 대검", "성광의 검", "고대 왕의 검", "태초의 검"],
	"axe": ["화산 파쇄 도끼", "천둥 군주의 도끼", "거인족의 대도끼", "태초의 도끼"],
	"bow": ["매의 눈 장궁", "별빛 사냥활", "고대 정령의 활", "태초의 활"],
	"staff": ["용암 마력봉", "별의 홀", "고대 현자의 지팡이", "태초의 지팡이"],
	"shield": ["용비늘 방패", "성역의 방패", "고대 성벽 방패", "태초의 방패"],
	"helmet": ["그리폰 투구", "신화의 투구", "고대 왕관 투구", "태초의 투구"],
	"ring": ["질풍의 반지", "성운의 반지", "고대 시간의 반지", "태초의 반지"],
	"amulet": ["불사조 목걸이", "달의 눈물", "고대 심장석", "태초의 목걸이"],
}

## Drop window: weight of each grade offset from the region's base grade, at the region's first group
## (p = 0) and at its mid-boss (p = 1); linearly blended in between.
const WINDOW := {-2: [0.10, 0.06], -1: [0.50, 0.30], 0: [0.36, 0.48], 1: [0.04, 0.16]}
## Mid-boss / boss-role enemies roll one grade higher (their drop is the region's jackpot).
const BOSS_SHIFT := 1
## Chance that an equipment drop is the third copy of a pair the player already holds (merge assist).
const ASSIST := 0.22
const ASSIST_MERCHANT := 1.0   # the merchant always brings one "third copy" if a pair exists
## Each region's featured families drop this many times more often (Regions.LIST "gear").
const FEATURED_W := 3.5
## Extra gear drop chance per kill in the first regions (few enemies per group there), by region index.
const EARLY_DROP := [0.35, 0.18, 0.10]

# ---------------------------------------------------------------- item definitions
static var _cache := {}

static func family_of(key: String) -> String:
	for f in Defs.FAMILIES:
		if key.begins_with(f) and key.substr(f.length()).is_valid_int():
			return f
	return ""

static func grade_of_key(key: String) -> int:
	var f := family_of(key)
	return int(key.substr(f.length())) if f != "" else 0

static func is_family(key: String) -> bool:
	var g := grade_of_key(key)
	return g >= 1

static func key(fam: String, grade: int) -> String:
	return "%s%d" % [fam, maxi(1, grade)]

## Merge groups: family gear merges by slot + grade (weapon: sword/axe/bow/staff, armor: shield/helmet,
## accessory: ring/amulet). Three of one group -> one item of the next grade whose family is picked at
## random among the three materials. Group key format: "weapon#3".
static func slot_of_family(fam: String) -> String:
	return Defs.ITEMS[fam + "1"]["slot"]

static func families_in(slot: String) -> Array:
	return Defs.FAMILIES.filter(func(f): return slot_of_family(f) == slot)

static func group(slot: String, grade: int) -> String:
	return "%s#%d" % [slot, grade]

static func group_of(k: String) -> String:
	return group(slot_of_family(family_of(k)), grade_of_key(k))

static func is_group(g: String) -> bool:
	return g.contains("#")

static func group_slot(g: String) -> String:
	return g.get_slice("#", 0)

static func group_grade(g: String) -> int:
	return int(g.get_slice("#", 1))

static func rarity(grade: int) -> String:
	return RARITY.get(grade, "transcendent") if grade <= STAR_FROM else "transcendent"

static func grade_name(grade: int) -> String:
	if grade > STAR_FROM:
		return "초월 ★%d" % (grade - STAR_FROM)
	return NAMES.get(grade, "?")

## Definition for a generated family item (grade >= 5). Grades 1-4 live in Defs.ITEMS.
static func def(k: String) -> Dictionary:
	if _cache.has(k):
		return _cache[k]
	var f := family_of(k)
	var g := grade_of_key(k)
	if f == "" or g < 5:
		return {}
	var base: Dictionary = Defs.ITEMS[f + "4"]
	var up := g - 4
	var stats := {}
	for s in base["stats"]:
		var v: float = base["stats"][s]
		if PCT_STEP.has(s):
			stats[s] = minf(PCT_STEP[s][1], snappedf(v + PCT_STEP[s][0] * up, 0.01))
		elif s == "range":
			stats[s] = v
		else:
			stats[s] = _nice(v * pow(GROWTH, up))
	var nm: String = HIGH_NAMES[f][mini(g, STAR_FROM) - 5]
	if g > STAR_FROM:
		nm = "%s ★%d" % [nm, g - STAR_FROM]
	var d := {"name": nm, "slot": base["slot"], "tier": g, "stats": stats}
	_cache[k] = d
	return d

static func _nice(v: float) -> int:
	if v < 100.0:
		return int(roundf(v))
	if v < 1000.0:
		return int(roundf(v / 5.0) * 5.0)
	return int(roundf(v / 10.0) * 10.0)

## Shop prices for family gear (grades 1-4 keep the original table).
static func buy_price(grade: int) -> int:
	if Defs.ITEM_BUY.has(grade) and grade <= 4:
		return Defs.ITEM_BUY[grade]
	return int(roundf(2000.0 * pow(1.45, grade - 5) / 50.0) * 50.0)

static func sell_price(grade: int) -> int:
	if grade <= 4:
		return Defs.ITEM_SELL.get(grade, 10)
	return int(roundf(buy_price(grade) * 0.3 / 10.0) * 10.0)

# ---------------------------------------------------------------- stage design
static func region_of(k: int) -> int:
	return Regions.of_group(maxi(1, k))

## Base grade of encounter group k (1 for the first region, +1 per region, laps continue climbing).
static func base_grade(k: int) -> int:
	return region_of(k) + 1

## 0 at a region's first group .. 1 at its mid-boss.
static func progress(k: int) -> float:
	return float(posmod(maxi(1, k) - 1, Regions.PER_REGION)) / float(Regions.PER_REGION - 1)

## {grade: weight} for group k (boss rolls shift the window up).
static func window(k: int, boss := false) -> Dictionary:
	var b := base_grade(k) + (BOSS_SHIFT if boss else 0)
	var p := progress(k)
	var out := {}
	for off in WINDOW:
		var w: float = lerpf(WINDOW[off][0], WINDOW[off][1], p)
		var g := maxi(1, b + int(off))
		out[g] = out.get(g, 0.0) + w
	return out

static func roll_grade(k: int, boss := false) -> int:
	var win := window(k, boss)
	var total := 0.0
	for g in win:
		total += win[g]
	var r := randf() * total
	for g in win:
		r -= win[g]
		if r <= 0.0:
			return g
	return base_grade(k)

static func featured(k: int) -> Array:
	return Regions.info(region_of(k)).get("gear", [])

## Region-weighted family (optionally limited to one slot's families).
static func roll_family(k: int, slot := "") -> String:
	var fe := featured(k)
	var pool: Array = Defs.FAMILIES if slot == "" else families_in(slot)
	var total := 0.0
	for f in pool:
		total += FEATURED_W if f in fe else 1.0
	var r := randf() * total
	for f in pool:
		r -= FEATURED_W if f in fe else 1.0
		if r <= 0.0:
			return f
	return pool[0]

## Item keys that would be the third piece of a merge group the player holds exactly two of (unequipped:
## the permanent storage plus this run's bag), within the current window's reach. The family is rolled
## within the group's slot. Merging itself happens in the lobby storage.
static func pair_keys(game: Node, k: int) -> Array:
	if game == null:
		return []
	var counts := {}
	for e in game.inventory + Meta.storage_entries():
		if e.get("kind", "") == "equip" and is_family(e["key"]):
			var gk := group_of(e["key"])
			counts[gk] = counts.get(gk, 0) + 1
	var b := base_grade(k)
	var out := []
	for gk in counts:
		var g := group_grade(gk)
		if counts[gk] == 2 and g >= b - 2 and g <= b + 1:
			out.append(key(roll_family(k, group_slot(gk)), g))
	return out

## One family-gear drop for group k: merge assist first, else window grade + region-weighted family.
static func roll_key(game: Node, k: int, boss := false, assist := ASSIST) -> String:
	if randf() < assist:
		var pairs := pair_keys(game, k)
		if not pairs.is_empty():
			return pairs[randi() % pairs.size()]
	return key(roll_family(k), roll_grade(k, boss))

# ---------------------------------------------------------------- permanent slot levels (lobby 강화)
## Each hero's weapon / armor / accessory slot has a level (Meta.slot_lv) bought with gold + 강화석. The level
## belongs to the slot, not the item: whatever is worn there (permanent or picked up this run) gets the bonus.
## The level that counts is capped by the worn item's grade (grade x SLOT_CAP_PER_GRADE).
const SLOT_CAP_PER_GRADE := 10
const SLOT_BONUS := {"weapon": {"atk": 3.0}, "armor": {"hp": 22.0}, "accessory": {"atk": 1.5, "hp": 10.0}}

static func slot_cap(e) -> int:
	if e == null:
		return 0
	return mini(int(Defs.item(e["key"]).get("tier", 1)), STAR_FROM) * SLOT_CAP_PER_GRADE

static func slot_bonus(slot: String, lv: int) -> Dictionary:
	var out := {}
	var per: Dictionary = SLOT_BONUS.get(slot, {})
	for k in per:
		out[k] = floorf(per[k] * lv)
	return out

## Cost of raising a slot from level lv to lv + 1: {"gold", "stones"}.
static func upgrade_cost(lv: int) -> Dictionary:
	return {"gold": 40 + 25 * lv + int(pow(lv, 1.6)), "stones": 2 + int(lv * 0.8)}

## Additive per-kill gear drop bonus for group k (early regions only).
static func drop_bonus(k: int) -> float:
	var r := region_of(k)
	return EARLY_DROP[r] if r < EARLY_DROP.size() else 0.0

## Era scaling for unique (legendary / ultra / crown) gear: a unique found later in the march carries
## proportionally stronger flat stats so it never falls behind the family ladder. 1.0 until its era.
static func era_power(tier: int, k: int) -> float:
	var behind := base_grade(k) - (tier - 1)
	return snappedf(pow(GROWTH, behind), 0.01) if behind > 0 else 1.0
