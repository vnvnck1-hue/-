# Grid Defense Game — 에이전트 작업 내역 (2026-05-18)

대상 파일: `GridDefenseGame_standalone.html`  
작성 목적: 파일이 깨졌을 때 다른 환경에서 수동 복구할 수 있도록, 이 대화에서 적용한 변경을 기록합니다.

---

## 요약

| # | 기능 | 상태 (문서 작성 시점) |
|---|------|----------------------|
| 1 | 튜토리얼 손가락(👆) 힌트 | 파일에 반영됨 |
| 2 | 자동시작 ON 시 특성 룰렛 애니메이션 | 파일에 반영됨 |
| 3 | 전사 궁극기 50% 너프 | 파일에 반영됨 |
| 4 | 자동시작 버튼 마우스오버 툴팁 | 파일에 반영됨 |
| 5 | 상단 「시간의 결정」 HUD 마우스오버 툴팁 | 파일에 반영됨 |
| 6 | 튜토리얼 5단계 완료 후 40스테이지 공략 팝업 (1회) | 파일에 반영됨 |

---

## 1. 튜토리얼 손가락 힌트

### 추가 컴포넌트
- `TutorialFingerHint` — 약 **895행** (`TutorialOverlay` 근처)
- CSS: `@keyframes tutFingerBounce` — `<style>` head 또는 인라인 style 블록

### 연동 위치
- `GridBattleEntities`: `tutorialMovedUnitIds` prop — 1단계에서 유닛 이동 시 해당 유닛 손가락 제거
- 전투 시작 버튼, 스킬 UP 버튼, 인벤 장비(5단계) 등에 `<TutorialFingerHint show={...} />` 배치
- state: `tutorialMovedUnitIds` (`useState([])`)

### 동작
- 튜토리얼 포커스 UI 위에 👆 표시 (pointer-events 없음)
- 1단계: 유닛별로 한 번 이동하면 그 유닛 손가락만 사라짐

---

## 2. 자동시작 + 특성 룰렛

### state / ref
```javascript
const [perkRouletteHighlightIdx, setPerkRouletteHighlightIdx] = useState(-1);
const [perkRouletteWinnerId, setPerkRouletteWinnerId] = useState(null);
const perkRouletteTimersRef = useRef([]);
const perkRouletteRunIdRef = useRef(0);
```

### useEffect (약 4103~4152행)
- 조건: `autoStartBattle && !isTutorialLocked && perkSelection`
- 카드 인덱스를 빠르게 순환 → 감속 → `selectPerk(winnerId)` 호출
- `runId`로 이전 타이머와 충돌 방지

### UI (perkSelection 모달, 약 4601행~)
- `isPerkAutoRoulette = autoStartBattle && !isTutorialLocked && !!perkSelection`
- 룰렛 중: `perkRoulettePick` / `perkRouletteWin` 애니만 사용 (deal-in 애니와 겹치면 깜빡임)
- 자동 룰렛 중 카드 클릭 비활성, 상단 ▼ 표시

---

## 3. 전사 궁극기 너프 (50%)

`ULTIMATES.warrior` (약 **472행**):

| 항목 | 변경 전 | 변경 후 |
|------|---------|---------|
| damageMultiplier | 2.0 | **1.0** |
| stunDuration | 1000 | **500** |
| shockwave spawnHit intensity | 1.45 | **0.72** (executeUltimate 내부) |

---

## 4~6. 툴팁 + 공략 팝업 (최신 작업 — 상세)

### 4-A. 공용 컴포넌트 `HoverInfoTooltip` (약 791~822행)

`TutorialFingerHint` **바로 위**에 삽입.

```javascript
function HoverInfoTooltip({ tip }) {
    if (!tip) return null;
    const w = tip.width || 300;
    return (
        <motion style={{
            position: 'fixed',
            left: Math.min(tip.x + 14, (typeof window !== 'undefined' ? window.innerWidth : 1200) - w - 10),
            top: Math.max(10, tip.y + 8),
            width: w,
            background: 'rgba(8,8,24,0.98)',
            border: `2px solid ${tip.borderColor || 'rgba(147,197,253,0.5)'}`,
            borderRadius: 12,
            padding: '12px 14px',
            zIndex: 5950,
            color: '#fff',
            pointerEvents: 'none',
            boxShadow: '0 16px 40px rgba(0,0,0,0.65)',
            lineHeight: 1.55,
            fontSize: 11,
        }}>
            {tip.title && (
                <motion style={{ fontWeight: 900, fontSize: 12, color: tip.titleColor || '#93c5fd', marginBottom: 8, borderBottom: '1px solid rgba(255,255,255,0.12)', paddingBottom: 6 }}>
                    {tip.title}
                </motion>
            )}
            {tip.body}
        </motion>
    );
}
```

