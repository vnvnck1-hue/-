class_name UiTheme
extends RefCounted
## 뚜까펫(Ttukka Pet: Survival) 레퍼런스에서 뽑은 UI 팔레트와 스타일 규칙.
## - 두꺼운 거의-검정 외곽선, 흰 글자 + 검정 테두리
## - 어두운 남보라 패널(정보 창), 크림 본문 + 보라 체크무늬 머리띠(확인 창)
## - 버튼: 아래로 두꺼운 입체 턱 + 위쪽 밝은 광택 띠. 확인=연두, 주요 행동=노랑(검은 글자), 보조=남색
## - 배너: 주황 리본, 빛줄기, 섬광 / 경고: 빨간 가로 띠

## UI 프리셋: "ttukka"(뚜까펫 스타일) / "classic"(기존 Toy Clash 스타일, 그대로 보존).
## 로비의 프리셋 버튼으로 바꾸며, user://ui_preset.cfg에 저장된다.
const PRESETS := ["ttukka", "classic"]
const PRESET_NAME := {"ttukka": "뚜까펫", "classic": "클래식"}
const SAVE_PATH := "user://ui_preset.cfg"
static var preset := ""

static func tt() -> bool:
	if preset == "":
		load_preset()
	return preset == "ttukka"

static func load_preset() -> void:
	var cf := ConfigFile.new()
	preset = "ttukka"
	for a in OS.get_cmdline_user_args():   # 확인용: --ui=classic|ttukka (저장 안 함)
		if a.begins_with("--ui=") and PRESETS.has(a.substr(5)):
			preset = a.substr(5)
			return
	if cf.load(SAVE_PATH) == OK:
		var p: String = cf.get_value("ui", "preset", "ttukka")
		if PRESETS.has(p):
			preset = p

static func set_preset(p: String) -> void:
	preset = p
	var cf := ConfigFile.new()
	cf.set_value("ui", "preset", p)
	cf.save(SAVE_PATH)

static func next_preset() -> String:
	tt()
	return PRESETS[(PRESETS.find(preset) + 1) % PRESETS.size()]

## 외곽선 색: 프리셋마다 다르다(클래식 1d1530 / 뚜까펫 거의 검정).
static func ink() -> Color:
	return INK if tt() else CLASSIC_INK

const CLASSIC_INK := Color("1d1530")
const INK := Color("16121f")          # 외곽선(거의 검정)
const INK_SOFT := Color("26223c")

# 어두운 패널 계열
const NIGHT := Color("2d244b")        # 기본 패널(하단 덱/가방)
const NIGHT_DEEP := Color("221b3a")
const PLUM := Color("372444")         # 덱 패널 머리
const BODY := Color("342e5b")         # 정보 창 본문
const ROW := Color("413c67")          # 본문 안의 줄
const FRAME := Color("5845a6")        # 정보 창 보라 테두리
const FRAME_HI := Color("6d4bb8")
const FRAME_LINE := Color("5d94aa")   # 테두리 안쪽 청록 선
const HEADER := Color("51439b")       # 크림 창의 보라 머리띠
const HEADER_CHECK := Color("5d4fae")

# 밝은 패널 계열
const CREAM := Color("fffff2")
const INSET := Color("d4ced6")        # 크림 위 회색 칸
const PILL_DARK := Color("252b3c")    # 수치 알약

# 버튼
const GREEN := Color("76cd2b")
const GREEN_HI := Color("99e555")
const YELLOW := Color("fec30d")
const YELLOW_HI := Color("faec3b")
const NAVY := Color("4c467b")
const NAVY_HI := Color("5f6c98")
const RED := Color("ef3f55")
const ORANGE := Color("f2900f")
const ORANGE_DEEP := Color("dd5f01")
const RIBBON_EDGE := Color("a02c1c")
const GREY := Color("6e6a8c")

# 글자
const TXT := Color("fefeff")
const TXT_DIM := Color("a9a4cb")
const TXT_LABEL := Color("6e71a0")
const TXT_VALUE := Color("9cef42")
const TXT_DARK := Color("2a2440")
const TXT_YELLOW := Color("ffe14a")

# 바 (클래식은 hp_col()/trail_col()이 예전 색을 돌려준다)
const HP := Color("76cd2b")
const HP_ENEMY := Color("ef3f55")
const BAR_TRACK := Color("1c1830")
const BAR_TRAIL := Color("f2900f")

