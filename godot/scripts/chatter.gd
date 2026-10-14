class_name Chatter
extends Control
## Tiny white speech bubbles: every hero and monster now and then pipes up with an onomatopoeia or a
## two-word line. Purely cosmetic — it only reads the units it is handed and never touches game state.
##   provider: Callable -> Array of {"n": Node3D, "key": kind/class, "ctx": context, "h": head height (m)}
##   ctx: battle / low (hurt) / march / camp / sleep / idle / lobby ("" = stay quiet)
## Bubbles follow their speaker, pop in with a squash, hold briefly and fade. At most MAX_ON_SCREEN at once.

const MAX_ON_SCREEN := 3
const GAP := 1.5              # min seconds between two new bubbles (whole screen)
const POP := 0.25             # pop-in
const HOLD := 3.0             # fully readable time (real seconds; frozen while paused / a popup is up)
const FADE := 0.25
const LIFT := 24.0           # px above the head point (clears the hp bar)
const INK := Color("16121f")
const TEXT := Color("2a2238")

## Lines per kind and context. "*" is the fallback context of a kind.
const LINES := {
	# heroes
	"warrior": {"battle": ["간다!", "덤벼!", "흐압!", "막아낸다!", "읏차!"], "low": ["아직이야!", "크윽…"],
		"march": ["영차 영차", "가자!", "흠흠~", "든든하지?"], "*": ["준비 완료!", "흐흠!", "검 반짝~"]},
	"ranger": {"battle": ["조준!", "슉!", "명중!", "거기!"], "low": ["위험해!", "으앗!"],
		"march": ["룰루~", "저기 뭐지?", "발 아파~"], "*": ["활 점검!", "헤헤~", "바람 좋다"]},
	"mage": {"battle": ["화르륵!", "펑!", "번쩍!", "주문 간다"], "low": ["힐 좀!", "으으…"],
		"march": ["마나가…", "후아암", "책 읽고 싶다"], "*": ["흠흠…", "불꽃 준비", "반짝!"]},
	# classic cast
	"normal": {"*": ["끼에엑!", "죽어라!", "헤헤", "덤벼!"]},
	"fast": {"*": ["슉슉!", "헤헷", "잡아봐!"]},
	"tank": {"*": ["철컹!", "막는다", "흡!"]},
	"boss": {"*": ["우워어!", "부숴라!", "크하하!"]},
	"goblin": {"*": ["키키!", "약탈이다!", "끼약"]},
	"ninja": {"*": ["닌닌!", "슉!", "……"]},
	"splitter": {"*": ["뽀잉!", "말랑", "뿌직"]},
	"splitling": {"*": ["뾱!", "말랑~", "삐"]},
	"sprinter": {"*": ["부릉부릉!", "비켜!", "후다닥"]},
	"giant": {"*": ["쿠구궁", "우우웅", "돌…"]},
	"hydra": {"*": ["샤아아!", "쉬익", "셋이 하나"]},
	"illusionist": {"*": ["짜잔!", "어느 쪽?", "후후"]},
	"illusion": {"*": ["짜잔!", "나야 나", "후후"]},
	"tut_easy": {"*": ["……", "툭", "때려 봐"]},
	"tut_tough": {"*": ["끄떡없다", "툭", "……"]},
	# beasts
	"wolf": {"*": ["아우우~!", "크르릉", "왈!", "킁킁"], "camp": ["킁킁", "하암~", "꼬리 살랑"]},
	"hornbunny": {"*": ["깡총!", "뿅!", "찍!"], "camp": ["냠냠", "깡총~", "오물오물"]},
	"boar": {"*": ["꿀꿀!", "쿵쿵!", "푸르릉", "꾸웩!"], "camp": ["꿀꿀~", "킁킁", "도토리!"]},
	"bear": {"*": ["크아앙!", "어흥!", "으르렁"], "camp": ["꿀 어딨어", "하아암", "어흥~"]},
	# monsters
	"imp": {"*": ["키히히!", "깔깔!", "찌릿!"], "camp": ["히히", "장난칠까", "룰루"]},
	"eyebat": {"*": ["끼익!", "째릿", "찍찍"], "camp": ["파닥파닥", "끼익~", "두리번"]},
	"mimic": {"*": ["덜컹!", "와구와구", "짤그랑"], "camp": ["보물 아님", "덜컹…", "쩝쩝"]},
	"horror": {"*": ["꾸르륵", "철퍽!", "쉬익…"], "camp": ["꿀렁", "꾸륵~", "촉촉"]},
	# ranged support
	"slinger": {"*": ["휙휙!", "받아라!", "키키, 명중!", "돌 간다~"], "camp": ["돌 줍줍", "빙글빙글", "이 돌 예쁘다"]},
	"crossbow": {"*": ["조준…", "철컥!", "놓치지 않아", "피융!"], "camp": ["시위 점검", "……", "바람 체크"]},
	"shaman": {"*": ["타올라라!", "우가 부가!", "불의 저주!", "화르륵"], "camp": ["불님께 기도", "우가~", "연기 맛있다"]},
	# mid-bosses
	"mammoth": {"*": ["뿌우우!", "쿠웅!", "짓밟는다", "부우웅"], "sleep": ["쿠우…", "음머…"]},
	"abyss": {"*": ["무릎 꿇어라", "크흐흐…", "심연으로", "어리석은 것"], "sleep": ["……", "크흐…"]},
	"spider": {"*": ["끼리릭…", "거미줄에 걸렸구나", "쉬이익!", "맛있겠다"], "sleep": ["사각사각…", "……"]},
	"warden": {"*": ["불태워라!", "쿠웅!", "집행한다", "재가 되어라"], "sleep": ["화르르…", "음…"]},
	"flytrap": {"*": ["와앙!", "냠냠!", "뻐끔뻐끔", "씨앗 받아라!"], "sleep": ["쿨…", "광합성 중"]},
	"murPriest": {"*": ["음르글!", "심해의 빛이여!", "므르르륵", "바다가 부른다"], "sleep": ["뻐끔…", "음르…"]},
	"murWhip": {"*": ["므를글!", "낚았다!", "끌려와라!", "음르그!"], "sleep": ["꾸르륵…", "음…"]},
	"murSpear": {"*": ["므르르륵!", "돌격!", "음르글!", "찌른다!"], "sleep": ["뻐끔…", "음르…"]},
}
## Context lines every monster may borrow besides its own.
const SHARED := {
	"camp": ["배고파", "불 따뜻해", "흥얼~", "졸려…"],
	"sleep": ["쿨…", "음냐음냐", "드르렁"],
	"low": ["아야!", "으악!", "히익!"],
}

