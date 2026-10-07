# 캐릭터 이동·동선 기능명세서 (이식용)

**대상 프로젝트:** autobattler-mvp  
**목적:** 다른 게임/엔진에 동일 패턴을 이식할 때 참고할 수 있는 **기능·데이터·알고리즘** 정리  
**주요 소스:** `src/entities/Entity.ts`, `Hero.ts`, `Enemy.ts`, `Heroes.ts`, `core/Types.ts` (전투 영역 상수)

---

## 1. 범위 및 용어

| 용어 | 정의 |
|------|------|
| **유닛** | 영웅(`Hero`) 또는 적(`Enemy`), 공통 기반 `Entity` |
| **월드 좌표** | 2D 평면 `pos = (x, y)` (논리 해상도 기준) |
| **의도 속도 `vel`** | 매 틱 재계산되는 이동 방향·크기. 틱 끝에 **0으로 리셋** |
| **넉백 `knockback`** | 피격 시 누적되는 별도 속도, 시간에 따라 지수 감쇠 |
| **전투 영역** | `BATTLE_LEFT` ~ `BATTLE_RIGHT`, `BATTLE_TOP+8` ~ `BATTLE_BOTTOM-8` 내로 **클램프** |
| **동선** | 타깃 선정 → `vel` 결정 → `vel+knockback` 적분 → 경계 클램프의 결과 궤적 |

발사체(`Projectile`)·픽업(`Pickup`) 이동은 본 문서 **범위 외**.

---

## 2. 공통 물리 모델 (`Entity`)

### 2.1 상태 변수

| 필드 | 타입 | 설명 |
|------|------|------|
| `pos` | `Vec2` | 월드 위치 |
| `vel` | `Vec2` | 이번 프레임 의도 속도 (단위: 월드/초) |
| `knockback` | `Vec2` | 피격 등으로 가산되는 속도 |
| `radius` | `number` | 충돌·표시 반경 (영웅 기본 11, 종별 상이) |
| `alive` | `boolean` | 사망 시 `update`에서 이동 로직 스킵 |

### 2.2 피격과 넉백

- `takeDamage(amount, fromDir?, knockbackMul?)` 호출 시:
  - `knockback`에 `fromDir` 정규화 방향 × `60 * knockbackMul` 가산.
- `baseUpdate(dt)`:
  - `knockback *= max(0, 1 - dt * 8)` (지수 감쇠, 프레임마다 감소)

### 2.3 통합 적분 (영웅·적 공통 패턴)

매 `update` 말미:

```
pos += (vel + knockback) * dt
pos.x = clamp(pos.x, BATTLE_LEFT, BATTLE_RIGHT)
pos.y = clamp(pos.y, BATTLE_TOP + 8, BATTLE_BOTTOM - 8)
vel.x = 0; vel.y = 0
```

**명세 포인트:** 가속도 적분이 아니라 **매 틱 `vel`을 새로 쓰는 키네마틱**에 가깝다. 관성 없음.

---

## 3. 좌표계 및 스폰 (동선 초기조건)

### 3.1 전투 영역 상수 (`Types.ts`)

- `VIEW_W`, `VIEW_H`: 논리 뷰 크기  
- `BATTLE_TOP`, `BATTLE_BOTTOM`, `BATTLE_LEFT`, `BATTLE_RIGHT`: 유닛이 클램프되는 사각형 (상·하단 UI 여백 반영)

### 3.2 파티 스폰 (`Heroes.createParty`)

| 영웅 | 초기 `pos` | `setHome` (닻 좌표) |
|------|------------|---------------------|
| 전사 | `(cx, yBottom - 10)` | 동일 |
| 궁수 | `(cx - 60, yBottom)` | 동일 |
| 마법사 | `(cx + 60, yBottom)` | 동일 |

- `cx = (BATTLE_LEFT + BATTLE_RIGHT) / 2`  
- `yBottom = BATTLE_BOTTOM - 30`

**명세 포인트:** 스폰과 별도로 **홈 좌표**를 저장해 이후 `applyAnchoring`에서 사용.

---

## 4. 영웅 (`Hero`) 이동 파이프라인

### 4.1 `update` 처리 순서 (고정)

