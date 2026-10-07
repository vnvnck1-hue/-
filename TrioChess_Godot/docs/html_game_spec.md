# 트리오 체스(Grid Defense) — HTML 프로토타입 포팅 스펙 (Godot 4 / GDScript)

- 원본: `defense_attack_visuals_bugfix_wave_exp_startlock.html` (2751줄, React 18 + Babel standalone, 단일 파일)
- `GAME_VERSION = 'attack-visual-smooth-mage-delay-2026-04-30'`
- 이 문서는 HTML을 열지 않고도 게임 규칙을 재구현할 수 있게 하는 것을 목표로 한다. 비주얼(색/CSS/애니메이션)은 폐기 대상이므로 §9, §10은 "어떤 정보/피드백이 필요한가"만 기술한다.
- 모든 수치는 코드에서 그대로 옮겼다. `floor`=`Math.floor`, `rand()`=`Math.random()`(0≤r<1).
- 시간 단위는 모두 ms. 거리 `dist`는 **맨해튼 거리** `|ax-bx|+|ay-by|` (그리드 칸 단위).

---

## 0. 핵심 개념 요약

- 6×8 그리드. 플레이어는 영웅 3명(전사/궁수/마법사)을 하단 4줄(y=4..7)에 배치하고 "전투 시작".
- 적은 상단 2줄(y=0..1)에 생성되어 **가장 가까운 영웅을 향해 이동·공격**한다. 경로/골 라인은 없다. "적이 끝에 도달" 개념은 없음.
- 영웅은 자동으로 가장 가까운 적을 향해 이동·공격. 플레이어 개입: 영웅을 0.3초 길게 눌러 궁극기 조준(조준 중 시뮬레이션 일시정지) → 놓으면 발동.
- 적 전멸 → (서브웨이브가 남으면 다음 서브웨이브) → 웨이브 클리어(보상/회복/위치복귀) → 3웨이브마다 특성(퍽) 선택, 10웨이브마다 상인.
- **패배 조건: 전투 중 살아있는 영웅 수 == 0** → 게임오버. 승리 조건 없음(무한). 40웨이브 클리어 시 "커피 획득" 연출만 존재.
- 메타 성장: 시간의 결정(영구 재화)으로 영구 특성 트리 구매, 전설 유물은 런 간 유지(localStorage).

---

## 1. 게임 루프 · 페이즈 · 상태 머신

### 1.1 페이즈 값
`phase ∈ { 'placement', 'spawning', 'battle', 'transition', 'gameover' }` (+ `gameOver` bool)
오버레이(페이즈 아님): `perkSelection`(특성 선택), `merchant`(상인), `skillBookChoice`, 특성 트리 모달, 가이드 모달.

### 1.2 전이

```
placement --(전투 시작 버튼)--> spawning --(마지막 적 등장 +420ms)--> battle
battle --(살아있는 적 0 && 남은 서브웨이브 있음)--> (800ms 후) spawning --> battle
battle --(살아있는 적 0 && 마지막 서브웨이브)--> transition  [finishWave]
battle --(히드라 기믹: 히드라 4마리 동시 사망)--> transition [finishWave]
battle --(영웅 0명)--> gameover
transition --(700ms 후, 상인 웨이브가 아니면)--> placement (wave+1)
transition --(상인 웨이브: clearedWave>=10 && %10==0)--> 상인 오버레이 유지 --(닫기)--> placement (wave+1)
gameover --(다시 시작)--> placement (wave=1, 런 상태 초기화)
```

### 1.3 전투 시작 (`startBattle`) 조건 / 처리
차단 조건(하나라도 해당 시 무시):
- 이벤트가 신뢰된 사용자 클릭이 아님 / 버튼 pointerdown 없이 click / 이전 시작으로부터 600ms 이내 (중복 시작 방지)
- `phase != 'placement'`, 복귀 애니메이션 중(`returningToStart`), 적 생성 중, 웨이브 전환 중
- 튜토리얼이 진행 중이고 단계가 2 또는 4가 아님

처리:
1. 선택 해제, 판매모드 해제, `relicTempoStacks = 0`.
2. 모든 영웅의 현재 좌표를 `startPositions`에 저장(웨이브 종료 후 이 위치로 복귀).
3. 서브웨이브 수: `wave >= 25 → 3`, `wave >= 20 → 2`, 그 외 `1`.
4. 기믹 결정:
   - `wave >= 35 && wave % 5 == 0` → `'giantBoss'`
   - 그 외 `wave >= 3 && rand() < 0.45` → `['hydra','illusionist','goblinRaid','ninjaRaid','splitterRaid','sprinterRaid']` 중 균등 랜덤
   - 그 외 없음
5. 기믹이 있으면 기믹 적을 생성(§4.4). 없으면:
   - 튜토리얼 단계 2 && wave==1 → 튜토리얼 적 2마리(§8)
   - 튜토리얼 단계 4 → 마법사 궁 쿨 0으로 리셋, 튜토리얼 적 2마리(§8)
   - 그 외 일반 서브웨이브 0 생성(§4.3)
   - 주의: 기믹 판정이 튜토리얼 분기보다 **먼저** 수행됨(웨이브 3 이상에서 튜토리얼 4단계가 남아 있으면 기믹이 우선할 수 있음).

### 1.4 적 순차 등장 (`spawnEnemiesSequentially`)
- phase='spawning', 기존 적 배열 비움. 메시지 표시(기본 "👾 적 등장 중...").
- i번째 적을 `i * 170ms` 후 추가. 마지막 적 추가 후 `420ms` 뒤 phase='battle'.
- 목록이 비면 즉시 battle.
- spawning 중에는 전투 시뮬레이션이 돌지 않는다.

### 1.5 전투 시뮬레이션 루프
- requestAnimationFrame + **고정 스텝 33ms**. 프레임 dt는 최대 250ms로 클램프, 한 프레임 최대 8스텝, 8스텝에 도달하면 누적 시간 버림.
- 시뮬레이션 시간 `now`(simNow)는 스텝마다 +33ms. 전투 진입 시 `Date.now()`로 초기화.
- **궁극기 조준 중(slowMotion=true)에는 tick 자체가 정지**(이름은 슬로모션이지만 실제로는 일시정지).
- 골드 회수 중(`collectingGold`)에도 tick 정지.
- 주의: 일부 타이머(스턴/슬로우 만료, 궁극기 쿨다운, 히드라 부활 시각, 스킬/투사체 setTimeout)는 `Date.now()`(실시간) 기준. Godot에서는 **단일 게임 시간**으로 통일하는 것을 권장(일시정지 시 함께 멈추도록).

tick 순서:
1. 히드라 기믹이면: 히드라 4마리 모두 HP≤0 → 각 히드라 위치에 골드 40 드랍, 적 배열 비움, "🎉 히드라 클리어!", `finishWave(wave+1)`. 아니면 죽은 히드라 중 사망 후 2000ms 경과한 것은 HP 최대로 부활.
2. 히드라 기믹이 아니고 살아있는 적이 0 → 서브웨이브 남았으면 `subWave+1`, 800ms 후 `spawnSubWave(wave, nextSub)` 순차 등장(메시지 "⚔️ N차 웨이브!"), 아니면 `finishWave(wave+1)`.
3. 영웅 수 0 → gameOver=true, phase='gameover'.
4. 각 영웅: `mana >= maxMana(100)` 이면 고유 스킬 시전(적이 있을 때만 성공) → 성공 시 mana=0.
5. 각 영웅 행동(§3.4).
6. 각 적 행동(§4.2).

### 1.6 웨이브 종료 (`finishWave(nextWave)`), clearedWave = nextWave-1
1. phase='transition', returningToStart=true.
2. 바닥 골드 전체 회수(600ms 후 골드 합산). 기믹 해제, subWave=0.
3. **시간의 결정 +2** (메시지 "🔷 스테이지 클리어! 시간의 결정 +2").
4. clearedWave == 40 → 커피 보상 연출 3.2초(게임은 계속).
5. 700ms 후:
   - 회복량 `waveHeal = 50 + waveHealBonus(특성트리)`. 살아있는 모든 영웅을 startPositions로 이동, `currentHp = min(currentHp + waveHeal, hp)`.
   - clearedWave >= 10 && %10==0 → 상인 열기(아이템 4개), 회복, 종료(phase는 transition 유지; 상인 닫을 때 wave 증가 & placement).
   - 아니면: clearedWave >= 3 && %3==0 → 특성 선택 열기. phase='placement', wave=nextWave.
   - 튜토리얼 대기 플래그 처리(§8).
6. 상인 닫기: 상인 닫은 뒤 clearedWave>=3 && %3==0 이면 특성 선택 열기(예: 30, 60웨이브), wave=nextWave, placement.
7. 복귀 완료 판정: placement/transition 에서 모든 영웅이 startPositions에 있으면 430ms 후 returningToStart=false (그 전엔 전투 시작 불가).

### 1.7 재시작 (`restartGame`)
- id 카운터 0, 초기 유닛 재생성(특성 HP 반영), wave=1, gold=특성 startGold, 인벤토리 = (특성 `emergencySupply` 보유 시 랜덤 1티어 장비 1개) + 보유 중이던 **전설 유물**(영구), 인벤 용량 14, 퍽/상인/사망유닛 초기화, 퍽 리롤비 500, **튜토리얼 0(재시작 시 튜토리얼 없음)**, 부활 특성 사용 플래그 초기화, 유물 템포 스택 0.
- 시간의 결정과 특성 트리는 유지.

---

## 2. 보드

