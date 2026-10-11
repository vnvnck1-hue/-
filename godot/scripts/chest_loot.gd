class_name ChestLoot
extends RefCounted
## Treasure chest gacha rules (Squad Busters style): data only, no presentation (see ChestGacha).
##   - chests sometimes lie on the march road (FIELD_CHANCE per ordinary group) and every mid-boss drops one
##     that already starts at 희귀; picked-up chests pile up on the bag's top-left badge (game.chests).
##   - opening one: TAPS taps, each tap may raise the chest one tier (일반 -> 희귀 -> 영웅 -> 전설),
##     then it bursts open. The tier decides how many items, how high they roll and the gold.

const TAPS := 4
const NAMES := ["일반", "희귀", "영웅", "전설"]
const RARITY := ["common", "rare", "epic", "legendary"]   # Defs.RARITY_COL keys (tier colour)
## Chance that one tap raises tier i -> i + 1.
const UP_ODDS := [0.30, 0.18, 0.09]
const FIELD_CHANCE := 0.09   # was 0.3, cut by 70%
const BOSS_TIER := 1
## Per tier: item count, grade bonus of the best item (over the stage drop window), gold multiplier.
const ITEMS := [1, 2, 3, 4]
const BEST_BONUS := [0, 1, 2, 3]
const REST_BONUS := [0, 0, 0, 1]   # the other items of a tier-t chest roll this much higher (unless merge assist)
const GOLD_MULT := [1.0, 2.0, 3.5, 6.0]

static func tier_name(t: int) -> String:
	return NAMES[clampi(t, 0, NAMES.size() - 1)]

static func tier_color(t: int) -> Color:
	return Defs.RARITY_COL[RARITY[clampi(t, 0, RARITY.size() - 1)]]

## One tap: does the chest climb a tier?
static func roll_up(t: int) -> bool:
	return t < UP_ODDS.size() and randf() < UP_ODDS[t]

## Short reward line for the chest screen ("장비 2 · 골드 ×2").
static func preview(t: int) -> String:
	var s := "장비 %d개" % ITEMS[t]
	if BEST_BONUS[t] > 0:
		s += " · 최대 +%d등급" % BEST_BONUS[t]
	return s + " · 골드 ×%s" % str(GOLD_MULT[t]).trim_suffix(".0")

static func gold(game: Node, k: int, t: int) -> int:
	var base := 40.0 + 9.0 * maxi(1, k)
	var gm := Stats.g(Stats.perk_fx(game), "goldMult") if game else 0.0
	return int(roundf(base * GOLD_MULT[t] * (1.0 + gm) / 5.0) * 5.0)

## The rewards of a tier-t chest opened around group k: {"items": [entries], "lucky": [bool], "gold": int}.
## The first item is the best one (stage window grade + BEST_BONUS); the rest roll the normal window with
## a strong merge assist, so a chest often hands over the third copy of a pair ("lucky" = completes a merge).
static func roll(game: Node, k: int, t: int) -> Dictionary:
	var items := []
	var lucky := []
	for i in ITEMS[t]:
		var key := ""
		if i == 0 and t == 3 and k >= 15 and randf() < 0.3:
			key = Inventory.random_legendary(k >= 25 and randf() < 0.2)
		elif i == 0:
			key = Gear.key(Gear.roll_family(k), Gear.roll_grade(k) + BEST_BONUS[t])
		elif REST_BONUS[t] > 0 and randf() > 0.4:
			key = Gear.key(Gear.roll_family(k), Gear.roll_grade(k) + REST_BONUS[t])
		else:
			key = Gear.roll_key(game, k, false, 0.45)
		var e := Inventory.make_found(key, k)
		lucky.append(game != null and Inventory._completes_merge(game, e))
		items.append(e)
	return {"items": items, "lucky": lucky, "gold": gold(game, k, t)}

## Expected final-tier distribution after TAPS taps (dev check).
static func odds() -> Array:
	var p := [1.0, 0.0, 0.0, 0.0]
	for i in TAPS:
		var n := [0.0, 0.0, 0.0, 0.0]
		for t in 4:
			var up: float = UP_ODDS[t] if t < UP_ODDS.size() else 0.0
			n[t] += p[t] * (1.0 - up)
			if t < 3:
				n[t + 1] += p[t] * up
		p = n
	return p