var cam: Camera3D
var font: Font
var provider: Callable
var quiet: Callable          # -> true while a popup / overlay covers the field
var _next := {}              # Node3D -> earliest time it may speak again
var _bubbles: Array = []     # [{node: Control, n: Node3D, h: float, t: float}]
var _t := 0.0
var _last := -99.0
var _purge_at := 0.0
var _sb: StyleBoxFlat         # bubble look, shared by every bubble
var _ls: LabelSettings

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1   # over hp bars and damage numbers; hidden while a popup is up (quiet)

func _process(delta: float) -> void:
	var hush: bool = get_tree().paused or (quiet.is_valid() and quiet.call())
	visible = not hush
	if hush:
		return
	var real := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)   # hit-stops / drag slow-mo don't stretch or cut it
	_t += real
	for b in _bubbles.duplicate():
		b["age"] += real
		_animate(b)
	_follow()
	if not provider.is_valid() or not is_instance_valid(cam):
		return
	# forget speakers that are gone (also while no one gets to speak, or _next keeps every dead monster)
	if _t >= _purge_at:
		_purge_at = _t + 2.0
		for k in _next.keys():
			if not is_instance_valid(k):
				_next.erase(k)
	if _bubbles.size() >= MAX_ON_SCREEN or _t - _last < GAP:
		return
	var cands: Array = []
	for e in provider.call():
		var n: Node3D = e["n"]
		if e["ctx"] == "" or _talking(n):
			continue
		if not _next.has(n):
			_next[n] = _t + randf_range(1.2, 12.0)   # stagger first words
			continue
		if _t >= _next[n] and _on_screen(n, e["h"]):
			cands.append(e)
	if cands.is_empty():
		return
	var e: Dictionary = cands[randi() % cands.size()]
	var txt := line(e["key"], e["ctx"])
	if txt != "":
		say(e["n"], e["h"], txt)
	var busy: bool = e["ctx"] in ["battle", "low"]
	_next[e["n"]] = _t + (randf_range(10.0, 22.0) if busy else randf_range(8.0, 18.0))

## Pick a line for kind in context (own context lines, then shared context lines, then the kind's fallback).
static func line(key: String, ctx: String) -> String:
	var d: Dictionary = LINES.get(key, {})
	var pool: Array = (d.get(ctx, []) as Array).duplicate()
	if SHARED.has(ctx) and not (ctx in ["low", "sleep"] and not pool.is_empty()):
		pool.append_array(SHARED[ctx])
	if pool.is_empty() or (ctx in ["camp", "march", "idle", "lobby"] and randf() < 0.35):
		pool.append_array(d.get("*", []))
	if pool.is_empty():
		pool = ["…!"]
	return pool[randi() % pool.size()]