## 예전 Toy Clash 버튼 색 → 뚜까펫 버튼 역할 색. 버튼은 역할이 같은 색끼리 묶인다.
const BUTTON_MAP := {
	"ff9f1c": "yellow",  # 전투 시작 / 닫기 / 떠나기 (주요 행동)
	"3fa9f5": "green",   # 다시 시작 / 해금 (확인)
	"27c6b0": "green",   # 사용 / 구매
	"6f6cf0": "navy",    # 특성 / 새로고침 / 다시 뽑기 (보조)
	"8a7ad8": "navy",    # 로비로
	"8a8aa0": "navy",    # X / 버리기
	"ff6b8a": "navy",    # 창 닫기 X
	"ff7a5a": "red",     # 판매
	"a0a0b0": "grey",    # 비활성 느낌
}

static func role_color(role: String) -> Color:
	match role:
		"yellow": return YELLOW
		"green": return GREEN
		"navy": return NAVY
		"red": return RED
		"grey": return GREY
	return GREEN

## 버튼 역할: 색을 받아 역할로 바꾼다. 표에 없는 색은 그 색 그대로 쓴다("" 반환).
static func button_role(c: Color) -> String:
	return BUTTON_MAP.get(c.to_html(false), "")

## 역할별 글자색: 노랑 버튼만 어두운 글자(외곽선 없음).
static func button_text(role: String) -> Color:
	return Color("3a2400") if role == "yellow" else TXT

static func hi(c: Color) -> Color:
	if c == GREEN: return GREEN_HI
	if c == YELLOW: return YELLOW_HI
	if c == NAVY: return NAVY_HI
	return c.lightened(0.28)

static func lip(c: Color) -> Color:
	return c.darkened(0.42)

## 크림 창 안의 예전 갈색 글자 → 뚜까펫 남색 글자.
const TEXT_MAP := {
	"4a3a30": "2f2a45",
	"3a2a20": "2a2440",
	"8a6a50": "6b6590",
	"8a7a60": "6b6590",
	"b0a890": "9a96b4",
	"a07a20": "b07800",
	"5a3a00": "3a2400",
}

static func text_color(c: Color) -> Color:
	var m: String = TEXT_MAP.get(c.to_html(false), "")
	if m == "":
		return c
	var out := Color(m)
	out.a = c.a
	return out

# ---------------------------------------------------------------- style boxes
static func flat(bg: Color, radius := 12, border := 0, border_col := INK) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_col
	sb.anti_aliasing = true
	return sb

## 입체 버튼: 아래 어두운 턱 + 외곽선 있는 몸통 + 위쪽 광택 띠.
static func button_box(c: Color, radius := 20, pressed := false) -> StyleBox:
	var lb := Layered.new()
	var depth := 3.0 if pressed else 8.0
	var top := 5.0 if pressed else 0.0
	lb.add(flat(INK, radius, 0), Vector4(0, top, 0, 0))
	lb.add(flat(c, radius, 4), Vector4(0, top, 0, -depth))
	var g := flat(Color(hi(c), 0.95), maxi(radius - 6, 4), 0)
	lb.add(g, Vector4(-8, -(top + 6.0), -8, 0), 0.40)   # 위 40%만
	lb.content_margin_bottom = depth
	lb.content_margin_top = top
	lb.content_margin_left = 6
	lb.content_margin_right = 6
	return lb

## 크림 확인 창: 두꺼운 외곽선 + 보라 체크무늬 머리띠(header_h > 0일 때).
static func cream_card(radius := 26, header_h := 0.0) -> StyleBox:
	if not tt():
		return flat(Color("fff4e0"), 28, 6, CLASSIC_INK)
	var lb := Layered.new()
	lb.add(flat(INK, radius + 2, 0), Vector4(4, 4, 4, 10))     # 바깥 그림자 턱
	lb.add(flat(CREAM, radius, 6), Vector4.ZERO)
	if header_h > 0.0:
		lb.header_h = header_h
		lb.header_radius = radius
	return lb

## 어두운 정보 창(용과구리 설명창): 검정 → 보라 테두리 → 청록 선 → 남보라 본문.
static func night_card(radius := 28) -> StyleBox:
	if not tt():
		return flat(Color("fff4e0"), 28, 6, CLASSIC_INK)
	var lb := Layered.new()
	lb.add(flat(INK, radius + 2, 0), Vector4(4, 4, 4, 10))
	lb.add(flat(FRAME, radius, 5), Vector4.ZERO)
	var hl := flat(Color(0, 0, 0, 0), radius - 4, 0)
	hl.border_width_top = 4
	hl.border_color = FRAME_HI
	lb.add(hl, Vector4(-5, -5, -5, -5))
	lb.add(flat(FRAME_LINE, radius - 10, 3), Vector4(-12, -12, -12, -12))
	lb.add(flat(BODY, radius - 14, 0), Vector4(-18, -18, -18, -18))
	return lb

