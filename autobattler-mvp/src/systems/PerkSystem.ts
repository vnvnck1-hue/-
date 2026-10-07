import type { GameState } from "../core/GameState";
import type { PerkData } from "../core/Types";
import { pickN } from "../core/Random";

export const PERKS: PerkData[] = [
  {
    id: "atk",
    name: "공격 훈련",
    desc: "파티 공격력 +20%",
    apply: (s) => {
      s.buffs.atkMul *= 1.2;
    },
  },
  {
    id: "atkSpd",
    name: "연사",
    desc: "파티 공격속도 +18%",
    apply: (s) => {
      s.buffs.atkSpdMul *= 1.18;
    },
  },
  {
    id: "hp",
    name: "생명력",
    desc: "파티 최대 체력 +25%",
    apply: (s) => {
      s.buffs.hpMul *= 1.25;
      for (const h of s.heroes) {
        h.heal(h.maxHp * 0.25);
      }
    },
  },
  {
    id: "explode",
    name: "강화 마탄",
    desc: "마법사 폭발 범위 +30%",
    apply: (s) => {
      s.buffs.explosionMul *= 1.3;
    },
  },
  {
    id: "lifesteal",
    name: "흡혈",
    desc: "공격 데미지의 8%만큼 회복",
    apply: (s) => {
      s.buffs.lifesteal += 0.08;
    },
  },
  {
    id: "crit",
    name: "치명 강화",
    desc: "치명타 확률 +12%",
    apply: (s) => {
      s.buffs.critChance += 0.12;
    },
  },
  {
    id: "critDmg",
    name: "정밀 타격",
    desc: "치명타 피해 +30%",
    apply: (s) => {
      s.buffs.critMul += 0.3;
    },
  },
  {
    id: "regen",
    name: "전열 정비",
    desc: "지금 즉시 모든 영웅 체력 회복",
    apply: (s) => {
      for (const h of s.heroes) h.heal(h.maxHp * 0.5);
    },
  },
];

export function rollPerks(): PerkData[] {
  return pickN(PERKS, 3);
}

/** 특성을 적용해야 할 웨이브 번호인지 (3 웨이브마다) */
export function shouldShowPerks(state: GameState): boolean {
  const totalWaveIndex = (state.stage - 1) * 5 + state.wave;
  return totalWaveIndex > 0 && totalWaveIndex % 3 === 0;
}
