import type { Vec2, Faction } from "../core/Types";

let _idSeq = 0;

export abstract class Entity {
  readonly id: number = ++_idSeq;
  pos: Vec2;
  vel: Vec2 = { x: 0, y: 0 };
  radius = 10;
  faction: Faction;
  alive = true;

  hp: number;
  maxHp: number;

  /** 일시적인 시각 효과 - 피격 플래시 (0 ~ 1). */
  hitFlash = 0;
  /** 피격 시 살짝 커지는 스케일 애니메이션 (1 = 기본). */
  squash = 1;
  /** 넉백 누적 속도 (별도 vel과 합쳐 적용). */
  knockback: Vec2 = { x: 0, y: 0 };

  constructor(faction: Faction, pos: Vec2, hp: number) {
    this.faction = faction;
    this.pos = { ...pos };
    this.hp = hp;
    this.maxHp = hp;
  }

  takeDamage(amount: number, fromDir?: Vec2, knockbackMul = 1): void {
    if (!this.alive) return;
    this.hp -= amount;
    this.hitFlash = 1;
    this.squash = 1.18;
    if (fromDir) {
      const len = Math.hypot(fromDir.x, fromDir.y) || 1;
      const force = 60 * knockbackMul;
      this.knockback.x += (fromDir.x / len) * force;
      this.knockback.y += (fromDir.y / len) * force;
    }
    if (this.hp <= 0) {
      this.hp = 0;
      this.alive = false;
    }
  }

  heal(amount: number): void {
    if (!this.alive) return;
    this.hp = Math.min(this.maxHp, this.hp + amount);
  }

  baseUpdate(dt: number): void {
    if (this.hitFlash > 0) {
      this.hitFlash = Math.max(0, this.hitFlash - dt * 4);
    }
    if (this.squash !== 1) {
      this.squash += (1 - this.squash) * Math.min(1, dt * 12);
      if (Math.abs(this.squash - 1) < 0.01) this.squash = 1;
    }
    // 넉백 감쇠
    this.knockback.x *= Math.max(0, 1 - dt * 8);
    this.knockback.y *= Math.max(0, 1 - dt * 8);
  }

  abstract update(dt: number, ctxState: import("../core/GameState").GameState): void;
  abstract draw(ctx: CanvasRenderingContext2D): void;
}
