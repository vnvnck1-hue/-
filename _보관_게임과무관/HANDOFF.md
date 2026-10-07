## Handoff (2026-04-30)

이 폴더는 단일 HTML 프로토타입을 **Vite + React 개발환경**으로 옮기는 작업 중 산출물입니다.
현재는 “로직 변경 최소화”를 위해, Vite 앱이 기존 단일 HTML을 **`iframe`으로 그대로 로드**합니다.

### 실행
- `run-dev.cmd` 더블클릭: dev 서버 실행 + 브라우저 오픈
- `run-preview.cmd` 더블클릭: build 후 preview 실행 + 브라우저 오픈

> Node.js/npm이 설치되어 있어야 합니다.

### 핵심 파일
- `defense_attack_visuals_bugfix_wave_exp_startlock.html`: 원본 게임(단일 HTML)
- `index.html`, `src/main.jsx`, `src/App.jsx`: Vite 엔트리
  - `src/App.jsx`에서 `iframe`으로 원본 HTML을 띄움
- `src/styles/`: 토큰/리셋/베이스 CSS 분리
- `public/assets/`: 에셋 폴더 스켈레톤(`icons/images/sfx`)
- `src/effects/`, `src/animations/`, `src/components/`: 분리 목적지(스켈레톤)

### 최근 실험 변경(게임 밸런스)
원본 HTML에서 유닛 기본 속도를 “3배 빠르게” 보이도록 변경했습니다.
- 위치: `defense_attack_visuals_bugfix_wave_exp_startlock.html`의 `UNIT_TYPES`
- 이 게임 구조상 `speed/moveSpeed` 값이 **작을수록 빨라지는 간격(ms)** 이라서, 3배 빠르게 = 기존값을 `/ 3` 처리

### 실시간 전투 리팩터링 진행 상황
목표: 적/이펙트가 많아져도 “턴제처럼 뭉개지는 느낌”을 줄이기.

#### 1) setInterval → requestAnimationFrame + fixed timestep
- 전투 루프를 `setInterval` 대신 `requestAnimationFrame` 기반으로 변경
- `simNowRef`(시뮬레이션 시간) + 고정 스텝(`STEP_MS`) 누적 처리

#### 2) 시뮬레이션(Ref) ↔ 렌더(State) 분리 (부분 적용)
- tick에서 `setUnits/setEnemies`를 매 스텝 호출하던 것을 줄이기 위해
  - tick에서는 `unitsRef.current`, `enemiesRef.current` 중심으로 갱신
  - RAF에서 프레임당 1회 `setUnits(unitsRef.current)`, `setEnemies(enemiesRef.current)` 커밋

#### 3) 비동기 전투 이벤트의 setState 난사 완화 (부분 적용)
- `simDirtyRef`(더티 플래그) 추가: 비동기에서 시뮬레이션 ref가 바뀌면 다음 RAF에서 1회 커밋
- `updateUnitsSim`, `updateEnemiesSim` 헬퍼 추가
- `fireProjectile()` 내부의 일부 `setUnits/setEnemies`를 `updateUnitsSim/updateEnemiesSim`로 치환
- 하이드라 처리 일부도 `updateEnemiesSim`로 치환

### 아직 남은 문제(다음 작업자가 보면 좋은 포인트)
전투가 시작되면 여전히 “턴제처럼 버벅” 체감이 남습니다. 원인 후보:
- `executeActiveSkill()` / `executeUltimate()` / 각종 `setTimeout` 콜백 내부에 `setUnits/setEnemies`가 여전히 많음
- 이펙트가 DOM 노드로 많이 생성되어 렌더 비용이 급증할 수 있음
- “캐치업 없음”: 프레임이 밀렸을 때 공격/이동이 시간만큼 따라잡지 못하고 1회만 처리되는 구조

### 다음 권장 스텝(우선순위)
1. 전투 중 `setUnits/setEnemies` 호출을 전부 제거하고(특히 `executeActiveSkill/executeUltimate`),
   시뮬레이션 ref에만 반영 후 RAF에서 1회 커밋으로 통일
2. 캐치업 처리(while로 공격/이동 여러 번 처리하되 상한선 둠) 도입 검토
3. 이펙트 렌더링 최적화(DOM 이펙트 수 제한 또는 별도 레이어로 분리) 검토