- `GRID_W = 6`(x: 0..5, 좌→우), `GRID_H = 8`(y: 0..7, 위→아래), `CELL = 56px`.
- 픽셀 중심: `px = x*56 + 28`, `py = y*56 + 28` (원뿔/라인 판정 등에서 사용).
- 구역: y=0..1 적 생성 구역, y=2..3 중립, **y=4..7 플레이어 배치 구역**.
- 배치: placement/transition 페이즈에서 영웅 드래그 → 드롭 칸이 `0<=x<6 && 4<=y<8` 이고 다른 영웅이 없으면 이동. (적은 배치 단계에 없음)
- 초기 영웅 좌표: 전사 (1,6), 궁수 (3,5), 마법사 (5,6).
- 점유: 영웅 1칸, 적 `size` (기본 1, 거인 2 → (x..x+1, y..y+1) 2×2, x,y는 좌상단 앵커). 거리 계산은 앵커 좌표 기준.
- 이동은 기본 4방향 1칸. 이동 규칙(`getMoveDir`): 상,하,좌,우 순서로 검사, 그리드 안 & 비점유 칸 중 목표와의 맨해튼 거리가 **현재보다 엄격히 작아지는** 최솟값 칸 선택(동률은 먼저 검사한 방향). 없으면 이동 안 함.

---

## 3. 영웅(유닛)

### 3.1 기본 스탯 (`UNIT_TYPES`)
| 키 | 이름 | HP | ATK | 사거리 | 공격 간격 speed(ms) | 이동 간격 moveSpeed(ms/칸) | maxMana | 공격당 마나 |
|---|---|---|---|---|---|---|---|---|
| warrior | 워리어(전사) | 200 | 30 | 1 | 1600/3 ≈ 533.33 | 1200/3 = 400 | 100 | 25 |
| ranger | 레인저(궁수) | 120 | 40 | 3 | 1200/3 = 400 | 1500/3 = 500 | 100 | 20 |
| mage | 메이지(마법사) | 100 | 55 | 3 | 1800/3 = 600 | 2400/3 = 800 | 100 | 15 |

- speed/moveSpeed는 "다음 행동까지 필요한 최소 간격(ms)". 값이 작을수록 빠름.
- 사거리는 맨해튼 거리.
- 유닛 생성 필드: level 1, exp 0, currentHp=hp, lastAttack 0, lastMove 0, skills [0,0,0], skillBooks {}, skillPoints 0, ultCooldown 0(즉시 사용 가능), mana 0, attackCount 0, equipment {weapon, armor, accessory}=null, equipmentBonuses 동일.
- 생성 시 특성 HP: `hp += floor(baseHp * unitTalent.hpMult)`, currentHp도 동일 증가.

### 3.2 레벨/경험치
- 처치 1회당 EXP: `expGain = floor(처치수(히드라 제외) * 25 * (1 + expMult))` — **막타를 친 유닛에게만** 지급. expMult = 퍽 + 특성 트리.
- 레벨업 필요 EXP: `level * 40` (현재 레벨 기준, 초과분 이월, 여러 번 연속 레벨업 가능).
- 레벨업 시: `hp += 15`, `atk += 8`, `currentHp = min(currentHp + 30, hp)`, **새 레벨이 짝수이면 skillPoints +1**.
- 같은 expGain이 장착된 스킬북 각각에도 누적(§3.6).
- 별/합성(유닛) 시스템 없음. 유닛은 항상 3명 고정(추가 구매 불가).

### 3.3 패시브 스킬 (`SKILLS`, 스킬포인트로 레벨업, 각 최대 3)
| 직업 | 슬롯 | id | 이름 | 효과(lv당) |
|---|---|---|---|---|
| 전사 | 0 | ironWall | 철벽 | dmgReduce +0.15 |
| 전사 | 1 | counter | 반격 | counterChance +0.30 |
| 전사 | 2 | vitality | 생명력 | bonusHp +20 |
| 궁수 | 0 | rapidFire | 속사 | atkSpeedBonus +0.20 |
| 궁수 | 1 | pierce | 관통 | pierceChance +0.25 |
| 궁수 | 2 | critical | 치명타 | critChance +0.20 |
| 마법사 | 0 | explosion | 폭발 | explosionChance +0.30 |
| 마법사 | 1 | freeze | 빙결 | freezeChance +0.25 |
| 마법사 | 2 | arcane | 마력 증폭 | dmgBonus +0.20 |

- 업그레이드(`upgradeSkill`): placement/transition에서 유닛 선택 → "UP". 조건 `skillPoints > 0 && skills[i] < 3`. SP 1 소모.
- 전사 vitality 업그레이드 시: `hp = 200(기본) + bonusHp`, `currentHp = min(currentHp + 20, hp)`. **버그: 레벨업/아이템/특성으로 늘어난 HP가 사라짐**(포팅 시 `hp += 20` 으로 수정 권장, 판단은 기획).
- 효과 합산(`getSkillEffects`): 슬롯별로 스킬북이 있으면 스킬북 스킬·스킬북 레벨, 없으면 기본 스킬·skills[i] 레벨.

### 3.4 영웅 행동 (tick마다)
궁극기 시전 중(ultCastingUnitId == 이 유닛, 즉 궁수 집중포화 채널 중)이면 아무것도 안 함.
```
atkSpdSum = skill.atkSpeedBonus + item.atkSpeedBonus + perk.atkSpeedBonus + unitTalent.atkSpeedBonus
attackInterval = speed * (1 - min(atkSpdSum, 0.7))
moveInterval   = moveSpeed * (1 - min(item.moveSpeedBonus + perk.moveSpeedBonus, 0.75))
range = baseRange + item.range + perk.range + unitTalent.range
target = 살아있는 적 중 맨해튼 거리 최소(동률은 배열 앞쪽)
if dist <= range && now - lastAttack >= attackInterval: 공격(fireProjectile(unit, target, unit.atk)); lastAttack = now
elif dist > range && now - lastMove >= moveInterval: getMoveDir(점유=다른 영웅+모든 적(죽은 히드라 포함)); 이동 시 lastMove = now
```

### 3.5 공격 처리 (`fireProjectile`, 영웅 → 적)
명중 지연(impact delay):
- 전사: 350ms (근접 베기)
- 궁수: 200ms (화살)
- 마법사: **볼트 2발** — 1발 460ms 후 명중, 2발은 300ms 후 발사되어 300+460=760ms 후 명중. **각 볼트가 독립적으로 전체 피해·마나·attackCount·온힛 효과를 적용**(실질 2회 타격). 명중 시 원래 대상이 죽었으면 마법사에서 가장 가까운 살아있는 적으로 재지정. 시전자가 죽었으면 취소.
- 반격(카운터)에 의한 공격: 50ms, 이펙트 없음.

명중 시 계산(피해 공식, 발사 시점 유닛 스냅샷 기준):
```
atkMult = 1 + perk.atkMult + unitTalent.atkMult
dmg = floor((unit.atk + item.atk) * atkMult)
critChance = skill.critChance + item.critChance + perk.critChance + unitTalent.critChance
if rand() < critChance: dmg *= 2  (CRITICAL 표시)
dmgBonus = skill.dmgBonus + item.dmgBonus
if dmgBonus > 0: dmg = floor(dmg * (1 + dmgBonus))
```
- 주의(버그): `perk.atkMult`에 특성 트리 공용 atkMult가 이미 포함되고, `unitTalent.atkMult`에도 공용 atkMult가 포함 → **특성 '반복 전투술'(allAtk)이 2배로 적용됨**. 동일 패턴이 `getUnitAttackPower`(스킬/궁 피해 기준)와 스탯창에도 있음.
- 흡혈: perk.lifeSteal > 0 → 공격자 `currentHp += floor(dmg * lifeSteal)` (최대 hp).
- 마나: `manaGain = floor(manaPerAttack * (1 + perk.manaGainMult + unitTalent.manaGainMult))`, 공격자 mana += manaGain (최대 100), attackCount +1. **sharedMana 효과를 가진 다른 아군**은 `floor(manaGain*0.5)` 획득.
- 유물 템포(tempoRelic 보유): relicTempoStacks = min(15, +1). 공속 보너스 `min(0.30, stacks*0.02)`. 전투 시작 시 0으로 리셋.
- 대상 처리:
  - 환영(isIllusion)이고 환술사가 살아있으면: 피해 무효(IMMUNE 표시), 이후 처리 생략(단, 아래 폭발/관통은 무효 판정 없이 적용됨 — 버그).
  - 빙결: `rand() < skill.freezeChance` → 대상 `slowUntil = now + 2000`.
  - 넉백 장비(knockback && !swap && !knockbackImmune): 공격자→대상 방향의 주축(|dx|>=|dy|면 x축)으로 1칸 밀기, 그리드 클램프, 다른 살아있는 적이 있으면 취소.
  - 대상 HP -= dmg.
- 폭발/스플래시: `explosionChance = skill.explosionChance + item.explosionChance + perk.splashChance`; 성공 시 대상과 맨해튼 거리 ≤1인 다른 모든 적에게 `floor(dmg*0.5)`.
- 관통: `rand() < skill.pierceChance` → 대상 바로 뒤 칸(대상 + sign(dx), sign(dy); dx,dy=대상-공격자) 의 적에게 `floor(dmg*0.7)`.
- 위치 교환(swap 장비): 공격자와 대상 좌표 교환(점유 검사 없음).
- 번개(lightning 장비): `(attackCount+1) % 3 == 0` 이면 대상 외 살아있는 적 중 랜덤 1명에게 150ms 후 `floor(dmg*0.8)`.
- 처치 판정: 이번 계산으로 HP가 >0에서 ≤0이 된 적 → `handleEnemyKill`(§4.6), 궁수+특성 rangerGoldBonus면 처치당 `max(1, floor(10*rangerGoldBonus))` 골드 추가 드랍, killMana 장비면 공격자 마나 최대, 막타 EXP 지급. HP≤0 적은 제거(히드라 제외 — 시체로 남음).
- 추가 공격(유물 echoCrystal, doubleAttackChance): 보너스 공격이 아닌 일반 공격 시 `rand() < doubleAttackChance` → 210ms 후 같은 대상(마법사는 재지정 규칙)에 동일 damage로 보너스 공격 1회("추가 공격!" 표시). 보너스 공격은 다시 추가 공격을 유발하지 않음.