**tip 객체 형식**
```javascript
{
  x, y,                    // clientX, clientY
  width: 318,              // optional
  title: '🔷 시간의 결정',
  titleColor: '#93c5fd',
  borderColor: 'rgba(...)',
  body: <>...</>,          // JSX
}
```

기존 `buffTip` 패턴과 동일하게 `onMouseEnter` / `onMouseMove` / `onMouseLeave`로 `setHoverInfoTip` 호출.

---

### 4-B. `StrategyGuideModal` (약 824~892행)

`HoverInfoTooltip` 다음, `TutorialFingerHint` 이전에 삽입.

- `open`, `onClose` props
- z-index: **3350**
- 제목: 「🗺️ 40스테이지 공략 요약」
- 본문: 초반 / 중반 / 후반 / 팁 4블록
- 하단 **닫기** 버튼 → `onClose` 호출

---

### 4-C. GridDefenseGame 내부 state / 상수

**상수** (`GridDefenseGame` 시작부, 약 1835행):
```javascript
const STRATEGY_GUIDE_KEY = 'gridDefense_strategyGuideShown_v1';
```

**state** (buffTip 근처, 약 1896~1897행):
```javascript
const [hoverInfoTip, setHoverInfoTip] = useState(null);
const [showStrategyGuide, setShowStrategyGuide] = useState(false);
```

**콜백** (`isTutorialLocked` 다음, 약 2102~2114행):
```javascript
const finishEarlyTutorial = useCallback(() => {
    setTutorialStep(0);
    try {
        if (!localStorage.getItem(STRATEGY_GUIDE_KEY)) setShowStrategyGuide(true);
    } catch (e) {
        setShowStrategyGuide(true);
    }
}, []);

const closeStrategyGuide = useCallback(() => {
    setShowStrategyGuide(false);
    try { localStorage.setItem(STRATEGY_GUIDE_KEY, '1'); } catch (e) {}
}, []);
```

**튜토리얼 완료 트리거** — 기존 `setTutorialStep(0)` 대체:
- `sellItem` (약 2505행): `if (tutorialStepRef.current === 5) finishEarlyTutorial();`
- `equipItem` (약 3306행): 동일

**restartGame** (약 3821행):
```javascript
setShowStrategyGuide(false);
```
추가 (다른 튜토리얼 리셋과 함께).

**렌더** (`GuideModal` 다음, 약 4649~4650행):
```jsx
<StrategyGuideModal open={showStrategyGuide} onClose={closeStrategyGuide} />
<HoverInfoTooltip tip={hoverInfoTip} />
```

---

### 4-D. 상단 「시간의 결정」 HUD (약 4310~4331행)

기존 한 줄 `<div>...</motion>` 을 아래처럼 교체:

- `onMouseEnter` → `setHoverInfoTip({ title: '🔷 시간의 결정', ... body })`
- `onMouseMove` → title이 일치할 때만 x,y 갱신
- `onMouseLeave` → title이 일치할 때만 null
- `cursor: 'help'`, 호버 시 border 강조
- 하단에 `설명 보기` 소문구 추가

**툴팁 본문 요약**
- 역할: 영구 성장 재화, 특성 트리 해금
- 획득: 스테이지 클리어 +2, 적 처치 5%
- 사용: 특성 트리 버튼, 초기화 시 환급

---

### 4-E. 인벤 「자동시작」 버튼 (약 4515~4549행)

- 기존 `title="켜면 스테이지..."` **제거**
- `type="button"` 추가
- 마우스 이벤트로 `title: '⚡ 자동시작'` 툴팁 표시

**툴팁에 적은 자동 기능 목록** (실제 코드와 일치해야 함):

| 자동 처리 | 구현 위치 (대략) |
|-----------|------------------|
| 배치 후 전투 자동 시작 | useEffect ~4091, `startBattleCore(true)` |
| 전투 중 궁극기 자동 시전 | battle loop ~4063, `executeUltimate` |
| 특성 룰렛 후 자동 선택 | useEffect ~4103 |
| 스킬 UP / 장비 착용 / 인벤 장비 판매 | useEffect ~4155 |