## 하단 덱/가방 패널: 검정 외곽선 + 진한 자두색 머리줄 + 남보라 본문.
static func deck_panel(radius := 24, header_h := 46.0) -> StyleBox:
	if not tt():
		return flat(Color(0.1, 0.08, 0.2, 0.55), radius, 0)
	var lb := Layered.new()
	lb.add(flat(Color(INK, 0.9), radius + 2, 0), Vector4(3, 3, 3, 3))
	lb.add(flat(Color(NIGHT, 0.94), radius, 0), Vector4.ZERO)
	var head := flat(Color(PLUM, 0.96), radius, 0)
	head.corner_radius_bottom_left = 0
	head.corner_radius_bottom_right = 0
	lb.add(head, Vector4.ZERO, header_h / 214.0)
	return lb

## 빈 칸(가방·덱): 패인 듯 어두운 칸.
static func empty_slot(radius := 14) -> StyleBoxFlat:
	if not tt():
		return flat(Color(1, 1, 1, 0.08), radius, 3, Color(1, 1, 1, 0.18))
	var sb := flat(Color(NIGHT_DEEP, 0.95), radius, 3, Color(INK, 0.9))
	return sb

## HUD 알약: 반투명 남보라 + 검정 외곽선.
static func capsule(radius := 22, alpha := 0.88, classic_alpha := 0.5) -> StyleBoxFlat:
	if not tt():
		return flat(Color(0.1, 0.08, 0.2, classic_alpha), radius, 0)
	var sb := flat(Color(NIGHT, alpha), radius, 3, INK)
	return sb

## 여러 StyleBoxFlat을 바깥 여백(grow)만큼 늘리거나 줄여 순서대로 그리는 스타일.
## grow = (왼, 위, 오른, 아래) 픽셀, 음수면 안쪽으로. frac < 1이면 그 층은 위에서부터 높이의 frac만 쓴다.
class Layered extends StyleBox:
	var layers: Array = []
	var header_h := 0.0
	var header_radius := 26
	var _header_sb: StyleBoxFlat   # built on first draw, then reused (no allocation per redraw)

	func add(sb: StyleBox, grow: Vector4, frac := 1.0) -> void:
		layers.append([sb, grow, frac])

	func _draw(ci: RID, rect: Rect2) -> void:
		for l in layers:
			var sb: StyleBox = l[0]
			var g: Vector4 = l[1]
			var r := Rect2(rect.position - Vector2(g.x, g.y), rect.size + Vector2(g.x + g.z, g.y + g.w))
			if l[2] < 1.0:
				r.size.y = r.size.y * l[2]
			if r.size.x > 1.0 and r.size.y > 1.0:
				sb.draw(ci, r)
		if header_h > 0.0:
			_draw_header(ci, rect)

	## 보라 머리띠 + 큰 체크무늬 + 아래 검정 선(창 윗부분, 외곽선 안쪽).
	func _draw_header(ci: RID, rect: Rect2) -> void:
		var b := 6.0
		var hr := Rect2(rect.position + Vector2(b, b), Vector2(rect.size.x - b * 2.0, header_h - b))
		var cr := maxi(header_radius - 6, 2)
		if _header_sb == null:
			_header_sb = StyleBoxFlat.new()
			_header_sb.bg_color = HEADER
			_header_sb.anti_aliasing = true
			_header_sb.corner_radius_top_left = cr
			_header_sb.corner_radius_top_right = cr
		_header_sb.draw(ci, hr)
		var s := hr.size.y * 0.5
		var cols := int(ceil(hr.size.x / s))
		for row in 2:
			for col in cols:
				if (row + col) % 2 == 1:
					continue
				var x0 := hr.position.x + col * s
				var x1 := minf(x0 + s, hr.end.x)
				if row == 0:   # 둥근 모서리 밖으로 삐지지 않게
					x0 = maxf(x0, hr.position.x + cr)
					x1 = minf(x1, hr.end.x - cr)
				if x1 <= x0:
					continue
				RenderingServer.canvas_item_add_rect(ci, Rect2(x0, hr.position.y + row * s, x1 - x0, s), HEADER_CHECK)
		RenderingServer.canvas_item_add_rect(ci, Rect2(hr.position.x, hr.end.y - 1.0, hr.size.x, 5.0), INK)


static func hp_col() -> Color:
	return HP if tt() else Color("6fdc6a")

## 유닛 머리 위 바 채움색: 뚜까펫은 아군 연두 / 적 빨강, 클래식은 진영색.
static func unit_bar(hero: bool) -> Color:
	if tt():
		return HP if hero else HP_ENEMY
	return Defs.COL_HERO if hero else Defs.COL_ENEMY

static func trail_col() -> Color:
	return BAR_TRAIL if tt() else Color("fff4e0")

## 크림 창 안쪽 칸.
static func inset() -> Color:
	return Color(INSET, 0.8) if tt() else Color(0.1, 0.08, 0.2, 0.07)