### 3.6 스킬북 (`SKILLBOOK_SKILLS`)
- 획득: 웨이브 ≥20에서 적 처치 시 3% (직업 균등 랜덤 → 그 직업 3개 중 균등 랜덤). "봉인됨" 상태로 인벤토리에 들어감.
- 사용(클릭): 스킬 공개 → 선택 팝업: 해당 직업 유닛의 슬롯 0~2 중 하나를 교체, 또는 버리기.
- 교체 시 `skillBooks[slot] = { skillId, level: 1, exp: 0 }`, `skills[slot] = 0`(기존 투자 SP 소멸, 환급 없음).
- 성장: 전투 EXP를 그대로 받아 `exp >= 70 + level*55` 이면 레벨업, 최대 Lv.5. SP로는 올릴 수 없음.
- 판매가 300G. 희귀도 mythic/tier5 취급.

| 직업 | id | 이름 | lv당 효과 |
|---|---|---|---|
| 전사 | berserkerRage | 광전사의 분노 | dmgBonus 0.14, atkSpeedBonus 0.06 (설명은 "체력이 낮을수록"이지만 실제로는 상시 고정) |
| 전사 | whirlSlash | 회전 베기 | explosionChance 0.12, dmgBonus 0.06 |
| 전사 | ironTaunt | 철벽 도발 | dmgReduce 0.08, counterChance 0.08 |
| 궁수 | sniperMode | 저격 모드 | critChance 0.08, dmgBonus 0.10 |
| 궁수 | splitArrow | 분열 화살 | pierceChance 0.10, explosionChance 0.08 |
| 궁수 | shadowEvasion | 그림자 회피 | dodgeChance 0.07, atkSpeedBonus 0.04 |
| 마법사 | blackHole | 블랙홀 | explosionChance 0.10, freezeChance 0.05, dmgBonus 0.06 |
| 마법사 | overcharge | 과충전 | atkSpeedBonus 0.08, dmgBonus 0.10 |
| 마법사 | absoluteFrost | 절대 동결 | freezeChance 0.10, dmgReduce 0.03 |

### 3.7 고유 스킬 (마나 100 자동 발동, `ACTIVE_SKILLS`)
공통: `atkPower = max(1, floor((atk + item.atk) * (1 + perk.atkMult + unitTalent.atkMult)))` (치명타/dmgBonus 미적용), `baseDamage = max(1, floor(atkPower * damageMultiplier))`. 살아있는 적이 없으면 발동 실패(마나 유지). 환영 무적 규칙 적용(환술사 생존 중 환영은 피해·효과 없음).

**전사 — 용맹한 강습 (autoJumpSlam)**: damageMultiplier 1.65, impactAtkMultiplier 1.2, impactMaxHpRatio 0.35, stunDuration 1050, guardDuration 2100
1. 대상 = 가장 **먼** 살아있는 적(맨해튼).
2. 착지 칸 = `getNearestEmptyCell(target)`: 대상 칸이 비면 그 칸(대상 자신은 무시), 아니면 반경 r=1,2의 정사각 링을 dy=-r..r, dx=-r..r 순으로 검사해 첫 빈 칸, 없으면 클램프 좌표.
3. 즉시 `warriorGuardUntil = now + 2100` (가드 중 받는 피해 감소 +0.5).
4. 260ms 점프 후 착지: 유닛 좌표 갱신. 각 적:
   - onTarget(대상 id이거나 대상 원래 좌표에 있음): `extra += floor(적 최대HP * 0.35) + floor(atkPower * 1.2)`, 착지 지점 반대 방향으로 1칸 밀기(`getPushCell`).
   - nearLanding(착지 칸과 체비쇼프 거리 ≤1): `extra += baseDamage`.
   - 둘 다 해당되면 합산. 피격 적 모두 `stunUntil = now + 1050`.

**궁수 — 다중 사격**: damageMultiplier 2.5, targetCount 3
1. 후퇴: 뒤칸 (x, y+1)이 비면 그곳으로, 아니면 좌/우 빈 칸 중 "가장 가까운 적까지 거리"가 큰 칸(동률이면 좌측 우선), 둘 다 막히면 제자리.
2. 원래 위치 기준 가까운 순 3명에게 i*100ms 간격으로 화살 발사, 발사 150ms 후 각 `baseDamage`.

**마법사 — 절대 영도**: damageMultiplier 1.5, freezeDuration 1000
- 300ms 후 모든 살아있는 적에게 `baseDamage`, `stunUntil = slowUntil = frozenUntil = now + 1000`.

`getPushCell(enemy, fromX, fromY)`: knockbackImmune 또는 giant면 이동 없음. 주축 방향(|dx|>=|dy| ? (sign dx,0) : (0,sign dy)) → (1,0) → (-1,0) → (0,1) → (0,-1) 순으로 그리드 안이고 점유 가능한 첫 칸.

### 3.8 궁극기 (`ULTIMATES`, 수동 — 길게 누르기)
- 발동 조건: phase=='battle', `ultCooldown <= now`. 유닛을 누른 상태로 300ms → 조준 모드(시뮬레이션 정지, 커서 위치가 조준점). 손을 떼면 발동. 300ms 전에 떼면 취소.
- 쿨다운: `actual = floor(cooldown * (1 - min(0.85, perk.ultCooldownReduce + unitTalent.ultCooldownReduce)))`, 발동 시 `ultCooldown = now + actual`. 초기값 0이므로 첫 전투에서 즉시 사용 가능, 쿨다운은 페이즈와 무관하게 실시간 흐름.
- `ultDmg = max(1, floor(atkPower * damageMultiplier * (1 + unitTalent.ultDamageBonus)))`, `tickDmg = max(1, floor(atkPower * damagePerTickMultiplier))`.

| 직업 | 이름 | type | 수치 | cooldown |
|---|---|---|---|---|
| 전사 | 충격파 | shockwave | damageMultiplier 2.0, stunDuration 1000 | 8500 |
| 궁수 | 집중 포화 | coneBarrage | length 360px, coneAngle π/7, damagePerTickMultiplier 0.6, tickInterval 250, channelDuration 2000 | 7000 |
| 마법사 | 체인 라이트닝 | chainLightning | maxBounces 5, damageMultiplier 1.45 | 10000 |

- **충격파**: (조준 무관) **맵의 모든** 살아있는 적에게 ultDmg, 시전자 기준 1칸 밀기(getPushCell), 1000ms 스턴. (조준 미리보기는 반경 원을 보여주지만 실제 판정은 전체 — 기획 확인 필요)
- **체인 라이트닝**: 시전자 좌표에서 시작해 방문하지 않은 적 중 가장 가까운 적으로 연쇄, 최대 `5 + mageUltBouncesBonus`회. i번째 타격은 i*100ms 후 번개, 그 50ms 후 ultDmg. 마지막 후 시전자로 귀환(연출). 대상 없으면 쿨다운만 소모.
- **집중 포화**: 조준각 = 시전자 중심→조준점. 판정 `isInCone`: 시전자 중심과 적 앵커칸 중심의 거리 8 < d ≤ 360px, 각도 차 ≤ π/14. 2000ms 동안 시전자 이동/공격 불가. tick=1..8 (250ms 간격) 마다 콘 안의 적 모두에게 tickDmg. (매 틱마다 콘 판정을 다시 함, 조준각은 고정)
- 마법사 궁 사용 시 특성 `magFinal` 보유하면 10% 확률로 시간의 결정 +1.
- 튜토리얼 4단계에서 마법사 궁 사용 → 튜토리얼 진행(§8).

### 3.9 영웅 피격 (적 → 영웅)
```
dodge = min(skill.dodgeChance, 0.75); rand() < dodge → 회피(IMMUNE 표시), 끝
reduce = min(0.9, skill.dmgReduce + item.dmgReduce + perk.dmgReduce(퍽+유물) + unitTalent.dmgReduce
                  + (가드 중 ? 0.5 : 0)
                  + (특성 warTaunt && 살아있는 전사 존재 ? 0.03 : 0)
                  + (대상이 전사 && 특성 warLastStand && currentHp/hp <= 0.3 ? 0.15 : 0))
final = max(1, floor(enemyAtk * (1 - reduce)))
```
- 반격: `counterChance = skill.counterChance + item.counterChance + unitTalent.counterChance`; 성공 시 100ms 후 영웅이 공격자에게 `unit.atk` 기반 일반 공격 1회(이펙트 생략, 마나/온힛 정상 적용).
- HP ≤ 0 시 순서:
  1. 전사이고 특성 `warFinal` 보유, 런 중 미사용 → HP = max(1, floor(hp*0.5))로 부활.
  2. 특성 `secondChance` 보유, 런 중 미사용 → HP = max(1, floor(hp*0.3))로 부활(아무 영웅이나 첫 사망 1회).
  3. 그 외 사망: 유닛 목록에서 제거, `deadUnits`에 HP 최대 상태로 저장(부활의 깃털로 복귀, 사망 위치로 복귀).
- 영웅이 1명만 남고 사망자가 1명 이상이면 1회성 팁: "다음 상점까지 살아남아서, 부활깃털을 얻어 동료를 부활시키세요!"

---

## 4. 적

### 4.1 적 스탯 (`createEnemy`) — HP/ATK에 웨이브 배율 적용
`mult = getScalingMultiplier(wave)`, `hp = floor(baseHp * mult)`, `atk = floor(baseAtk * mult)`. 사거리/속도는 배율 없음.

| type | HP | ATK | 사거리 | 공격간격 | 이동간격 | 특이 |
|---|---|---|---|---|---|---|
| normal | 35 | 8 | 1 | 1400 | 1200 | |
| fast | 25 | 8 | 1 | 1000 | 800 | |
| tank | 80 | 12 | 1 | 2000 | 1800 | |
| boss | 200 | 25 | 2 | 1500 | 1300 | |
| goblin | 22 | 7 | 1 | 850 | 520 | 고블린 부대 기믹 |
| ninja | 18 | 13 | 1 | 900 | 1000 | 가장 먼 영웅 추적, 점프 |
| splitter | 55 | 9 | 1 | 1350 | 1150 | 사망 시 분열 |
| splitling | 12 | 5 | 1 | 900 | 850 | 분열체 자식 |
| sprinter | 28 | 9 | 1 | 900 | 760 | 8방향 2칸 대시 |
| giant | 620 | 22 | 2 | 2100 | 3000 | size 2(2×2), knockbackImmune |

