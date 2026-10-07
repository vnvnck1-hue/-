import type { GameState } from "../core/GameState";
import { Pickup } from "../entities/Pickup";
import { rollItem } from "./ItemSystem";
import { chance, randInt } from "../core/Random";
import type { Enemy } from "../entities/Enemy";

/** 적 사망 시 호출 */
export function dropFromEnemy(enemy: Enemy, state: GameState): void {
  const goldMul = enemy.isBoss ? 1.4 : enemy.isElite ? 1.25 : 1;
  // 골드 (여러 코인으로 분리해서 튀어오르게)
  const totalGold = enemy.cfg.gold * (1 + (state.stage - 1) * 0.4) * goldMul;
  const coins = Math.min(6, Math.max(1, Math.round(totalGold / 3)));
  const each = Math.max(1, Math.round(totalGold / coins));
  for (let i = 0; i < coins; i++) {
    state.pickups.push(new Pickup(enemy.pos, "gold", each));
  }
  // 아이템 드랍
  if (chance(enemy.cfg.itemDropChance + state.stage * 0.01)) {
    const item = rollItem(state.stage);
    state.pickups.push(new Pickup(enemy.pos, "item", 1, item));
  }
  // 힐링 코어 (가끔): 흡수 시 최대 체력의 일부 회복
  const healCoreChance = 0.11 + state.stage * 0.012;
  if (chance(healCoreChance)) {
    const pct = 10 + randInt(0, 5);
    state.pickups.push(new Pickup(enemy.pos, "healCore", pct));
  }
}