튜토리얼 중(`isTutorialLocked`)에는 위 자동 로직이 return으로 막힘.

---

## 자동시작이 실제로 하는 일 (코드 기준)

복구·검증 시 아래 useEffect / 루프를 참고하세요.

1. **전투 자동 시작** — `phase === 'placement'`, 260ms 후 `startBattleCore(true)`
2. **궁극기** — `phase === 'battle'`, 마나 충전 시 가장 가까운 적에게 `executeUltimate`
3. **특성 룰렛** — `perkSelection` 있을 때 단계적 highlight → `selectPerk`
4. **배치·전환** — `upgradeSkill` → `equipItem`(더 좋은 장비) → `sellItem`(인벤 전체 장비 판매) 순 시도

---

## 공략 팝업 본문 (복사용)

**제목:** 🗺️ 40스테이지 공략 요약  
**부제:** 튜토리얼을 마쳤습니다. 아래 흐름을 참고해 도전해 보세요.

**1. 초반 (1~10웨이브)**  
전사 앞줄, 궁수·마법사 뒤쪽. 시간의 결정 → 특성 트리 체력·골드·드롭 우선. 일반 장비 3개 합성.

**2. 중반 (10~25웨이브)**  
10웨이브마다 상점. 특성은 생존+공격 균형. 한 영웅에 장비 집중.

**3. 후반 (25~40웨이브)**  
20웨이브+ 등급별 일괄 판매. 전설·유물로 딜러 육성. 궁극기는 위기 때 수동.

**팁:** 전원 사망 시 게임오버. 10웨이브 상점 부활. 40웨이브 클리어 특별 보상.

---

## localStorage 키

| 키 | 용도 |
|----|------|
| `gridDefense_autoStart_v1` | 자동시작 ON/OFF 저장 |
| `gridDefense_bulkSellTipShown_v1` | 일괄 판매 팁 1회 |
| `gridDefense_strategyGuideShown_v1` | 공략 팝업 1회 (닫기 시 `'1'` 저장) |

공략 팝업을 다시 보려면 DevTools → Application → Local Storage에서 해당 키 삭제.

---

## 복구 시 주의사항

### `<motion>` 태그
이번 작업에서 UI 래퍼에 `<motion>` / `</motion>` 을 사용했습니다.  
프로젝트에 **framer-motion이 없으면** React는 커스텀 HTML 요소 `<motion>`으로 렌더합니다 (동작은 하지만 비표준).

파일이 깨졌거나 JSX 오류가 나면:
- **권장:** 새로 추가한 블록의 `<motion>` → `<div>`, `</motion>` → `</div>` 로 일괄 치환
- 특히 `StrategyGuideModal` 내부에서 `</motion>` / `<div>` 혼용 여부 확인

### JSX 짝 맞추기
`StrategyGuideModal` 작성 중 일시적으로 `<motion>` 여는데 `</motion>` 닫는 실수가 있었음.  
복구 시 모든 블록이 **같은 태그명으로 열고 닫히는지** 확인.

### 검색 키워드 (파일 내 빠른 확인)
```
HoverInfoTooltip
StrategyGuideModal
STRATEGY_GUIDE_KEY
finishEarlyTutorial
hoverInfoTip
⚡ 자동시작
🔷 시간의 결정
```

---

## 테스트 체크리스트

- [ ] 자동시작 버튼 hover → 5~6줄 툴팁 표시
- [ ] 시간의 결정 HUD hover → 역할/획득/사용 표시
- [ ] 배율 HUD hover → 기존 buffTip 정상 (충돌 없음)
- [ ] 튜토리얼 5단계: 장비 착용 또는 판매 후 공략 팝업 1회
- [ ] 팝업 「닫기」 후 새로고침해도 재표시 안 됨
- [ ] `restartGame` 후 공략 팝업 즉시 안 뜸
- [ ] 자동시작 ON + 특성 선택 시 룰렛 후 자동 확정

---

## 변경하지 않은 것

- 게임 밸런스·웨이브 데이터 (전사 너프 제외)
- `GuideModal` (기존 가이드북) 본문
- 특성 트리 노드 정의

---

*문서 끝 — 복구 후 이 파일은 삭제하거나 버전 관리에 포함해도 됩니다.*