기믹 전용(배율 직접 적용):
| 종류 | HP | ATK | 사거리 | 공격간격 | 이동간격 |
|---|---|---|---|---|---|
| hydra | floor(50*mult) | floor(10*mult) | 1 | 1200 | 1000 |
| illusionist(진짜) | floor(80*mult) | floor(12*mult) | 1 | 1000 | 900 |
| illusion(환영) | floor(40*mult) | floor(12*mult) | 1 | 1000 | 900 |

### 4.2 웨이브 배율 (`getScalingMultiplier`)
```
wave <= 10: 1 + (wave-1)*0.15
wave <= 20: 2.35 + (wave-10)*0.25
wave <= 30: 4.85 + (wave-20)*0.4
else:       8.85 * 1.15^(wave-30)
```
참고값: w1 1.0, w5 1.6, w10 2.35, w15 3.6, w20 4.85, w25 6.85, w30 8.85, w35 17.80, w40 35.80, w50 144.84.

### 4.3 일반 서브웨이브 구성 (`spawnSubWave`)
```
cnt = min(3 + floor(wave*0.5), 10)
if wave >= 20: cnt = min(4 + floor((wave-20)*0.3), 8)
각 적마다 roll = rand():
  wave>=30 && roll>0.70 → boss
  elif wave>=15 && roll>0.85 → boss
  elif wave>=10 && roll>0.75 → tank
  elif wave>=5 && roll>0.70 → fast
  else normal
위치: x∈[0,5], y∈[0,1] 랜덤, 이미 점유된 칸이면 최대 20회 재시도, 그래도 점유면 그 적은 생략.
```
- 웨이브 ≥30에서는 boss(30%) / normal(70%)만 나옴(tank/fast 분기 도달 불가).
- 확률표: w1-4: normal 100% / w5-9: fast 30% / w10-14: tank 25%, fast 5% / w15-29: boss 15%, tank 10%, fast 5% / w30+: boss 30%.
- 서브웨이브 수: w1-19: 1, w20-24: 2, w25+: 3. 서브웨이브 간 지연 800ms.

| wave | 배율 | 서브웨이브당 수 | 서브웨이브 |
|---|---|---|---|
| 1 | 1.00 | 3 | 1 |
| 2 | 1.15 | 4 | 1 |
| 5 | 1.60 | 5 | 1 |
| 8 | 2.05 | 7 | 1 |
| 10 | 2.35 | 8 | 1 |
| 12 | 2.85 | 9 | 1 |
| 14+ (≤19) | ≥3.35 | 10 | 1 |
| 20 | 4.85 | 4 | 2 |
| 25 | 6.85 | 5 | 3 |
| 28 | 8.05 | 6 | 3 |
| 30 | 8.85 | 7 | 3 |
| 34+ | — | 8 | 3 |

### 4.4 기믹 웨이브 (첫 서브웨이브를 대체, 이후 서브웨이브는 일반)
- 위치 `randomFreeTopCell(size)`: x∈[0, 6-size], y∈[0, 2-size] 랜덤 50회 시도, 실패 시 생략.
- `goblinRaid`: goblin 6 — "🟢 고블린 부대 습격!"
- `ninjaRaid`: ninja 3 — "🥷 닌자 습격!"
- `splitterRaid`: splitter 4 — "🧫 분열체 무리 등장!"
- `sprinterRaid`: sprinter 3 — "⚡ 질주 몬스터 등장!"
- `giantBoss` (wave≥35 && %5==0 고정): giant 1 (y=0, 실패 시 (2,0)) — "🗿 거대 중간보스 등장!"
- `hydra`: 히드라 4마리 고정 좌표 (1,0),(2,0),(3,1),(4,1). 죽어도 시체로 남고 사망 2000ms 후 최대 HP로 부활. **4마리가 동시에 죽어 있는 순간** 클리어 → 각 시체 위치에 골드 40(배율 없음, 골드퍽 적용), 이후 남은 서브웨이브 없이 바로 finishWave. 히드라 처치는 골드/EXP/시간의 결정 없음, 아이템 드랍(30%)은 있음.
- `illusionist`: 5마리 랜덤 상단 배치, 그 중 1마리(랜덤 인덱스)만 진짜 환술사. 환술사 생존 중 환영은 모든 직접 피해·스킬 피해 무효. 환술사 처치 시 "💀 환술사 처치!" 이후 환영도 피해 가능. 웨이브 클리어는 전원 처치.
- 기믹 안내 텍스트(HUD):
  - hydra: 처치 후 2초 뒤 부활 — 4마리 모두 제거해야 클리어
  - illusionist: 환영 4마리 중 진짜 1마리를 찾아 처치하세요
  - goblinRaid: 빠르지만 체력이 낮은 적 6마리가 몰려옵니다
  - ninjaRaid: 가장 멀리 있는 아군에게 점프 접근합니다
  - splitterRaid: 죽으면 작은 개체 2마리로 갈라집니다
  - sprinterRaid: 대각선 포함 2칸씩 이동합니다
  - giantBoss: 2x2 크기, 넉백 면역, 매우 높은 체력

### 4.5 적 행동 (tick마다)
```
HP<=0 또는 now < stunUntil → 행동 없음
target = 가장 가까운 영웅 (ninja는 가장 먼 영웅)
slowed = now < slowUntil
attackInterval = slowed ? speed*2 : speed;  moveInterval = slowed ? moveSpeed*2 : moveSpeed
ninja: dist > range && now - lastJump >= 1700 → 대상 주변 8칸 중 점유 가능하고 닌자에게 가장 가까운 칸으로 순간 점프(lastMove=lastJump=now), 이번 tick 종료
dist <= range && now - lastAttack >= attackInterval → 공격(명중 350ms 후, §3.9)
dist > range && now - lastMove >= moveInterval → 이동:
   sprinter: 8방향, 먼저 2칸 거리 후보 전부 검사 → 개선되는 최적 칸, 없으면 1칸 후보 (중간 칸 막힘 무시)
   size>1(거인): 4방향 1칸, 2×2 전체 점유 가능 검사
   그 외: getMoveDir 4방향 (점유 = 다른 살아있는 적 + 영웅)
```
- 적은 별도 목표 지점이 없고 영웅만 공격. 영웅을 모두 죽이면 패배.

### 4.6 적 처치 처리 (`handleEnemyKill`)
1. 환술사 → 환술사 사망 플래그.
2. splitter → 오프셋 (0,0),(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,1) 순으로 점유 가능한 칸에 splitling 최대 2마리(현재 웨이브 배율).
3. **killMana 장비를 가진 모든 영웅의 마나를 최대로**(처치자 무관 — 원본 동작).
4. 골드(히드라 제외): `base = boss 80 | tank 30 | illusionist 40 | illusion 20 | 그 외 15`, `+ floor(wave/5)*5`, 드랍 시 `floor(amount * (1 + goldMult))`. 골드는 바닥에 떨어지고 **웨이브 종료 시 일괄 회수**(게임오버 시 미회수분 소실).
5. 시간의 결정(히드라 제외): `rand() < 0.05 + crystalDropBonus` → +1.
6. 스킬북: wave ≥ 20 && rand() < 0.03.
7. 공간 확장 키트: wave ≥ 20 && rand() < 0.04.
8. 유물: wave ≥ 15, roll<0.003 → 전설 유물 랜덤, roll<0.013 → 희귀 유물 랜덤.
9. 일반 아이템: `rand() < DROP_RATES[type] + dropBonus` → `getRandomItem(wave)`.
   - `DROP_RATES = { normal 0.2, fast 0.25, tank 0.4, boss 0.8, hydra 0.3, illusionist 0.6, illusion 0.15 }`, 그 외 0.2.

---

## 5. 경제

### 5.1 골드
- 시작 골드: 0 + 특성 `startGold`(레벨당 50).
- 수입: 적 처치 드랍(§4.6), 히드라 클리어 40×4, 궁수 특성 보너스, 아이템 판매, 인벤토리 가득 시 자동 판매.
- 지출: 상인 구매, 상인 리롤 300G(고정), 특성(퍽) 리롤 500G부터 +500씩.
- goldMult = 퍽 + 유물(luckyCompass) (특성 트리에 goldMult 노드는 없음).

### 5.2 시간의 결정 (영구 재화)
- 처치당 5% + crystalDropBonus(특성 crystalSense 레벨당 0.005, rngFinal 0.02) — 히드라 제외.
- 웨이브 클리어마다 +2 확정.
- 마법사 궁 사용 시 10%(특성 magFinal).
- 용도: 영구 특성 트리. localStorage 저장, 게임오버 후 유지.

### 5.3 배율 HUD
- "배율" = `getScalingMultiplier(wave)` 소수점 1자리(x1.0). 적 HP/ATK 배율 표시용일 뿐 보상에는 영향 없음.

### 5.4 상인 (10, 20, 30… 웨이브 클리어 후)
아이템 4개, 각 슬롯 `specialRoll = rand()`:
- `< 0.015 && wave >= 25` → 초희귀(ultra) 전설 랜덤, 가격 = 아이템 price(5200~6000)
- `< 0.08` → 일반 전설(LEGENDARY_ITEMS 중 ultra 아님) 랜덤, 가격 2000
- `< 0.20` → SPECIAL_ITEMS 랜덤(아래 가격)
- 그 외 → `getRandomItem(wave)` (전설이면 price 또는 2000, 일반이면 `ITEM_BUY_PRICES[tier]`)
- `ITEM_BUY_PRICES = {1:30, 2:100, 3:350, 4:1000, 5:2000}`
- 구매 조건: 골드 충분 && 인벤토리 여유. 구매한 슬롯은 사라짐(재고 보충 없음). 리롤 300G로 4개 재생성. 닫기 → 다음 웨이브.
- 상인 화면에서 인벤토리 클릭 판매 가능.

