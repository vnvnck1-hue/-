class_name Regions
extends RefCounted
## The world of the Endless March: six regions on one world map, visited in order and looped forever.
## Region r holds groups 10r+1 .. 10r+10 (its mid-boss guards the exit). The march field takes its ground,
## light and props from the region's theme, so the map always tells where the trio is marching.
##   gear: featured equipment families (drop x Gear.FEATURED_W) — the region's "specialty" for merges.
##   roster: which creature line camps there (Defs.ROSTERS: beasts / monsters, each with its own mid-boss).
##   map: island centre on the world map (x, z) in map units; size: island radius; tilt: outline phase.

const PER_REGION := 10

const LIST := [
	{"name": "햇살 왕국", "theme": "meadow", "gear": ["sword", "shield", "helmet"], "roster": "beast", "desc": "왕성 아래 펼쳐진 햇살 가득한 초원", "map": Vector2(0.55, -0.35), "size": 1.95, "seed": 3},
	{"name": "거목의 숲", "theme": "forest", "gear": ["bow", "staff", "amulet"], "roster": "beast", "desc": "푸른 정령이 깃든 거목이 지키는 깊은 숲", "map": Vector2(-2.85, -2.6), "size": 1.62, "seed": 11},
	{"name": "황금 모래톱", "theme": "desert", "gear": ["axe", "ring", "helmet"], "roster": "monster", "desc": "선인장과 바위 언덕이 이어지는 뜨거운 모래땅", "map": Vector2(-2.55, 2.35), "size": 1.66, "seed": 23},
	{"name": "불꽃 화산", "theme": "volcano", "gear": ["axe", "sword", "shield"], "roster": "monster", "desc": "용암 강이 흐르는 검은 현무암 대지", "map": Vector2(0.85, 4.55), "size": 1.8, "seed": 31},
	{"name": "황혼 광산", "theme": "mine", "gear": ["staff", "ring", "amulet"], "roster": "monster", "desc": "수정과 거대 버섯이 빛나는 보랏빛 갱도", "map": Vector2(3.2, 1.55), "size": 1.5, "seed": 47},
	{"name": "서리 봉우리", "theme": "frost", "gear": ["bow", "shield", "amulet"], "roster": "beast", "desc": "구름 위에 떠 있는 눈과 얼음의 섬", "map": Vector2(0.15, -5.35), "size": 1.5, "seed": 59},
]

static func count() -> int:
	return LIST.size()

## Region index (unbounded: laps keep counting) of encounter group k (k >= 1).
static func of_group(k: int) -> int:
	return maxi(0, int((k - 1) / PER_REGION))

static func info(r: int) -> Dictionary:
	return LIST[posmod(r, LIST.size())]

static func lap(r: int) -> int:
	return int(r / LIST.size())

static func theme(r: int) -> Dictionary:
	return THEMES[info(r)["theme"]]

## Island outline radius at angle a (shared by the 3D island mesh and the sea shader's shallows).
static func shape_r(r: int, a: float) -> float:
	var d: Dictionary = info(r)
	var p: float = d["seed"] * 1.37
	return d["size"] * (1.0 + 0.12 * sin(2.0 * a + p) + 0.08 * sin(3.0 * a + p * 2.1) + 0.05 * sin(5.0 * a + p * 0.7) + 0.03 * sin(7.0 * a + p * 3.3))