1. `baseUpdate(dt)` — 플래시·스쿼시·넉백 감쇠  
2. 생존하지 않으면 return  
3. `pickupTweenT` 감소 (이동과 무관, 표현용)  
4. `maxHp` 버프 동기화  
5. `target = findTarget(state)`  
6. `attackCooldown -= dt`  
7. **타깃 있으면** `moveToward(target, dt)`  
8. **`applyAnchoring(state)`** — `vel`에 가속도 벡터 **가산**  
9. 공격 판정·실행  
10. 위치 적분 + 클램프 + `vel` 리셋  

### 4.2 타깃 선정 `findTarget`

- 대상 풀: 살아 있는 모든 `Enemy`  
- 기본 점수: `score = 거리 d`  
- **마법사만:** 후보 적 `e`에 대해 반경 36 내 다른 적 수 `cluster`를 세고  
  `score = d - cluster * 10` (밀집할수록 우선)  
- 최소 `score`인 적 1체 선택  

**명세 포인트:** 동선은 “가장 가까운 적”이 아니라 클래스별 **가중 거리**로 바뀔 수 있음.

### 4.3 이동 규칙 `moveToward` (클래스별)

공통 입력: 타깃까지 벡터 `(dx, dy)`, `dist = hypot(dx,dy)||1`, 정규화 `(dx/dist, dy/dist)`.

| 클래스 | 조건 | `vel` (요약) |
|--------|------|----------------|
| **전사** | `dist > attackRange - 2` | 목표 방향 × `moveSpeed` |
| **전사** | 그 외 | 0 (추적 안 함, 사거리 내 정지) |
| **궁수** | `dist < preferredDistance - 8` | **반대 방향** × `moveSpeed` (후퇴) |
| **궁수** | `dist > preferredDistance + 8` | 목표 방향 × `moveSpeed * 0.6` (느린 접근) |
| **궁수** | 그 사이 | `vel.y = sin(time*0.003 + id) * 12`, x는 0 근처 (미세 위빙) |
| **마법사** | `dist < preferredDistance - 10` | x: 반대 × `moveSpeed` |
| **마법사** | `dist > preferredDistance + 30` | x: 목표 × `moveSpeed * 0.4` |
| **마법사** | (항상) y | `targetY = BATTLE_BOTTOM - 30` 을 향해 `sign(dyHome) * min(moveSpeed*0.5, abs(dyHome)*4)` |

**설정값 (`HeroConfig`):**

| | attackRange | preferredDistance | moveSpeed |
|---|-------------|-------------------|-----------|
| 전사 | 28 | 0 | 140 |
| 궁수 | 160 | 130 | 150 |
| 마법사 | 180 | 170 | 120 |

### 4.4 앵커링 `applyAnchoring` (스티어링 합성)

`moveToward` 이후 `vel`에 **누적 가속** `ax, ay`를 더함. `cap = moveSpeed`.

| 힘 | 조건 | 기여 |
|----|------|------|
| **홈 시크** | 홈까지 거리 `hd > 8` | `(home - pos)` 방향, 크기 `min(cap*0.32, hd*0.9)` |
| **좌 벽 반발** | `pos.x < BATTLE_LEFT + 40` | +x, `push * t²`, `push = cap*0.42`, `t`는 margin 내 침입 비율 |
| **우·상·하** | 대칭 | 동일 패턴으로 안쪽 밀기 |
| **아군 분리** | 다른 살아 있는 영웅과 거리 `< 30` | 상대 반대 방향으로 `cap*0.26*w²`, `w=1-d/sepR` |
| **속도 캡** | `hypot(vel) > cap*1.2` | 벡터를 `cap*1.2`로 스케일 |

**명세 포인트:** 추적/키팅만 쓰면 구석 고착이 생기므로 **홈 + 경계 + 분리**를 같은 틱에 합성.

### 4.5 공격과 이동의 결합

- `canAttackNow`: `attackCooldown <= 0` 이고 `dist <= attackRange + 4`  
- 이동은 **공격 가능 여부와 독립**으로 매 틱 계산 (사거리 밖이면 계속 접근).

---

## 5. 적 (`Enemy`) 이동 파이프라인

### 5.1 특수 상태: 보스 텔레그래프

- `isBoss` 이고 HP 비율에 따라 `telegraphKind` 가 `slam` / `dash` 로 설정되면:
  - 일반 이동·공격 **스킵**
  - `telegraphT` 카운트다운, 대시 예고 시 매 프레임 가장 가까운 영웅 위치로 예고선 갱신
  - 종료 시 `executeBossTelegraph`: 광역 또는 **위치 스냅 대시** + 근접 피해
  - 이 동안에도 `knockback`만 `pos`에 반영 가능