### 5.5 판매가
- `ITEM_SELL_PRICES = {1:10, 2:35, 3:120, 4:400, 5:800, 6:1800, 7:3200}`
- 스킬북: 300
- 유물: `floor(price * 0.5 * (1+goldMult))`
- 특수(소비/왕관): `floor(price * 0.5)` (goldMult 미적용)
- 그 외 장비: `floor(SELL[tier] * (1+goldMult))`
- 인벤토리 가득 상태에서 드랍 → 즉시 자동 판매: `floor((SELL[tier] || floor((price||500)*0.5) || 800) * (1+goldMult))`.
- (상인 화면의 표시 가격은 유물/스킬북을 고려하지 않아 실제 판매가와 다를 수 있음 — 버그)

---

## 6. 아이템 · 인벤토리

### 6.1 인벤토리
- 기본 용량 `MAX_INVENTORY = 14`, 공간 확장 키트 사용 시 +3 (런 한정).
- 인벤토리 엔트리: `{ id, itemKey, bonusStats?, isLegendary?, isSpecialEquip?, isTranscendent? }`, 소비템 `{ id, specialKey, ... }`, 스킬북 `{ id, type:'skillBook', unitType, skillId, revealed }`, 유물 `{ id, type:'relic', itemKey, permanent? }`.
- 장비 슬롯: weapon / armor / accessory (유닛당 각 1).
- 장착: placement/transition에서 장비를 영웅 위로 드래그. 기존 장비는 인벤토리로 반환(합성 검사). `hp += (새 장비 HP합 - 기존 HP합)`, `currentHp = min(currentHp + max(0, hpDiff), 새 hp)`. 장비 해제 단독 기능 없음.
- 소비템/스킬북은 클릭 사용, 유물은 소지만으로 효과(드래그 불가).
- 추가 옵션(이동속도): 고희귀(legendary/mythic/transcendent 또는 tier≥5) 아이템이 `makeInventoryEntry`로 생성될 때 35% 확률로 `moveSpeedBonus = round((0.05 + rand()*0.35)*100)/100` (0.05~0.40) 부여. (상인에서 산 일반 장비는 미적용)

### 6.2 일반 장비 (`ITEMS`, family 8종 × tier 1~4)
| key | 이름 | 슬롯 | 스탯 |
|---|---|---|---|
| sword1 | 낡은 검 | weapon | atk 5 |
| sword2 | 강철검 | weapon | atk 12 |
| sword3 | 미스릴검 | weapon | atk 25 |
| sword4 | 전설의 검 | weapon | atk 50, crit 0.15 |
| axe1 | 손도끼 | weapon | atk 7 |
| axe2 | 전투도끼 | weapon | atk 15 |
| axe3 | 처형자의 도끼 | weapon | atk 30, crit 0.10 |
| axe4 | 심판의 도끼 | weapon | atk 55, crit 0.25 |
| bow1 | 단궁 | weapon | atk 4, range 1 |
| bow2 | 장궁 | weapon | atk 10, range 1 |
| bow3 | 정밀 석궁 | weapon | atk 20, range 2 |
| bow4 | 바람의 활 | weapon | atk 35, range 2, atkSpd 0.20 |
| staff1 | 나무 지팡이 | weapon | atk 3, dmgBonus 0.05 |
| staff2 | 마법 지팡이 | weapon | atk 8, dmgBonus 0.12 |
| staff3 | 대마법사의 지팡이 | weapon | atk 15, dmgBonus 0.25 |
| staff4 | 아크메이지 스태프 | weapon | atk 25, dmgBonus 0.40, explosion 0.20 |
| shield1 | 나무 방패 | armor | hp 15, dmgReduce 0.05 |
| shield2 | 철 방패 | armor | hp 35, dmgReduce 0.10 |
| shield3 | 수호자의 방패 | armor | hp 60, dmgReduce 0.18 |
| shield4 | 불멸의 방패 | armor | hp 100, dmgReduce 0.30, counter 0.20 |
| helmet1 | 가죽 모자 | armor | hp 10 |
| helmet2 | 철 투구 | armor | hp 25 |
| helmet3 | 강철 투구 | armor | hp 50, dmgReduce 0.08 |
| helmet4 | 용의 투구 | armor | hp 80, dmgReduce 0.15, atk 15 |
| ring1 | 구리 반지 | accessory | atkSpd 0.08 |
| ring2 | 은 반지 | accessory | atkSpd 0.15 |
| ring3 | 민첩의 반지 | accessory | atkSpd 0.25, atk 8 |
| ring4 | 폭풍의 반지 | accessory | atkSpd 0.40, atk 20, crit 0.10 |
| amulet1 | 나무 목걸이 | accessory | hp 12 |
| amulet2 | 은 목걸이 | accessory | hp 30 |
| amulet3 | 생명의 목걸이 | accessory | hp 55, dmgReduce 0.08 |
| amulet4 | 불사의 목걸이 | accessory | hp 90, dmgReduce 0.15, atk 10 |
희귀도: tier1 common, 2 uncommon, 3 rare, 4 legendary.

### 6.3 전설 장비 (`LEGENDARY_ITEMS`)
| key | 이름 | 슬롯 | 스탯 | 효과 | 비고 |
|---|---|---|---|---|---|
| resonanceOrb | 공명의 오브 | accessory | hp 30 | sharedMana | mythic, tier5 |
| soulReaper | 영혼 착취자 | weapon | atk 35 | killMana | mythic, tier5 |
| stormFist | 폭풍의 주먹 | weapon | atk 30 | knockback | mythic, tier5 |
| dimensionMirror | 차원의 거울 | accessory | hp 20, atkSpd 0.15 | swap | mythic, tier5 |
| thunderHeart | 천둥의 심장 | accessory | atk 15, crit 0.10 | lightning | mythic, tier5 |
| eclipseBlade | 일식검 | weapon | atk 90, crit 0.35, dmgBonus 0.25 | lightning, killMana | ultra, transcendent, tier6, price 5200 |
| worldTreeSeed | 세계수의 씨앗 | accessory | hp 280, dmgReduce 0.28, atkSpd 0.25 | sharedMana | ultra, tier6, 5400 |
| voidAnchor | 공허의 닻 | armor | hp 360, atk 35, dmgReduce 0.42 | knockback | ultra, tier6, 5600 |
| chronosHourglass | 크로노스의 모래시계 | accessory | atkSpd 0.60, hp 160, crit 0.25 | sharedMana, lightning | ultra, tier6, 5800 |
| royalDecree | 왕의 칙령 | accessory | atk 100, hp 260, dmgReduce 0.30, crit 0.30 | killMana, sharedMana | ultra, tier6, 6000 |

효과 정의:
- `sharedMana`: 다른 아군이 공격 명중 시 그 마나 획득량의 50%(floor)를 장착자도 획득.
- `killMana`: 장착자가 처치 시 마나 최대 + (원본) 아무 적이나 죽으면 장착자 마나 최대.
- `knockback`: 공격 명중 시 대상을 1칸 밀어냄(swap과 동시 보유 시 무효, 넉백면역 제외).
- `swap`: 공격 명중 시 장착자와 대상 위치 교환.
- `lightning`: 3번째 공격마다 다른 랜덤 적에게 피해의 80%.

### 6.4 특수 아이템 (`SPECIAL_ITEMS`)
| key | 이름 | 종류 | 가격 | 효과 |
|---|---|---|---|---|
| revive | 부활의 깃털 | 소비 | 500 | 사망 아군 1명(가장 먼저 죽은) HP 100%로 부활. 사망자 없으면 사용 불가 |
| fullHeal | 여신의 축복 | 소비 | 300 | 모든 아군 HP 100% |
| skillPoint | 지혜의 서 | 소비 | 600 | 모든 아군 SP +1 |
| massKill | 심판의 번개 | 소비 | 800 | 모든 적 즉시 제거(**보상/처치 처리 없음**). battle 페이즈에서만 |
| inventoryExpand | 공간 확장 키트 | 소비 | 900 | 인벤토리 +3. 웨이브 20+ 처치 시 4% |
| crown | 전설의 왕관 | 장비(accessory) | 1500 | atk 50, hp 150, atkSpd 0.30, crit 0.20, dmgReduce 0.20; tier5, 3개 합성 → 초월한 왕관 |
- 소비템 사용: 인벤토리 클릭(튜토리얼 5단계 또는 튜토리얼 외). 페이즈 제한은 massKill만(battle 중). 단, 인벤토리 클릭 UI 자체는 항상 표시.
- 획득: 상인(12% 구간), inventoryExpand는 드랍도.

### 6.5 초월 아이템 (`TRANSCENDENT_ITEMS`, 같은 전설 3개 합성)
| 원본 → key | 이름 | 슬롯 | 스탯 | 효과 | tier |
|---|---|---|---|---|---|
| resonanceOrb → ascendedResonanceOrb | 초월한 공명의 오브 | acc | hp 140, atkSpd 0.35 | sharedMana, lightning | 6 |
| soulReaper → ascendedSoulReaper | 초월한 영혼 착취자 | weapon | atk 105, crit 0.25 | killMana, lightning | 6 |
| stormFist → ascendedStormFist | 초월한 폭풍의 주먹 | weapon | atk 95, dmgBonus 0.35, hp 80 | knockback, lightning | 6 |
| dimensionMirror → ascendedDimensionMirror | 초월한 차원의 거울 | acc | hp 120, atkSpd 0.45, dmgReduce 0.18 | swap, sharedMana | 6 |
| thunderHeart → ascendedThunderHeart | 초월한 천둥의 심장 | acc | atk 75, crit 0.35, atkSpd 0.35 | lightning, killMana | 6 |
| crown → ascendedCrown | 초월한 왕관 | acc | atk 140, hp 380, atkSpd 0.55, crit 0.40, dmgReduce 0.35 | sharedMana, killMana | 6 |
| eclipseBlade → ascendedEclipseBlade | 초월한 일식검 | weapon | atk 180, crit 0.50, dmgBonus 0.45 | lightning, killMana | 7 |
| worldTreeSeed → ascendedWorldTreeSeed | 초월한 세계수의 씨앗 | acc | hp 520, dmgReduce 0.45, atkSpd 0.35 | sharedMana, lightning | 7 |
| voidAnchor → ascendedVoidAnchor | 초월한 공허의 닻 | armor | hp 680, atk 70, dmgReduce 0.55 | knockback, sharedMana | 7 |
| chronosHourglass → ascendedChronosHourglass | 초월한 크로노스의 모래시계 | acc | atkSpd 0.85, hp 280, crit 0.42, atk 60 | sharedMana, lightning, killMana | 7 |
| royalDecree → ascendedRoyalDecree | 초월한 왕의 칙령 | acc | atk 220, hp 520, dmgReduce 0.45, crit 0.45, atkSpd 0.35 | killMana, sharedMana, lightning | 7 |

