import type { GameState } from "../core/GameState";
import { Enemy } from "../entities/Enemy";
import type { EnemyKind } from "../core/Types";
import { BATTLE_LEFT, BATTLE_RIGHT, BATTLE_TOP, BATTLE_BOTTOM } from "../core/Types";
import { randInt } from "../core/Random";

/** 스테이지 번호 → 이번 스테이지의 총 웨이브 수 */
export function wavesForStage(stage: number): number {
  if (stage <= 2) return 1;
  if (stage <= 5) return randInt(2, 3);
  return Math.min(5, 3 + Math.floor((stage - 5) / 2));
}

/**
 * 웨이브를 구성한다. 스테이지/웨이브 번호에 따라 적 종류와 수가 증가.
 */
export function spawnWave(state: GameState): void {
  const stage = state.stage;
  const wave = state.wave;
  const baseCount = 3 + Math.floor(stage * 0.7) + Math.floor(wave * 0.4);
  const count = Math.min(14, baseCount);
  const scale = 1 + (stage - 1) * 0.18 + (wave - 1) * 0.05;

  // === 무리(클러스터) 스폰: 전투 필드 전역 랜덤 지점에 뭉쳐서 생성 ===
  // 무리 개수는 2~4개, 후반일수록 약간 증가
  const clusterCount = Math.min(5, Math.max(2, 2 + Math.floor(stage / 4)));
  const clusters = Math.min(clusterCount, Math.max(1, Math.ceil(count / 3)));

  let spawned = 0;
  for (let c = 0; c < clusters; c++) {
    // 클러스터 중심점: 전투 필드 전역 랜덤
    const cx = BATTLE_LEFT + 22 + Math.random() * (BATTLE_RIGHT - BATTLE_LEFT - 44);
    const cy = BATTLE_TOP + 18 + Math.random() * (BATTLE_BOTTOM - BATTLE_TOP - 60);

    // 클러스터 당 개체 수: 남은 수 기반으로 3~6 사이
    const remain = count - spawned;
    const groupSize = Math.max(2, Math.min(6, remain - (clusters - c - 1)));

    // 클러스터 내 배치 반경 (작게 잡아 뭉치게)
    const spread = 18 + Math.random() * 12; // 18~30

    for (let i = 0; i < groupSize; i++) {
      const kind = rollEnemyKind(stage);
      // 너무 띄엄띄엄해지지 않도록 중심 근처에 편향
      const a = Math.random() * Math.PI * 2;
      const r = (Math.random() ** 0.7) * spread;
      let x = cx + Math.cos(a) * r;
      let y = cy + Math.sin(a) * r;
      x = clamp(x, BATTLE_LEFT + 14, BATTLE_RIGHT - 14);
      y = clamp(y, BATTLE_TOP + 14, BATTLE_BOTTOM - 18);
      state.enemies.push(new Enemy(kind, { x, y }, scale));
      spawned++;
      if (spawned >= count) break;
    }
    if (spawned >= count) break;
  }

  // 보스 웨이브: 마지막 웨이브에 페이즈 보스 오크 (스테이지 4부터)
  if (stage >= 4 && wave === state.totalWaves) {
    state.enemies.push(
      new Enemy(
        "orc",
        {
          x: BATTLE_LEFT + 22 + Math.random() * (BATTLE_RIGHT - BATTLE_LEFT - 44),
          y: BATTLE_TOP + 18 + Math.random() * (BATTLE_BOTTOM - BATTLE_TOP - 60),
        },
        scale * 1.6,
        { boss: true },
      ),
    );
  }

  assignWaveRules(state);

  const pool = state.enemies.filter((e) => !e.isBoss);
  const pickList = pool.length ? pool : state.enemies;
  if (pickList.length > 0) {
    pickList[randInt(0, pickList.length - 1)]!.applyElite();
  }

  state.enemiesAlivePeak = state.enemies.length;
}

function assignWaveRules(state: GameState): void {
  state.waveModifier = "none";
  state.waveTimeLeft = 0;
  if (state.stage < 2 || state.wave < 1) return;
  const r = Math.random();
  if (r < 0.3) {
    state.waveModifier = "timeBonus";
    state.waveTimeLeft = 34 + state.stage * 2;
  } else if (r < 0.52) {
    state.waveModifier = "eliteShield";
  }
}

function rollEnemyKind(stage: number): EnemyKind {
  const r = Math.random();
  if (stage >= 4 && r < 0.06) return "brute";
  if (stage >= 3 && r < 0.11) return "shaman";
  if (stage >= 3 && r < 0.17) return "charger";
  if (stage >= 3 && r < 0.28) return "orc";
  if (stage >= 2 && r < 0.48) return "goblinArcher";
  return "goblin";
}

function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}
