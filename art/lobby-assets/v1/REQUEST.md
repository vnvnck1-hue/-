# Codex request: 토이 캠프 로비 아이콘 12종 + 원경 배경 1장

로비 개편(`docs/handoffs/2026-10-23-lobby-toy-camp-claude.md`)에 쓸 런타임 자산을 내장 이미지 생성 도구(image_gen)로 만들어 주세요.
기준 화면: `art/ui-concepts/2026-10-23-lobby/a-toy-camp.png` (이 이미지의 아이콘·배경 화풍을 그대로 따른다).

게임 코드는 아래 파일명이 `godot/art/lobby/`에 있으면 자동으로 사용하고, 없으면 코드로 그린 임시 아이콘을 씁니다.
그러니 **파일명을 정확히 지켜 주세요.**

## A. 아이콘 12종 (각각 투명 PNG, 1024×1024)

### 공통 프롬프트

Use case: stylized-concept
Asset type: individual transparent PNG UI icon for a bright cozy casual mobile fantasy game lobby, matching the supplied concept screen's icons (top currency icons, mission/attendance buttons, bottom navigation icons).
Style: soft 3D toy render, glossy rounded clay/vinyl materials, gentle studio lighting from the upper left, soft internal shading and a small specular highlight. **No black outlines**, no thick dark strokes. Saturated but soft colours. Chunky simplified silhouette readable at 48–72 px.
Composition: exactly ONE object centered in a square canvas, filling roughly 80% of the canvas with transparent padding. All parts fully inside the canvas. Front or slight three-quarter view.
Backdrop: genuinely transparent alpha. No ground, no cast shadow plate, no card, no frame, no circle background, no text, no letters or numbers, no watermark, no glow halo outside the object.
Input images are style references only.

### 파일 목록

| 파일명 | 대상 |
|---|---|
| `coin.png` | 금색 동전 1개, 정면, 두툼한 테두리와 가운데 홈(열쇠 구멍 모양 또는 세로 홈) |
| `stone.png` | 파란 면이 있는 보석(강화석), 육각/둥근 컷, 밝은 하늘색~파랑 |
| `crystal.png` | 세로로 긴 보라 결정 1개(시간의 결정), 다이아 모양 패싯 |
| `gear.png` | 흰색 톱니바퀴 1개 (설정 버튼 위에 올라감, 둥근 이빨 8개, 가운데 구멍) |
| `mission.png` | 남색 클립보드 + 흰 종이 + 큰 초록 체크 표시 |
| `attend.png` | 탁상 달력: 빨간 상단 바인딩과 링, 흰 페이지, 주황/빨강 체크 표시 (숫자 없음) |
| `nav_gear.png` | 은색 칼날 짧은 검 + 그 앞의 작은 파란 둥근 방패 (장비 메뉴) |
| `nav_relic.png` | 회색 돌 원형 받침 위에 떠 있는 보라 수정 (유물 메뉴) |
| `nav_camp.png` | 둥근 돌 테두리 + 장작 + 주황·노랑 불꽃의 모닥불 (캠프 메뉴) |
| `nav_raid.png` | X자로 교차한 은색 검 두 자루, 갈색 손잡이 (도전 메뉴) |
| `nav_growth.png` | 둥근 초록 잎 뭉치의 작은 나무/새싹, 갈색 줄기 (성장 메뉴) |
| `map.png` | 흰색 접힌 지도 실루엣(3단 접힘), 단색 흰색 + 아주 옅은 음영 (청록 탭 위에 올라감) |


## B. 원경 배경 1장

파일명: `backdrop.png` — **불투명** PNG, 세로 1024×1536 (또는 그 이상, 2:3 비율).

프롬프트:

Use case: game background layer
Asset type: distant scenery backdrop for a 3D mobile game lobby; the 3D characters, campfire, trees and grass plateau are rendered separately IN FRONT of this image, so it must contain ONLY far-away scenery.
Style: same soft painterly 3D toy look as the supplied concept, bright sunny day, soft atmospheric perspective (distant things paler and bluer, lower contrast).
Content from top to bottom: soft blue sky gradient (#8FDDF7 at the top to #C6F0FC near the horizon) with a few soft white rounded clouds in the upper half; in the middle band (roughly 45%–75% of the height) green cliffs and plateaus with a blue river/lake and a small waterfall, a stone arch bridge, a distant fairytale castle with blue and red cone roofs on a hill on the right-centre side, small round trees on the cliffs. The bottom 25% is soft out-of-focus green meadow/treetops fading slightly (it will be covered by the 3D grass plateau).
Must NOT contain: characters, campfire, chest, foreground trees, UI, text, logo, buttons, frames, vignette.
Camera: eye-level, gently looking out over the valley, horizon at about 55% of the image height.

## 완료 후

- 최종 이미지를 이 폴더(`art/lobby-assets/v1/`)에 위 파일명으로 저장하고, **같은 파일을 `godot/art/lobby/`에도 복사**해 주세요(이 두 폴더 밖은 건드리지 않기).
- 이 폴더에 `generation-manifest.json` 작성 (`art/skillbook-icons/v1/generation-manifest.json`과 같은 형식).
- 아이콘 12종은 실제 투명 배경인지(모서리 픽셀 alpha 0) 확인해 결과를 보고해 주세요. `backdrop.png`는 불투명이어야 합니다.