### 6.6 유물 (`RELIC_ITEMS`, 인벤토리 소지만으로 전체 적용, 장착 불가)
| key | 이름 | 희귀도 | 가격(판매기준) | 효과 |
|---|---|---|---|---|
| vampireChalice | 핏빛 성배 | legendary | 3600 | lifeSteal 0.20 |
| crescendoGear | 가속의 태엽심장 | legendary | 3800 | atkSpd 0.10 + 템포(공격당 +0.02, 최대 +0.30, 전투 시작 시 리셋) |
| windPilgrimBoots | 바람 순례자의 장화 | legendary | 3400 | moveSpeedBonus 0.50 |
| echoCrystal | 메아리 결정핵 | legendary | 3900 | doubleAttackChance 0.10 |
| moonlitPendant | 달빛 펜던트 | rare | 1200 | manaGainMult 0.20 |
| guardianIdol | 수호자의 작은 우상 | rare | 1100 | dmgReduce 0.08 |
| luckyCompass | 행운의 나침반 | rare | 1300 | dropBonus 0.10, goldMult 0.10 |
- 획득: 웨이브 15+ 처치 시 전설 0.3% / 희귀 1.0%. 상인 판매 없음.
- **전설 유물은 영구 보존**: 인벤토리가 바뀔 때마다 인벤토리 내 전설 유물 키 목록을 localStorage에 저장, 새 게임/재시작 시 인벤토리에 다시 넣음. 팔면 영구 목록에서도 사라짐. 중복 보유 시 효과 중첩.

### 6.7 랜덤 아이템 (`getRandomItem(wave)`)
```
wave>=25 && rand()<0.006 → ultra 전설 랜덤
elif wave>=15 && rand()<0.03 → 일반 전설 랜덤
else: family = 8종 균등; roll=rand(); tier=1
      if roll>0.55 || wave>5: tier=2
      if roll>0.82 || wave>12: tier=3
      if roll>0.96 && wave>18: tier=4
```
(즉 wave>5면 최소 2티어, wave>12면 최소 3티어, 4티어는 wave>18에서 4%.)

### 6.8 합성 (`tryMergeItems`) — 자동
- 호출 시점: 장비 획득(드랍/구매), 장착/교체 시. (소비템/스킬북/유물 제외)
- 인벤토리 + **모든 영웅 장착 장비**를 itemKey로 집계, 3개 이상인 키:
  - TRANSCENDENT_MAP에 있고 tier≥5 → 3개 제거, 초월 아이템 1개 인벤토리에 추가.
  - ITEMS(일반)이고 tier<4 → 3개 제거, 같은 family 다음 tier 1개 추가.
  - tier4 일반 장비는 합성 불가.
- 제거 우선순위: 인벤토리 엔트리 먼저, 그 다음 장착품(장착품 제거 시 해당 유닛 hp에서 그 장비 HP만큼 차감, currentHp 클램프).
- 합성 후 다시 처음부터 반복(연쇄 합성). 합성 알림 1.0초(초월 1.2초).

---

## 7. 특성

### 7.1 런 특성(퍽, `PERKS`) — 3웨이브마다 3장 중 1 선택
선택 규칙(`generatePerkSelection`): 아직 보유하지 않은 퍽만 후보. 3% 확률로 전설 1장 먼저 포함. 나머지 슬롯은 각 25% 확률로 희귀, 아니면 일반(풀이 비면 아무거나). 중복 없음. 정렬: 전설→희귀→일반. 리롤 비용 500, 리롤마다 +500, 열기/선택 시 500으로 리셋. 선택은 필수(건너뛰기 없음).
| id | 이름 | 희귀도 | 효과 |
|---|---|---|---|
| atkAll | 전투 훈련 | common | atkMult 0.12 |
| hpAll | 강인함 | common | hpMult 0.16 |
| speedAll | 신속 훈련 | common | atkSpd 0.12 |
| critAll | 약점 포착 | common | crit 0.08 |
| dmgReduce | 기초 방어술 | common | dmgReduce 0.08 |
| expBonus | 전투 기록 | common | expMult 0.25 |
| goldBonus | 잔돈 회수 | common | goldMult 0.20 |
| dropRate | 작은 행운 | common | dropBonus 0.10 |
| lifeSteal | 응급 흡혈 | common | lifeSteal 0.07 |
| rangeAll | 시야 확보 | common | range +1 |
| rareBattleRhythm | 전투 리듬 | rare | atkMult 0.18, atkSpd 0.10 |
| rareGuardianFormation | 수호 진형 | rare | hpMult 0.25, dmgReduce 0.08 |
| rareExplosiveArms | 폭발 장비 | rare | splashChance 0.20 |
| rareTreasureHunter | 보물 사냥꾼 | rare | goldMult 0.25, dropBonus 0.12 |
| rareUltMaster | 궁극기 숙련 | rare | ultCooldownReduce 0.18, crit 0.06 |
| legendDragonSoul | 용의 심장 | legendary | atkMult 0.30, hpMult 0.30, dmgReduce 0.10 |
| legendStormArmy | 폭풍 군단 | legendary | atkSpd 0.30, crit 0.18, ultCooldownReduce 0.20 |
| legendGoldenFate | 황금 운명 | legendary | goldMult 0.50, dropBonus 0.25, expMult 0.30 |
- hpMult 퍽은 선택 즉시 살아있는 각 유닛에 `hp += floor(baseHp * hpMult)`, currentHp 동일 증가(사망자/이후 부활자에는 미적용).

### 7.2 영구 특성 트리 (`TALENT_TREE_NODES`, 시간의 결정)
해금 규칙: **모든 선행 노드가 최대 레벨**이어야 구매 가능. 비용은 `costs[현재레벨]`. 구매는 placement/transition의 "특성 트리" 버튼(튜토리얼 중 비활성). 효과는 레벨 × 값으로 합산(불리언은 OR).
좌표(x,y)는 트리 화면용(900×805 캔버스).

| id | 분기 | 이름 | max | 비용 | 선행 | 효과(레벨당) |
|---|---|---|---|---|---|---|
| root | core | 시간의 뿌리 | 1 | [0] | — | 없음(시작점) |
| startGold | core | 시간의 축복 | 5 | 2,3,5,8,12 | root | 시작 골드 +50 |
| allAtk | core | 반복 전투술 | 5 | 2,4,6,9,13 | root | 전체 atkMult +0.02 (원본에서 2중 적용 버그) |
| allHp | core | 생존 기억 | 5 | 2,4,6,9,13 | root | 전체 hpMult +0.02 (유닛 생성 시에만 적용) |
| waveHeal | core | 빠른 정비 | 5 | 3,5,8,12,16 | root | 웨이브 종료 회복 +10 |
| crystalSense | core | 결정 감응 | 5 | 5,8,12,18,25 | startGold | 결정 드랍 확률 +0.005 |
| itemSense | core | 장비 감별 | 5 | 4,7,11,16,22 | allAtk | dropBonus +0.01 |
| battleRecord | core | 전투 기록 | 5 | 3,5,8,12,16 | allHp | expMult +0.03 |
| emergencySupply | core | 비상 보급 | 1 | [15] | waveHeal | 시작 시 랜덤 1티어 장비 1개 |
| secondChance | core | 두 번째 기회 | 1 | [30] | waveHeal | 런 중 첫 사망 영웅 1회 HP30% 부활 |
| timeCore | core | 시간의 핵 | 1 | [40] | crystalSense | 없음(직업 최종 노드 선행) |
| warAtk | warrior | 붉은 단련 | 5 | 2,4,6,9,13 | root | 전사 atkMult +0.03 |
| warHp | warrior | 강철 체력 | 5 | 2,4,6,9,13 | warAtk | 전사 hpMult +0.04 |
| warReduce | warrior | 방패 숙련 | 5 | 3,5,8,12,16 | warHp | 전사 dmgReduce +0.02 |
| warCounter | warrior | 반격 자세 | 5 | 4,7,11,16,22 | warReduce | 전사 counterChance +0.04 |
| warUlt | warrior | 충격파 강화 | 3 | 8,15,25 | warReduce | 전사 궁 피해 +0.10 |
| warTaunt | warrior | 도발의 함성 | 1 | [18] | warHp | 전사 생존 시 모든 아군 받는 피해 -0.03 |
| warLastStand | warrior | 불굴 | 1 | [25] | warTaunt | 전사 HP≤30%일 때 피해감소 +0.15 |
| warFinal | warrior | 영원의 방패 | 1 | [50] | timeCore, warLastStand | 전사 사망 시 1회 HP50% 부활 |
| rngAtk | ranger | 초록 단련 | 5 | 2,4,6,9,13 | root | 궁수 atkMult +0.03 |
| rngSpeed | ranger | 빠른 손놀림 | 5 | 2,4,6,9,13 | rngAtk | 궁수 atkSpd +0.03 |
| rngCrit | ranger | 명중 훈련 | 5 | 3,5,8,12,16 | rngSpeed | 궁수 crit +0.02 |
| rngRange | ranger | 긴 사거리 | 1 | [18] | rngCrit | 궁수 range +1 |
| rngBoss | ranger | 약점 추적 | 3 | 7,14,24 | rngCrit | 보스/정예 피해 +0.05 — **원본 미구현(효과 없음)** |
| rngGold | ranger | 화살 회수 | 5 | 4,7,11,16,22 | rngSpeed | 궁수 처치 시 추가 골드 max(1,floor(10×0.02×lv)) |
| rngLoot | ranger | 전리품 감각 | 1 | [35] | rngGold | dropBonus +0.05 |
| rngFinal | ranger | 시간 사냥꾼 | 1 | [50] | timeCore, rngLoot | 결정 드랍 확률 +0.02 |
| magAtk | mage | 보라 단련 | 5 | 2,4,6,9,13 | root | 마법사 atkMult +0.03 |
| magMana | mage | 마나 순환 | 5 | 2,4,6,9,13 | magAtk | 마법사 manaGainMult +0.03 |
| magSpeed | mage | 주문 가속 | 5 | 3,5,8,12,16 | magAtk | 마법사 atkSpd +0.02 |
| magFrost | mage | 냉기 숙련 | 3 | 5,10,18 | magMana | mageFreezeBonus 0.05 — **원본 미구현(효과 없음)** |
| magChain | mage | 연쇄 전류 | 3 | 10,18,30 | magSpeed | 마법사 궁 튕김 +1 |
| magUltCool | mage | 폭풍의 눈 | 1 | [40] | magFrost, magChain | 마법사 궁 쿨 -0.20 |
| magFinal | mage | 시간 마도사 | 1 | [55] | timeCore, magUltCool | 마법사 궁 사용 시 10% 결정 +1 |

