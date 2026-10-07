import type { Hero } from "../entities/Hero";
import type { Enemy } from "../entities/Enemy";
import type { Projectile } from "../entities/Projectile";
import type { Pickup } from "../entities/Pickup";
import type { Effect } from "../effects/Effect";
import type { ItemData } from "./Types";
import { Camera } from "./Camera";

export type GamePhase =
  | "intro"
  | "wavePrep"
  | "fighting"
  | "waveCleared"
  | "perkChoice"
  | "stageClear"
  | "gameOver";

/** 모든 시스템이 공유하는 게임 상태 컨테이너. */
export class GameState {
  heroes: Hero[] = [];
  enemies: Enemy[] = [];
  projectiles: Projectile[] = [];
  pickups: Pickup[] = [];
  effects: Effect[] = [];

  inventory: ItemData[] = [];
  gold = 0;

  stage = 1;
  wave = 0;
  totalWaves = 1;
  enemiesAlivePeak = 0;

  phase: GamePhase = "intro";
  phaseTimer = 0;

  time = 0;
  camera = new Camera();

  // 파티 단위 보너스 (특성 시스템에서 누적)
  buffs = {
    atkMul: 1,
    atkSpdMul: 1,
    hpMul: 1,
    explosionMul: 1,
    lifesteal: 0,
    critChance: 0.05,
    critMul: 1.6,
  };

  perksTaken = 0;

  /** 이번 웨이브 규칙: 시간 보너스 / 엘리트 실드 / 없음 */
  waveModifier: "none" | "timeBonus" | "eliteShield" = "none";
  /** timeBonus일 때 남은 초 (0이면 보너스 없음) */
  waveTimeLeft = 0;

  /** 선택하여 적용된 특성(순서대로). */
  appliedPerks: { id: string; name: string; desc: string }[] = [];

  reset(): void {
    this.heroes = [];
    this.enemies = [];
    this.projectiles = [];
    this.pickups = [];
    this.effects = [];
    this.inventory = [];
    this.gold = 0;
    this.stage = 1;
    this.wave = 0;
    this.totalWaves = 1;
    this.enemiesAlivePeak = 0;
    this.phase = "intro";
    this.phaseTimer = 0;
    this.time = 0;
    this.perksTaken = 0;
    this.appliedPerks = [];
    this.waveModifier = "none";
    this.waveTimeLeft = 0;
    this.buffs = {
      atkMul: 1,
      atkSpdMul: 1,
      hpMul: 1,
      explosionMul: 1,
      lifesteal: 0,
      critChance: 0.05,
      critMul: 1.6,
    };
  }
}