### 5.2 일반 루프

1. `baseUpdate`  
2. 보스 텔레그래프 중이면 조기 return  
3. `target = findHeroTarget(state)`  
4. `attackCooldown -= dt`  
5. **샤먼:** `healCooldown`로 주기적 아군 힐 (이동과 별개)  
6. 타깃 있으면 거리 `d`로 **종별 `vel` 분기**  
7. 사거리 내이면 원거리/근접에 따라 `attack`  
8. 적분·클램프·`vel` 리셋  

### 5.3 타깃 선정 `findHeroTarget`

| 종류 | 규칙 |
|------|------|
| **brute** | 거리 220 이내 **궁수·마법사** 중 최단거리. 없으면 전체 중 최단거리 |
| **그 외** | 살아 있는 영웅 중 **유클리드 최단거리** 1명 |

### 5.4 종별 이동 (`vel`)

| 종류 | 이동 로직 |
|------|-----------|
| **charger + 돌진 중** (`chargeBurstT > 0`) | 목표 방향 × `moveSpeed * 2.35` |
| **charger 평시** | `chargeCd` 만료 시 `38 < d < 210` 이면 `chargeBurstT = 0.32` 시작. 평소는 `d > attackRange-2` 일 때만 추적 속도 |
| **goblinArcher, shaman** | `d < preferredDistance - 6` 후퇴; `d > preferredDistance + 6` 접근(계수 0.65); 샤먼은 y 후퇴에 `0.55` |
| **근접형** (고블린, 오크, brute 등) | `d > attackRange - 2` 일 때만 목표 방향 × `moveSpeed` |

`EnemyConfig`에 `attackRange`, `preferredDistance`, `moveSpeed`가 종마다 정의됨.

### 5.5 보스 대시 (위치 기반 동선)

- 텔레그래프 종료 후: 최근접 영웅 방향 단위벡터 × 고정 거리 `72` 만큼 `pos` **즉시 이동** (연속 속도가 아닌 점프)

---

## 6. 데이터 의존성 (이식 시 매핑표)

| 개념 | 영웅 | 적 |
|------|------|-----|
| 최대 이동속도 | `HeroConfig.moveSpeed` | `EnemyConfig.moveSpeed` × (돌진 배율 등) |
| 사거리 기반 정지 | `attackRange - 2` | 동일 |
| 원거리 키팅 밴드 | `preferredDistance ± 8` | 궁수/샤먼: `± 6` |
| 전투 경계 | `Types` 상수 + 영웅 y 여유 8 | 동일 |
| 타깃 가중 | 마법사만 클러스터 | brute만 클래스 필터 |

---

## 7. 이식 시 체크리스트

1. **틱 순서 고정:** `의도 이동 → (선택) 보정력 가산 → 적분 → 클램프 → vel 초기화`  
2. **원거리:** 반드시 **히스테리시스 밴드** (두 임계값)로 진동 방지  
3. **근접:** `attackRange - ε` 로 “붙은 채 정지” 구간 명시  
4. **넉백:** `vel`과 분리 감쇠 — 합산 순서 문서화  
5. **다중 아군:** separation 또는 슬롯 할당  
6. **맵:** AABB 클램프 + (선택) 가장자리 반발 필드  
7. **보스 특수 이동:** 연속 속도 vs **pos 스냅** 구분 설계  

---

## 8. 소스 파일 인덱스

| 파일 | 책임 |
|------|------|
| `Entity.ts` | `pos`, `vel`, `knockback`, `baseUpdate`, 피격 넉백 |
| `Hero.ts` | `update` 파이프라인, `findTarget`, `moveToward`, `applyAnchoring`, 공격 사거리 `+4` |
| `Heroes.ts` | 스폰 좌표, `setHome` |
| `Enemy.ts` | 적 이동 분기, `findHeroTarget`, 보스 텔레그래프·대시, 샤먼/차저 |
| `Types.ts` | `BATTLE_*`, `VIEW_*` |

---

**문서 버전:** 저장소 현재 구현 기준. 수치·분기 변경 시 본 명세의 표와 함께 코드를 갱신할 것.