노드 좌표: root(450,315) startGold(450,230) allAtk(360,280) allHp(540,280) waveHeal(450,395) crystalSense(450,145) itemSense(295,230) battleRecord(605,230) emergencySupply(360,395) secondChance(540,395) timeCore(450,60) / warAtk(585,350) warHp(660,405) warReduce(735,460) warCounter(675,515) warUlt(800,555) warTaunt(775,385) warLastStand(835,465) warFinal(840,300) / rngAtk(315,350) rngSpeed(240,405) rngCrit(165,460) rngRange(225,515) rngBoss(100,555) rngGold(125,385) rngLoot(65,465) rngFinal(60,300) / magAtk(450,500) magMana(370,560) magSpeed(530,560) magFrost(285,620) magChain(615,620) magUltCool(450,675) magFinal(450,745).

적용 시점 주의:
- 시작 골드, 비상 보급, HP%(allHp/warHp)는 **유닛/런 생성 시**만 반영(런 도중 구매 시 다음 런부터).
- 공격력·공속·치명·사거리·피해감소·마나·쿨·드랍·경험치·결정·회복은 런 도중 구매 즉시 반영.
- 구매 실패 메시지: "🔒 앞선 특성을 먼저 해금해야 합니다." / "🔷 시간의 결정이 N개 부족합니다." 성공: "🌌 {이름} {lv}/{max} 해금!"

### 7.3 스탯 합산 출처 정리
- perkEffects(전체 공용) = 퍽 + 유물 + 특성트리 공용(atkMult, hpMult, goldMult, dropBonus, expMult, crystalDropBonus, waveHealBonus).
- unitTalent(직업별) = 특성트리 공용 atkMult/hpMult + 직업 노드.
- 상한: 공속 합 0.7, 이동속도 합 0.75, 피해감소 합 0.9, 회피 0.75, 궁 쿨감 0.85. 치명/폭발/관통/반격은 상한 없음(1 이상이면 항상 발동).

---

## 8. 튜토리얼 (페이지 첫 로드 시 단계 1부터, 저장 안 됨, 재시작 시 생략)

튜토리얼 중(`step > 0`)에는 현재 단계의 행동만 허용(`isTutorialActionAllowed`):
| 행동 | 허용 단계 |
|---|---|
| 유닛 드래그 | 1 |
| 전투 시작 | 2, 4 |
| 유닛 선택, 스킬 UP | 3 |
| 궁극기 길게 누르기 | 4 (마법사만) |
| 아이템 드래그/판매/사용/장착 | 5 |
특성 트리·가이드 버튼, 판매 모드 버튼(5단계 제외)은 튜토리얼 중 비활성.

| 단계 | 제목 | 안내문 | 완료 조건 / 처리 |
|---|---|---|---|
| 1 | 캐릭터 배치 | 전사, 궁수, 마법사를 각각 한 번씩 원하는 위치로 옮겨보세요! (n/3) | 서로 다른 유닛 3명(min(3,유닛수))을 각각 다른 칸으로 1회 이상 이동 → 2단계 |
| 2 | 전투 시작 | 반짝이는 "⚔️ 전투 시작!" 버튼을 눌러보세요! | wave1에서 전투 시작 → step=0, pending3=true. 적 2마리: (1,0),(4,0), HP 5, ATK 1, 사거리 1, 공격/이동 간격 2000 (배율 없음) |
| 3 | 스킬 업그레이드 | 반짝이는 영웅을 클릭한 후, "UP" 버튼으로 스킬을 올려보세요! | 웨이브1 종료 시(pending3): 모든 유닛 SP = max(SP,1), 인벤토리 비었으면 sword1 지급, step=3. 아무 스킬 UP 클릭 → step=4, 선택 해제 |
| 4 | 마법사 스킬 사용 | 전투를 시작한 후 마법사를 길게 눌러서 궁극기로 여러명의 적들을 공격해보세요! 전사와 궁수도 같은 방법으로 궁극기를 사용할 수 있습니다! | 전투 시작 시 마법사 궁 쿨 0, 적 2마리 (1,0),(4,0), HP 280, ATK 1, 간격 3200 (메시지 "✨ 마법사 궁극기를 사용해보세요!"). 마법사 궁 발동 → step=0, pending5=true, "✨ 마법사 궁극기 사용 성공!". 궁을 안 쓰고 웨이브를 끝내면 다음 웨이브도 4단계 반복 |
| 5 | 아이템 장착 / 판매 | 반짝이는 아이템을 드래그해서 장착하거나, "아이템 판매" 버튼으로 판매해보세요! | 웨이브 종료 시(pending5): 인벤토리 비었으면 sword1, step=5. 아이템 장착 또는 판매 → step=0(튜토리얼 종료) |
- 4단계에서 wave≥3이면 기믹(45%)이 튜토리얼 적 생성보다 우선되는 엣지 케이스 있음.

---

## 9. UI (필요 정보만)

- 상단 HUD: 웨이브(서브웨이브 n/m), 페이즈 상태, 남은 적 수, 골드, 시간의 결정, 배율.
- 보드: 6×8 그리드, 구역 구분(적 생성/배치 가능), 드래그 시 배치 미리보기.
- 영웅 표시: HP바, 마나바, EXP바, 레벨, SP 보유 배지(+n), 궁 준비 표시(전투 중), 장착 장비 아이콘, 가드 상태, 선택/장착 대상 하이라이트.
- 적 표시: HP바, 종류 아이콘, 상태(빙결/스턴/슬로우/무적 환영/넉백면역 "불굴"), 죽은 히드라 부활 진행도.
- 기믹 안내 문구, 중앙 알림 메시지(gimmickMessage, 1.2~2초).
- 유닛 상세 패널(placement/transition에서 선택 시): HP(현재/최대), ATK, 사거리, 이동속도 보너스, 장비 3슬롯, SP, 스킬 3개(레벨 점, 설명, UP 버튼 / 스킬북은 경험치 Lv x/5), 고유 스킬·궁극기 설명.
  - 원본 표시 버그: 최대 HP를 `u.hp + 장비hp`로 표시(u.hp에 이미 장비 HP 포함 → 중복).
- 인벤토리: n/용량, 슬롯 그리드, 판매 모드 토글(placement/transition), 아이템 툴팁(이름, 희귀도, 스탯, 유물 효과, 추가 옵션, 가격, 효과 키, 설명).
- 하단 버튼(placement/transition, 오버레이 없을 때): 특성 트리 / 전투 시작(복귀 중이면 "복귀 중...") / 가이드(?).
- 팝업: 특성(퍽) 선택(카드 3, 리롤 비용, 보유 골드), 상인(4상품, 리롤 300G, 닫기, 판매 목록), 스킬북 개봉(교체 슬롯 선택/버리기), 영구 특성 트리(분기별 진행도 n/total, 노드 레벨/비용/잠김, 툴팁), 게임 설명서, 게임오버(다시 시작), 합성 알림, 40웨이브 커피 보상, 마지막 영웅 팁, 튜토리얼 안내 박스.
- 궁극기 조준 표시: 일시정지 표시 + 타입별 범위 미리보기(전사: 전체/원, 마법사: 연쇄 경로, 궁수: 원뿔+해당 칸) + 피격 예정 적 하이라이트.

## 10. 이벤트별 피드백 (새 VFX/SFX 매핑용 목록, 원본에 사운드 없음)

| 이벤트 | 필요한 피드백 |
|---|---|
| 적 등장 | 등장 이펙트 |
| 영웅 배치 | 배치 확인 이펙트 |
| 영웅 일반 공격 | 전사 근접 베기 / 궁수 화살 투사체 / 마법사 곡선 볼트 2발 / 적 투사체 |
| 명중 | 피격 이펙트(+화면 흔들림 짧게), 피해 숫자(일반/치명타 구분), 영웅 피해 숫자 |
| 치명타 | "CRITICAL" 텍스트 |
| 회피·환영 무적 | "IMMUNE" 텍스트 |
| 추가 공격(유물) | "추가 공격!" 텍스트 |
| 빙결 발동 | 냉기 피격 |
| 번개 장비 / 체인 라이트닝 | 번개 줄기, 전기 잔상 |
| 위치 교환 | 양쪽 위치 표시 |
| 고유 스킬 발동 | 스킬 아이콘 팝업, 유닛 섬광; 전사 점프 궤적+착지 충격파, 궁수 3연사, 마법사 냉기 파동 |
| 궁극기 | 전사 충격파 링, 궁수 원뿔 영역+화살비+틱 피해 숫자, 마법사 연쇄 번개(시전자 이동 표현) |
| 닌자 점프 / 분열 | 점프 궤적+착지, 분열체 등장 |
| 적 처치 | 골드 코인 드랍(웨이브 종료 시 회수 연출), 아이템 드랍(유물은 강조), 결정 획득 텍스트 |
| 자동 판매 | +nG 텍스트 |
| 부활(깃털/특성/히드라) | 부활 이펙트 |
| 합성 | 합성 알림 |
| 특성 트리 구매 | 노드 해금 연출 |
| 웨이브 클리어 | 결정 +2 알림, 위치 복귀 |
| 40웨이브 | 커피 보상 연출 |
| 게임오버 | 게임오버 화면 |

