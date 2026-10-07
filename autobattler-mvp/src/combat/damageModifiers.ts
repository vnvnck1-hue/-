import type { GameState } from "../core/GameState";
import type { HeroClass } from "../core/Types";
import type { Enemy } from "../entities/Enemy";

/** 엘리트 실드: 살아있는 엘리트가 있으면 비엘리트가 받는 피해 감소 */
export function partyDamageMultiplier(
  enemy: Enemy,
  state: GameState,
  attackerClass: HeroClass | null,
): number {
  let m = 1;
  const t = state.time;
  if (t <= enemy.markedUntil) {
    if (attackerClass === "archer") m *= 1.22;
    if (attackerClass === "mage") m *= 1.18;
  }
  if (t <= enemy.shockedUntil) {
    if (attackerClass === "warrior") m *= 1.15;
  }
  if (state.waveModifier === "eliteShield") {
    const elite = state.enemies.find((e) => e.isElite && e.alive);
    if (elite && enemy.id !== elite.id) m *= 0.55;
  }
  return m;
}

export function applyRoundedDamage(
  enemy: Enemy,
  raw: number,
  state: GameState,
  attackerClass: HeroClass | null,
  dir: { x: number; y: number },
  knockbackMul: number,
): number {
  const dmg = Math.max(1, Math.round(raw * partyDamageMultiplier(enemy, state, attackerClass)));
  enemy.takeDamage(dmg, dir, knockbackMul);
  return dmg;
}