func _talking(n: Node3D) -> bool:
	for b in _bubbles:
		if is_instance_valid(b["n"]) and b["n"] == n:
			return true
	return false

func _on_screen(n: Node3D, h: float) -> bool:
	if not is_instance_valid(n) or not n.is_visible_in_tree():
		return false
	var w := n.global_position + Vector3(0, h, 0)
	if cam.is_position_behind(w):
		return false
	var p := cam.unproject_position(w)
	var r := get_viewport_rect().size
	return p.x > 30 and p.x < r.x - 30 and p.y > 150 and p.y < r.y * 0.72

## Show a bubble over node n (h metres above its origin) right now.
func say(n: Node3D, h: float, txt: String) -> void:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color.WHITE
		_sb.border_color = INK
		_sb.set_border_width_all(3)
		_sb.set_corner_radius_all(16)
		_sb.content_margin_left = 12
		_sb.content_margin_right = 12
		_sb.content_margin_top = 3
		_sb.content_margin_bottom = 4
		_sb.shadow_color = Color(0, 0, 0, 0.18)
		_sb.shadow_size = 0
		_sb.shadow_offset = Vector2(0, 3)
	box.add_theme_stylebox_override("panel", _sb)
	var l := Label.new()
	l.text = txt
	if _ls == null or _ls.font != font:
		_ls = LabelSettings.new()
		_ls.font = font
		_ls.font_size = 24
		_ls.font_color = TEXT
	l.label_settings = _ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	# tail: white triangle with an ink rim, poking down at the speaker
	var tail := Node2D.new()
	var rim := Polygon2D.new()
	rim.polygon = PackedVector2Array([Vector2(-10, -3), Vector2(10, -3), Vector2(0, 13)])
	rim.color = INK
	tail.add_child(rim)
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([Vector2(-6.5, -4), Vector2(6.5, -4), Vector2(0, 8)])
	fill.color = Color.WHITE
	tail.add_child(fill)
	box.add_child(tail)
	add_child(box)
	box.reset_size()
	tail.position = Vector2(box.size.x * 0.5, box.size.y - 1)
	box.pivot_offset = Vector2(box.size.x * 0.5, box.size.y + 12)
	box.scale = Vector2(0.2, 0.2)
	box.rotation = randf_range(-0.06, 0.06)
	var b := {"node": box, "n": n, "h": h, "t": _t, "age": 0.0}
	_bubbles.append(b)
	_last = _t
	_follow()
	_animate(b)

## Speaker died (or was freed): its bubble pops away with it.
func _dismiss(b: Dictionary) -> void:
	_bubbles.erase(b)
	var box: Control = b["node"]
	var tw := box.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(box, "modulate:a", 0.0, 0.12)
	tw.tween_property(box, "scale", Vector2(0.5, 0.5), 0.12)
	tw.chain().tween_callback(box.queue_free)

## Pop in (back-ease), hold HOLD seconds, fade out; frees itself at the end.
func _animate(b: Dictionary) -> void:
	var box: Control = b["node"]
	var age: float = b["age"]
	if age < POP:
		var k := age / POP - 1.0
		var e := 1.0 + 2.70158 * k * k * k + 1.70158 * k * k
		box.scale = Vector2.ONE * lerpf(0.2, 1.0, e)
		box.modulate.a = 1.0
	elif age < POP + HOLD:
		box.scale = Vector2.ONE
		box.modulate.a = 1.0
	elif age < POP + HOLD + FADE:
		var f := (age - POP - HOLD) / FADE
		box.scale = Vector2.ONE * (1.0 - 0.2 * f)
		box.modulate.a = 1.0 - f
	else:
		_bubbles.erase(b)
		box.queue_free()

func _follow() -> void:
	var r := get_viewport_rect().size
	for b in _bubbles.duplicate():
		var box: Control = b["node"]
		if not is_instance_valid(b["n"]) or b["n"].get("alive") == false:
			_dismiss(b)
			continue
		if not (b["n"] as Node3D).is_visible_in_tree():
			box.visible = false
			continue
		var w: Vector3 = (b["n"] as Node3D).global_position + Vector3(0, b["h"], 0)
		if cam.is_position_behind(w):
			box.visible = false
			continue
		box.visible = true
		var p := cam.unproject_position(w)
		var pos := p - Vector2(box.size.x * 0.5, box.size.y + 12 + LIFT)
		pos.x = clampf(pos.x, 6.0, r.x - box.size.x - 6.0)
		box.position = pos
