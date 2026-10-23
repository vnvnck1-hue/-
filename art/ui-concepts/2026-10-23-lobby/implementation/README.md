# 토이 캠프 로비 구현 기록 · 2026-10-23

기준: [a-toy-camp.png](../a-toy-camp.png) · 명세: [docs/handoffs/2026-10-23-lobby-toy-camp-claude.md](../../../../docs/handoffs/2026-10-23-lobby-toy-camp-claude.md)

## 변경 파일

| 파일 | 내용 |
|---|---|
| `godot/scripts/lobby.gd` | 데이터·흐름만 남김. 옛 카드·좌우 버튼·프리셋 버튼·종료 안내·로비 대사 제거. View 신호를 기존 열기 함수에 연결, `_snapshot()`으로 Meta 값 전달, 1초마다 모닥불 상태 갱신. `_open_settings`에 다른 창 열림 가드 추가. 개발용 `--lobby-states` 캡처 추가 |
| `godot/scripts/lobby_view.gd` (신규) | 재화 3종·설정·미션/출석·보상 알약·원정 시트(탭, 챕터 줄, 목표, 출발, 끝없는 행군)·하단 5메뉴. 안전 영역, 위/아래 그룹 고정, 숫자 축약, 긴 챕터명 축소·줄바꿈, 비활성 화살표, 눌림 연출 |
| `godot/scripts/lobby_camp_stage.gd` (신규) | 로비 전용 3D 캠프: 하늘·원경(절벽·물길·폭포·다리·성)·고원·소나무·수정·바위·그루터기·꽃·버섯·풀, 모닥불(불씨 포함), 상자, 로비 전용 영웅 3명(`LobbyHero`), 카메라(세로로 긴 화면은 v_offset, 넓은 화면은 KEEP_HEIGHT) |
| `godot/scripts/lobby_style.gd` (신규) | 로비 전용 팔레트·번들 폰트(Noto Sans KR / Lilita One)·StyleBox·아이콘 로더. `res://art/lobby/<이름>.png`가 있으면 그 PNG, 없으면 코드로 그린 대체 아이콘 |
| `godot/tools/lobby_probe.gd` (신규) | 헤드리스 연결 검증 |
| `TrioChess.exe` | 재빌드 |

## 캡처 (Windows Forward+, 540×960 창 = 720×1280 논리)

- `windows-home/lobby.png`: 실제 exe, 테스트 저장
- `windows-home/state_big_last.png`: 123.5M / 987,654 / 0, 마지막 열린 챕터(오른쪽 화살표 비활성), 2회차 이름
- `windows-home/state_cleared_empty.png`: 클리어한 챕터(`클리어 완료`), 모닥불 0 → `보상 쌓는 중`, 빨간 점 없음
- `windows-home/state_first_full.png`: 첫 챕터(왼쪽 화살표 비활성), 재화 0, 모닥불 가득 → 빨간 점
- `windows-home/state_long_name.png`: 긴 챕터명 축소 + 두 줄
- `windows-home/compare_concept_vs_game.png`: 컨셉과 나란히 비교

추가로 확인한 화면 비율(스크래치 캡처): 360×640, 480×1040(9:19.5), 900×960(넓은 화면), Compatibility 렌더러(`--rendering-method gl_compatibility`, Web 경로 근사).

## 검증 결과

`Godot --headless --path . -s res://tools/lobby_probe.gd` → **ALL OK**

- 자동 출석 열림, 닫힘 후 조용한 재로딩
- HUD 값 = Meta 값, 숫자 형식(0 / 47,769 / 999,999 / 1.23M / 123.5M)
- 챕터 0..cleared 범위, 양 끝 화살표 비활성, 비활성 화살표 무반응
- 장비·유물·상자(CampScreen)·도전(RaidScreen)·성장(TalentScreen)·미션·출석: 열림, 열린 동안 View 차단·설정/출발 차단, 닫으면 재로딩
- 캠프 탭: 아무 창도 열지 않음
- 설정 열림 중 `_go` 거부
- 출발 2연타 → 한 번만 이동, `Meta.expedition = true`, 일일 미션 `run` 1회만 증가, March 씬 진입
- 끝없는 행군 → `Meta.expedition = false`, `Meta.raid = ""`

기존 개발 캡처 `--open=daily`, `--open=raid`, `--open=mission`, `--open=settings` 동작 확인. (`--open=settings`와 `--open=daily`를 한 번에 주면 설정 창이 열린 채라 모닥불 창이 열리지 않음 — 변경 전과 같은 기존 제약)

## 컨셉 대비 남은 차이

1. **아이콘·원경 품질**: 지금은 코드로 그린 대체 아이콘과 기본 도형 원경이다. 장비 아이콘(검+방패)이 특히 약하다. Codex에 [아이콘 12종 + 원경 요청서](../../../lobby-assets/v1/REQUEST.md)를 작성해 두었다. 결과 PNG가 `godot/art/lobby/`에 들어오면 코드 수정 없이 자동 적용된다(임포트 후 exe 재빌드 필요).
2. 컨셉의 `TRIO CHESS` 로고는 명세(상단 HUD = 재화+설정)에 없어 넣지 않았다.
3. 영웅은 기본 도형 조합이라 컨셉의 매끈한 조형·옷 주름 수준은 아니다. 얼굴·소품·색 정체성은 맞춘다.
4. 고원 앞 절벽 단면(컨셉의 시트 위 흙 단면)은 시트에 거의 가려져 생략했다.
5. Web: 실제 Web 빌드는 하지 않았다. Compatibility 렌더러 데스크톱 캡처로 하늘 밝기만 보정(`SKY_COMPAT`). 새 로비 재질은 `warmup_shaders` 목록에 아직 없어서 Web 첫 진입 셰이더 컴파일 시간은 측정하지 않았다.