# ---------------------------------------------------------------- field themes
## Ground: grass (outer terrain, two noise tones), field (battle band, two tones), trail (worn centre path),
## bump (border lips; round = superellipsoid roundness), deco (trail details), camp (campfire ring stone).
## Light: sun / fill / ambient / sky / fog colours and energies, saturation and glow.
## Props: near / mid / far weighted tables (names handled by MarchWorld._spawn_prop).
const THEMES := {
	"meadow": {
		"grass": [Color("7cc443"), Color("67b13a")], "field": [Color("a2d95c"), Color("95d052")], "trail": Color("e6bb79"),
		"bump": [Color("62b23c"), Color("7cc84a")], "round": 0.55, "deco": "stones", "deco_col": Color("f3dcb0"), "edge": "daisies", "camp": Color("a7a3b5"),
		"sun": Color("fff1d6"), "sun_e": 1.25, "fill": Color("a8c8ff"), "fill_e": 0.28, "amb": Color("b3bdff"), "amb_e": 0.62,
		"sky": Color("8fd0f0"), "fog": Color("cfe9ff"), "sat": 1.3, "glow": 0.5,
		"near": [["daisies", 0.3], ["lily", 0.22], ["mushrooms", 0.2], ["rock", 0.12], ["stump", 0.11], ["blob_y", 0.1]],
		"mid": [["blob_y", 0.24], ["blob_g", 0.14], ["stump", 0.08], ["pine", 0.2], ["cube", 0.1], ["egg", 0.1], ["rock", 0.08], ["lily", 0.06]],
		"far": [["pine", 0.3], ["puff", 0.2], ["cube", 0.14], ["egg", 0.14], ["terrace", 0.14], ["pond", 0.08]],
	},
	"forest": {
		"grass": [Color("3f8a3e"), Color("2f7440")], "field": [Color("74ad4c"), Color("66a046")], "trail": Color("a8845c"),
		"bump": [Color("3c8f3c"), Color("4fa446")], "round": 0.55, "deco": "stones", "deco_col": Color("c9cfa4"), "edge": "ferns", "camp": Color("8f9a88"),
		"sun": Color("ffecc4"), "sun_e": 1.1, "fill": Color("9fe8d0"), "fill_e": 0.38, "amb": Color("9fcab8"), "amb_e": 0.7,
		"sky": Color("6cb8b4"), "fog": Color("a4d8c8"), "sat": 1.15, "glow": 0.65,
		"near": [["ferns", 0.3], ["mushrooms", 0.22], ["stump", 0.14], ["mossrock", 0.16], ["spirit", 0.1], ["log", 0.08]],
		"mid": [["pine", 0.3], ["puff", 0.2], ["egg", 0.14], ["log", 0.1], ["blob_g", 0.14], ["spirit", 0.08]],
		"far": [["pine", 0.34], ["giant", 0.16], ["puff", 0.2], ["egg", 0.16], ["terrace", 0.14]],
	},
	"desert": {
		"grass": [Color("e9c47c"), Color("ddb36a")], "field": [Color("f4d996"), Color("eccd86")], "trail": Color("c99558"),
		"bump": [Color("d99c58"), Color("e6b06c")], "round": 0.4, "deco": "stones", "deco_col": Color("fff1cc"), "edge": "cactus_s", "camp": Color("d8b98a"),
		"sun": Color("fff2cc"), "sun_e": 1.35, "fill": Color("ffcc9a"), "fill_e": 0.32, "amb": Color("ffe2bd"), "amb_e": 0.6,
		"sky": Color("9fd8f2"), "fog": Color("f6e6c6"), "sat": 1.18, "glow": 0.5,
		"near": [["cactus_s", 0.28], ["sandrock", 0.22], ["drybush", 0.22], ["bones", 0.12], ["cactus", 0.16]],
		"mid": [["cactus", 0.3], ["palm", 0.24], ["sandrock", 0.2], ["drybush", 0.12], ["mesa", 0.14]],
		"far": [["mesa", 0.34], ["palm", 0.26], ["dune", 0.22], ["cactus", 0.18]],
	},
	"volcano": {
		"grass": [Color("4d3c46"), Color("3d3039")], "field": [Color("7a6466"), Color("6c575a")], "trail": Color("3e2c30"),
		"bump": [Color("3a3036"), Color("4a3d44")], "round": 0.3, "deco": "embers", "deco_col": Color("ff7a2a"), "edge": "embers", "camp": Color("5a4a52"),
		"sun": Color("ffb27a"), "sun_e": 1.0, "fill": Color("ff6a48"), "fill_e": 0.55, "amb": Color("b07a84"), "amb_e": 0.72,
		"sky": Color("5a2a36"), "fog": Color("8a4036"), "sat": 1.2, "glow": 1.0,
		"near": [["obsidian", 0.3], ["embers", 0.26], ["vent", 0.18], ["deadtree", 0.12], ["lavapool", 0.14]],
		"mid": [["basalt", 0.3], ["deadtree", 0.18], ["lavapool", 0.2], ["obsidian", 0.16], ["vent", 0.16]],
		"far": [["cone", 0.3], ["basalt", 0.3], ["lavapool", 0.2], ["ledge_v", 0.2]],
	},
	"mine": {
		"grass": [Color("433a74"), Color("3a6666")], "field": [Color("6f6496"), Color("635889")], "trail": Color("9a89b8"),
		"bump": [Color("6d6492"), Color("7d74a0")], "round": 0.35, "deco": "rails", "deco_col": Color("8a86a8"), "edge": "shrooms", "camp": Color("7d74a0"),
		"sun": Color("c2b0ff"), "sun_e": 0.95, "fill": Color("ff8fc8"), "fill_e": 0.5, "amb": Color("7c68e8"), "amb_e": 0.85,
		"sky": Color("2a1f56"), "fog": Color("5a3fa0"), "sat": 1.18, "glow": 0.9,
		"near": [["shrooms", 0.3], ["crystals", 0.24], ["crock", 0.24], ["lantern", 0.18], ["cart", 0.08]],
		"mid": [["cart", 0.16], ["pillar", 0.18], ["bigshroom", 0.24], ["crystals", 0.14], ["crock", 0.14], ["lantern", 0.14]],
		"far": [["scaffold", 0.3], ["pulley", 0.16], ["bigshroom", 0.22], ["pillar", 0.16], ["ledge", 0.16]],
	},
	"frost": {
		"grass": [Color("d4e4f2"), Color("c2d6ea")], "field": [Color("e6eff9"), Color("d8e5f3")], "trail": Color("9cc2e4"),
		"bump": [Color("f2f7ff"), Color("dfeaf6")], "round": 0.6, "deco": "ice", "deco_col": Color("bfe6ff"), "edge": "icebits", "camp": Color("9fb2c8"),
		"sun": Color("fff8ee"), "sun_e": 0.92, "fill": Color("a8d0ff"), "fill_e": 0.42, "amb": Color("b8d0ff"), "amb_e": 0.66,
		"sky": Color("94c8ee"), "fog": Color("d4e8fa"), "sat": 1.18, "glow": 0.6,
		"near": [["snowrock", 0.28], ["icebits", 0.26], ["mound", 0.22], ["snowman", 0.08], ["icespike", 0.16]],
		"mid": [["snowpine", 0.36], ["icespike", 0.2], ["snowrock", 0.16], ["mound", 0.14], ["snowman", 0.06], ["icebits", 0.08]],
		"far": [["snowpine", 0.42], ["peak", 0.22], ["icecliff", 0.2], ["icespike", 0.16]],
	},
}