---

## 11. 저장 (localStorage)

| 키 | 내용 | 형식 |
|---|---|---|
| `gridDefensePermanentTalentTree_v1` | 특성 트리 레벨 | JSON 객체 `{ nodeId: level }` |
| `gridDefenseTimeCrystals_v1` | 시간의 결정 | 정수 문자열 (음수/파싱 실패 시 0) |
| `gridDefensePermanentLegendaryRelics_v1` | 보유 전설 유물 키 목록 | JSON 배열 `["vampireChalice", ...]` (legendary 유물만 필터) |
- 상태 변경 즉시 저장. 런 진행(웨이브, 유닛, 골드, 인벤토리 일반 아이템)은 저장되지 않음 — 새로고침 시 1웨이브부터(튜토리얼 포함).
- 특성 레벨 읽을 때 `0..max`로 클램프.

---

## 12. 밸런스 상수 · 랜덤 · 엣지 케이스 · 원본 버그

상수 모음: 공격 속도 상한 0.7, 이동 0.75, 피해감소 0.9, 회피 0.75, 궁쿨감 0.85, 가드 0.5, 웨이브 회복 50, 처치 EXP 25, 레벨업 필요 lv×40, 레벨업 +15HP/+8ATK/+30회복, 짝수 레벨 SP+1, 스킬 max 3, 스킬북 max 5 (필요 70+lv×55), 빙결 슬로우 2000ms(속도 2배 느려짐), 스플래시 50%, 관통 70%, 번개 80%, sharedMana 50%, 결정 기본 5%, 클리어 결정 2, 상인 리롤 300, 퍽 리롤 500(+500), 기믹 확률 45%(wave≥3), 히드라 부활 2000ms, 닌자 점프 쿨 1700ms, 순차 등장 170ms(+420ms), 서브웨이브 지연 800ms, 웨이브 종료 처리 700ms, 골드 회수 600ms, 복귀 확인 430ms, 궁 홀드 300ms, 전투 시작 디바운스 600ms, 시뮬 스텝 33ms.

원본 버그/주의(포팅 시 결정 필요):
1. 특성 '반복 전투술' 공격력 보너스 2중 적용(§3.5).
2. 전사 '생명력' 스킬 업 시 최대 HP가 200+bonusHp로 재설정되어 다른 HP 증가분 소실.
3. 상세 패널/HP바 최대 HP가 장비 HP 중복 가산(`u.hp + itemStats.hp`). HP바 비율도 이 값 기준.
4. 폭발/관통/번개 장비 피해는 환술사 생존 중 환영에게도 들어감(무적 미적용).
5. `rngBoss`(약점 추적), `magFrost`(냉기 숙련) 특성은 효과 미구현.
6. killMana: 어떤 적이든 죽으면 killMana 보유자 전원 마나 최대.
7. 심판의 번개(massKill)는 처치 보상(골드/EXP/드랍/분열)을 전혀 주지 않음.
8. 충격파 궁: 미리보기는 반경 원이지만 실제로는 맵 전체 적 적중.
9. 체인 라이트닝 미리보기는 특성 튕김 보너스 미반영.
10. 시뮬레이션 시간(simNow)과 실시간(Date.now()) 혼용: 스턴/슬로우/빙결/가드/궁 쿨/히드라 부활은 실시간 기준이라 궁 조준 일시정지 중에도 만료됨. Godot에서는 게임 시간 하나로 통일 권장.
11. 스플래시는 무적/히드라 시체 포함 모든 적(dist≤1)에 적용(HP<=0 시체에도 감산되나 무해).
12. 영웅 이동 시 점유 판정에 죽은 히드라 시체 포함(시체가 길을 막음), 적 이동에서는 제외.
13. 스프린터 2칸 대시는 중간 칸 막힘을 무시(점프).
14. 위치 교환(swap)은 점유 검사 없이 교환.
15. 상인 표시 판매가 ≠ 실제 판매가(유물/스킬북).
16. 스킬북 '광전사의 분노' 설명(체력 낮을수록)과 실제(상시 고정) 불일치. 빙결 설명 "1턴"이지만 실제 2000ms 슬로우.
17. 게임오버 시 바닥에 떨어진 미회수 골드는 소실.
18. 런 도중 특성 트리 HP%/시작골드/비상보급 구매는 다음 런부터 반영.
19. 부활 특성(secondChance/warFinal)은 "런당 1회"(재시작 시 리셋).
20. 튜토리얼 4단계에서 wave≥3 기믹이 우선될 수 있음.

랜덤 사용처: 기믹 선택, 적 종류/위치, 아이템 드랍·종류·티어·추가옵션, 결정 드랍, 유물/스킬북/키트 드랍, 치명·폭발·관통·빙결·반격·회피·추가공격, 번개 대상, 상인 상품, 퍽 카드, 시작 장비, 환술사 진짜 위치, 이펙트 산포.

---

## 13. 코드 인덱스 (원본 라인)

| 범위 | 이름 | 내용 |
|---|---|---|
| 1-18 | HTML head | React/Babel CDN, 기본 스타일 |
| 28 | GAME_VERSION | |
| 34 | GRID_W/H, CELL, MAX_INVENTORY | |
| 35-46 | ITEM_TIERS, ITEM_SELL_PRICES, ITEM_BUY_PRICES | |
| 47-58 | LEGENDARY_ITEMS | |
| 60-68 | RELIC_ITEMS | |
| 69-85 | TRANSCENDENT_ITEMS, TRANSCENDENT_MAP | |
| 86-93 | SPECIAL_ITEMS | |
| 94-127 | ITEMS | |
| 128-152 | PERKS, PERK_RARITY_META | |
| 154-201 | 저장 키, TALENT_TREE_NODES, TALENT_BRANCH_META | |
| 202-238 | readPermanentTalentTree, readTimeCrystals, getTalentLevel, getTalentEffects, getUnitTalentEffects, applyTalentHpToUnit, createInitialUnitsWithTalents | |
| 239-278 | RARITY_COLORS, isHighRarityItem, resolveItemData, getItemEffects, resolveInventoryItemData, rollMoveSpeedBonus, makeInventoryEntry, 영구 유물 읽기/저장 | |
| 279 | DROP_RATES | |
| 280-320 | SKILLS, SKILLBOOK_SKILLS, SKILLBOOK_TYPES, getSkillBookExpNeed, createSkillBookDrop, getDisplayedSkill(Level), makeSkillBookItemData | |
| 321-335 | ULTIMATES, UNIT_TYPES, ACTIVE_SKILLS | |
| 341-370 | genId, dist, pixelDist, findNearest/Farthest, getScalingMultiplier, getRandomItem | |
| 371-432 | getMoveDir, getEntitySize, entityOccupiesCell, isCellBlocked, canEnemyOccupy, getDashMoveDir, getSizedEnemyMoveDir, getNinjaLandingCell, getEnemyIcon | |
| 433-466 | getSkillEffects, getItemStats, getEquipmentEffects, createUnit | |
| 467-529 | getEnemiesInLine(미사용), angleDiff, getConeCells, isInCone, getGridLineCells(미사용), getNearestEmptyCell, getPushCell | |
| 530-554 | createEnemy (적 스탯표) | |
| 560-580 | TutorialOverlay | 튜토리얼 문구 |
| 584-611 | GuideModal | 게임 설명서 |
| 614-717 | TalentTreeModal | 특성 트리 UI/해금 판정 |
| 724-790 | GridDefenseGame: state | |
| 792-871 | refs, 동기화 effect, 복귀 완료 판정, 마지막 영웅 팁 | |
| 874-886 | isTutorialActionAllowed | |
| 889-919 | getPerkEffects, getUnitAttackPower | |
| 921-957 | grantCombatExp | 레벨업 |
| 960-990 | generateMerchantItems | |
| 992-1052 | tryMergeItems | |
| 1054-1107 | addEffect, awardTimeCrystals, buyTalentNode, dropGold, collectAllGold, spawnHit | |
| 1109-1146 | addToInventory, sellItem | |
| 1148-1217 | handleEnemyKill | 보상/드랍 |
| 1219-1287 | useSkillBook, replaceSkillWithBook, discardRevealedSkillBook, useSpecialItem | |
| 1290-1389 | executeActiveSkill | 고유 스킬 |
| 1391-1510 | executeUltimate | 궁극기 |
| 1513-1749 | fireProjectile | 공격/피해 판정 |
| 1751-1790 | upgradeSkill, equipItem | |
| 1793-1846 | 퍽 선택 생성/리롤/선택 | |
| 1848-1885 | buyFromMerchant, rerollMerchant, closeMerchant | |
| 1888-1971 | 입력: handleUnitClick, handleDragStart, handleBattleHoldStart, handleItemDragStart, handleMouseMove, handleMouseUp | |
| 1974-2028 | randomFreeTopCell, createGimmickEnemies, spawnSubWave | |
| 2031-2060 | spawnEnemiesSequentially | |
| 2062-2092 | finishWave | |
| 2094-2170 | startBattle | 기믹/튜토리얼 적 |
| 2172-2191 | restartGame | |
| 2194-2207 | updateUnitsSim, updateEnemiesSim | |
| 2210-2345 | 전투 루프(tick + 고정스텝 RAF) | |
| 2348-2426 | renderEffect | 이펙트 종류 |
| 2428-2476 | renderUltPreview, getUnitTotalStats, getUltTargetEnemies, battleStartLocked | |
| 2479-2742 | JSX 레이아웃(HUD, 보드, 패널, 인벤토리, 버튼, 팝업들, 툴팁) | |
| 2748-2749 | 부트스트랩 | |
