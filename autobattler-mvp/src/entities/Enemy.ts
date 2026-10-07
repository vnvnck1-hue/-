import { Entity } from "./Entity";
import type { GameState } from "../core/GameState";
import type { EnemyKind, Vec2 } from "../core/Types";
import {
  COLORS,
  BATTLE_TOP,
  BATTLE_BOTTOM,
  BATTLE_LEFT,
  BATTLE_RIGHT,
} from "../core/Types";
import { Projectile } from "./Projectile";
import { DamageText } from "../effects/DamageText";
import type { Hero } from "./Hero";

export interface EnemyConfig {
  kind: EnemyKind;
  hp: number;
  atk: number;
  atkSpd: number;
  attackRange: number;
  preferredDistance: number;
  moveSpeed: number;
  color: string;
  radius: number;
  gold: number;
  itemDropChance: number;
}

const CONFIGS: Record<EnemyKind, EnemyConfig> = {
  goblin: {
    kind: "goblin",
    hp: 35,
    atk: 6,
    atkSpd: 2.0,
    attackRange: 22,
    preferredDistance: 0,
    moveSpeed: 55,
    color: COLORS.enemy,
    radius: 10,
    gold: 3,
    itemDropChance: 0.18,
  },
  goblinArcher: {
    kind: "goblinArcher",
    hp: 28,
    atk: 7,
    atkSpd: 1.6,
    attackRange: 140,
    preferredDistance: 110,
    moveSpeed: 50,
    color: COLORS.enemyArcher,
    radius: 9,
    gold: 4,
    itemDropChance: 0.25,
  },
  orc: {
    kind: "orc",
    hp: 110,
    atk: 11,
    atkSpd: 1.4,
    attackRange: 26,
    preferredDistance: 0,
    moveSpeed: 38,
    color: COLORS.enemyTank,
    radius: 14,
    gold: 10,
    itemDropChance: 0.55,
  },
  /** 도발형: 원거리 영웅 우선, 느리고 단단 */
  brute: {
    kind: "brute",
    hp: 95,
    atk: 9,
    atkSpd: 1.15,
    attackRange: 24,
    preferredDistance: 0,
    moveSpeed: 32,
    color: COLORS.enemyBrute,
    radius: 13,
    gold: 8,
    itemDropChance: 0.35,
  },
  /** 돌진: 가끔 직선 돌파 */
  charger: {
    kind: "charger",
    hp: 32,
    atk: 8,
    atkSpd: 2.2,
    attackRange: 20,
    preferredDistance: 0,
    moveSpeed: 72,
    color: COLORS.enemyCharger,
    radius: 9,
    gold: 4,
    itemDropChance: 0.2,
  },
  /** 힐러: 뒤에서 아군 회복 */
  shaman: {
    kind: "shaman",
    hp: 24,
    atk: 4,
    atkSpd: 1.0,
    attackRange: 100,
    preferredDistance: 95,
    moveSpeed: 42,
    color: COLORS.enemyShaman,
    radius: 9,
    gold: 6,
    itemDropChance: 0.4,
  },
};

export class Enemy extends Entity {
  readonly kind: EnemyKind;
  readonly cfg: EnemyConfig;
  attackCooldown = 0;
  scale: number;

  isElite = false;
  isBoss = false;
  /** 보스 페이즈용 스폰 시 최대 체력 */
  spawnMaxHp = 0;

  /** 전사 타격 시 궁/법 보너스 */
  markedUntil = 0;
  /** 마법 폭발 등 → 전사 보너스 */
  shockedUntil = 0;

  private healCooldown = 1.2;
  private chargeBurstT = 0;
  private chargeCd = 0.8 + Math.random();

  /** 보스 텔레그래프 */
  private telegraphKind: "slam" | "dash" | null = null;
  private telegraphT = 0;
  private bossSlamUsed = false;
  private bossDashUsed = false;
  /** 보스 대시 예고선 끝점 (월드 좌표) */
  private telegraphDashEnd: Vec2 | null = null;

  constructor(kind: EnemyKind, pos: Vec2, scale = 1, opts?: { boss?: boolean }) {
    const cfg = CONFIGS[kind];
    super("enemy", pos, Math.round(cfg.hp * scale));
    this.kind = kind;
    this.cfg = cfg;
    this.scale = scale;
    this.radius = cfg.radius;
    this.isBoss = !!opts?.boss;
    if (this.isBoss) {
      this.spawnMaxHp = this.maxHp;
    }
  }

  /** 웨이브 스폰 후 엘리트 강화 */
  applyElite(): void {
    if (this.isElite) return;
    this.isElite = true;
    const mul = 1.34;
    const r = this.hp / Math.max(1, this.maxHp);
    this.maxHp = Math.round(this.maxHp * mul);
    this.hp = Math.round(this.maxHp * r);
    this.radius += 2;
    this.scale *= 1.1;
  }

  override update(dt: number, state: GameState): void {
    this.baseUpdate(dt);
    if (!this.alive) return;

    if (this.isBoss) {
      if (this.spawnMaxHp <= 0) this.spawnMaxHp = this.maxHp;
      const ratio = this.hp / Math.max(1, this.spawnMaxHp);
      if (!this.telegraphKind) {
        if (!this.bossSlamUsed && ratio <= 0.66) {
          this.bossSlamUsed = true;
          this.startTelegraph("slam");
        } else if (!this.bossDashUsed && ratio <= 0.33) {
          this.bossDashUsed = true;
          this.startTelegraph("dash");
        }
      }
    }

    if (this.telegraphKind) {
      this.telegraphT -= dt;
      if (this.telegraphKind === "dash") {
        const h = this.findNearestHero(state);
        this.telegraphDashEnd = h ? { ...h.pos } : null;
      }
      if (this.telegraphT <= 0) {
        this.executeBossTelegraph(state);
        this.telegraphKind = null;
        this.telegraphDashEnd = null;
      }
      this.pos.x += this.knockback.x * dt;
      this.pos.y += this.knockback.y * dt;
      this.pos.x = Math.max(BATTLE_LEFT, Math.min(BATTLE_RIGHT, this.pos.x));
      this.pos.y = Math.max(BATTLE_TOP + 8, Math.min(BATTLE_BOTTOM - 8, this.pos.y));
      this.vel.x = 0;
      this.vel.y = 0;
      return;
    }

    const target = this.findHeroTarget(state);
    this.attackCooldown -= dt;

    if (this.kind === "shaman") {
      this.healCooldown -= dt;
      if (this.healCooldown <= 0) {
        this.tryHealAlly(state);
        this.healCooldown = 2.4;
      }
    }

    if (target) {
      const dx = target.pos.x - this.pos.x;
      const dy = target.pos.y - this.pos.y;
      const d = Math.hypot(dx, dy) || 1;
      const desired = this.cfg.preferredDistance;

      if (this.kind === "charger" && this.chargeBurstT > 0) {
        this.chargeBurstT -= dt;
        this.vel.x = (dx / d) * this.cfg.moveSpeed * 2.35;
        this.vel.y = (dy / d) * this.cfg.moveSpeed * 2.35;
        if (this.chargeBurstT <= 0) {
          this.chargeCd = 1.7 + Math.random() * 1.6;
        }
      } else if (this.kind === "charger") {
        this.chargeCd -= dt;
        if (this.chargeCd <= 0 && d > 38 && d < 210) {
          this.chargeBurstT = 0.32;
        }
        if (d > this.cfg.attackRange - 2 && this.chargeBurstT <= 0) {
          this.vel.x = (dx / d) * this.cfg.moveSpeed;
          this.vel.y = (dy / d) * this.cfg.moveSpeed;
        }
      } else if (this.cfg.kind === "goblinArcher" || this.kind === "shaman") {
        if (d < desired - 6) {
          this.vel.x = -(dx / d) * this.cfg.moveSpeed;
          this.vel.y = -(dy / d) * this.cfg.moveSpeed * 0.55;
        } else if (d > desired + 6) {
          this.vel.x = (dx / d) * this.cfg.moveSpeed * 0.65;
          this.vel.y = (dy / d) * this.cfg.moveSpeed * 0.65;
        }
      } else {
        if (d > this.cfg.attackRange - 2) {
          this.vel.x = (dx / d) * this.cfg.moveSpeed;
          this.vel.y = (dy / d) * this.cfg.moveSpeed;
        }
      }

      if (this.attackCooldown <= 0 && d <= this.cfg.attackRange + 2) {
        this.attackCooldown = 1 / this.cfg.atkSpd;
        this.attack(target, state);
      }
    }

    this.pos.x += (this.vel.x + this.knockback.x) * dt;
    this.pos.y += (this.vel.y + this.knockback.y) * dt;
    this.pos.x = Math.max(BATTLE_LEFT, Math.min(BATTLE_RIGHT, this.pos.x));
    this.pos.y = Math.max(BATTLE_TOP + 8, Math.min(BATTLE_BOTTOM - 8, this.pos.y));
    this.vel.x = 0;
    this.vel.y = 0;
  }

  private startTelegraph(kind: "slam" | "dash"): void {
    this.telegraphKind = kind;
    this.telegraphT = kind === "slam" ? 0.68 : 0.58;
    this.attackCooldown = Math.max(this.attackCooldown, this.telegraphT + 0.2);
  }

  private executeBossTelegraph(state: GameState): void {
    if (!this.telegraphKind) return;
    const base = Math.round(10 * this.scale);
    if (this.telegraphKind === "slam") {
      const r = 52;
      state.camera.shake(4, 0.18);
      state.effects.push(new DamageText(this.pos, "광역!", "incoming"));
      for (const h of state.heroes) {
        if (!h.alive) continue;
        const dx = h.pos.x - this.pos.x;
        const dy = h.pos.y - this.pos.y;
        if (dx * dx + dy * dy <= r * r) {
          h.takeDamage(base + 6);
          state.effects.push(new DamageText(h.pos, base + 6, "incoming"));
        }
      }
    } else {
      const tgt = this.findNearestHero(state);
      if (tgt) {
        const dx = tgt.pos.x - this.pos.x;
        const dy = tgt.pos.y - this.pos.y;
        const len = Math.hypot(dx, dy) || 1;
        const dash = 72;
        this.pos.x += (dx / len) * dash;
        this.pos.y += (dy / len) * dash;
        this.pos.x = Math.max(BATTLE_LEFT, Math.min(BATTLE_RIGHT, this.pos.x));
        this.pos.y = Math.max(BATTLE_TOP + 8, Math.min(BATTLE_BOTTOM - 8, this.pos.y));
        const dHit = Math.hypot(tgt.pos.x - this.pos.x, tgt.pos.y - this.pos.y);
        if (dHit < this.radius + tgt.radius + 10) {
          const dmg = base + 14;
          tgt.takeDamage(dmg, { x: dx, y: dy }, 2.2);
          state.effects.push(new DamageText(tgt.pos, dmg, "incoming"));
        }
      }
      state.camera.shake(3.5, 0.14);
    }
  }

  private findNearestHero(state: GameState): Hero | null {
    let best: Hero | null = null;
    let bd = Infinity;
    for (const h of state.heroes) {
      if (!h.alive) continue;
      const d = Math.hypot(h.pos.x - this.pos.x, h.pos.y - this.pos.y);
      if (d < bd) {
        bd = d;
        best = h;
      }
    }
    return best;
  }

  private findHeroTarget(state: GameState): Hero | null {
    if (this.kind === "brute") {
      let ranged: Hero | null = null;
      let rangedD = Infinity;
      let any: Hero | null = null;
      let anyD = Infinity;
      for (const h of state.heroes) {
        if (!h.alive) continue;
        const d = Math.hypot(h.pos.x - this.pos.x, h.pos.y - this.pos.y);
        if (d < anyD) {
          anyD = d;
          any = h;
        }
        if ((h.className === "archer" || h.className === "mage") && d < 220 && d < rangedD) {
          rangedD = d;
          ranged = h;
        }
      }
      return ranged ?? any;
    }

    let best: Hero | null = null;
    let bestD = Infinity;
    for (const h of state.heroes) {
      if (!h.alive) continue;
      const d = Math.hypot(h.pos.x - this.pos.x, h.pos.y - this.pos.y);
      if (d < bestD) {
        bestD = d;
        best = h;
      }
    }
    return best;
  }

  private tryHealAlly(state: GameState): void {
    let best: Enemy | null = null;
    let bestRatio = 1;
    for (const e of state.enemies) {
      if (!e.alive || e === this) continue;
      const r = e.hp / Math.max(1, e.maxHp);
      if (r < 0.92 && r < bestRatio) {
        bestRatio = r;
        best = e;
      }
    }
    if (best) {
      const amt = Math.round(best.maxHp * 0.14);
      best.heal(amt);
      state.effects.push(new DamageText(best.pos, "+" + amt, "heal"));
    }
  }

  private attack(target: Hero, state: GameState): void {
    const dmg = Math.round(this.cfg.atk * this.scale);
    if (this.cfg.kind === "goblinArcher" || this.kind === "shaman") {
      const a = Math.atan2(target.pos.y - this.pos.y, target.pos.x - this.pos.x);
      state.projectiles.push(
        new Projectile({
          pos: { ...this.pos },
          angle: a,
          speed: this.kind === "shaman" ? 340 : 400,
          damage: dmg,
          isCrit: false,
          faction: "enemy",
          color: this.kind === "shaman" ? "#6affb0" : "#ffb56a",
          radius: 3,
          kind: "arrow",
          ownerId: this.id,
          lifetime: 1.5,
        })
      );
    } else {
      const dir = { x: target.pos.x - this.pos.x, y: target.pos.y - this.pos.y };
      target.takeDamage(dmg, dir);
      state.effects.push(new DamageText(target.pos, dmg, "incoming"));
      state.camera.shake(1.5, 0.1);
    }
  }

  override draw(ctx: CanvasRenderingContext2D): void {
    if (!this.alive) return;
    const sq = this.squash;
    const sx = 1 + (sq - 1);
    const sy = 1 - (sq - 1) * 0.5;

    if (this.telegraphKind) {
      const p = Math.min(1, 1 - Math.max(0, this.telegraphT) / (this.telegraphKind === "slam" ? 0.68 : 0.58));
      ctx.save();
      ctx.globalAlpha = 0.35 + p * 0.45;
      ctx.strokeStyle = this.telegraphKind === "slam" ? "rgba(255,80,80,0.95)" : "rgba(255,200,80,0.95)";
      ctx.lineWidth = 2 + p * 2;
      if (this.telegraphKind === "slam") {
        ctx.beginPath();
        ctx.arc(this.pos.x, this.pos.y, 52 * (0.4 + p * 0.6), 0, Math.PI * 2);
        ctx.stroke();
      } else if (this.telegraphDashEnd) {
        ctx.beginPath();
        ctx.moveTo(this.pos.x, this.pos.y);
        ctx.lineTo(this.telegraphDashEnd.x, this.telegraphDashEnd.y);
        ctx.stroke();
      }
      ctx.restore();
    }

    ctx.save();
    ctx.translate(this.pos.x, this.pos.y);
    ctx.scale(sx, sy);

    ctx.fillStyle = "rgba(0,0,0,0.3)";
    ctx.beginPath();
    ctx.ellipse(0, this.radius * 0.85, this.radius * 0.8, this.radius * 0.3, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = this.cfg.color;
    if (this.kind === "orc" || this.kind === "brute") {
      ctx.fillRect(-this.radius, -this.radius, this.radius * 2, this.radius * 2);
      ctx.strokeStyle = "rgba(0,0,0,0.45)";
      ctx.lineWidth = 1.5;
      ctx.strokeRect(-this.radius, -this.radius, this.radius * 2, this.radius * 2);
    } else {
      ctx.beginPath();
      ctx.arc(0, 0, this.radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "rgba(0,0,0,0.45)";
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }

    ctx.fillStyle = "#fff";
    ctx.font = "bold 9px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const mark =
      this.kind === "goblin"
        ? "G"
        : this.kind === "goblinArcher"
          ? "A"
          : this.kind === "orc"
            ? "O"
            : this.kind === "brute"
              ? "B"
              : this.kind === "charger"
                ? "C"
                : this.kind === "shaman"
                  ? "S"
                  : "?";
    ctx.fillText(mark, 0, 0);

    if (this.hitFlash > 0) {
      ctx.globalCompositeOperation = "lighter";
      ctx.fillStyle = `rgba(255,255,255,${this.hitFlash * 0.7})`;
      ctx.beginPath();
      ctx.arc(0, 0, this.radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    if (this.isElite || this.isBoss) {
      ctx.save();
      ctx.strokeStyle = this.isBoss ? "rgba(255,210,120,0.9)" : "rgba(255,215,90,0.85)";
      ctx.lineWidth = this.isBoss ? 2.2 : 1.6;
      ctx.beginPath();
      ctx.arc(this.pos.x, this.pos.y, this.radius + 4 + (this.isBoss ? 2 : 0), 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }

    const bw = 22 + (this.isBoss ? 8 : 0);
    const bh = 3;
    const bx = this.pos.x - bw / 2;
    const by = this.pos.y - this.radius - 7;
    const hpRatio = this.hp / this.maxHp;
    if (hpRatio < 1 || this.isBoss) {
      ctx.fillStyle = "rgba(0,0,0,0.55)";
      ctx.fillRect(bx, by, bw, bh);
      ctx.fillStyle = this.isBoss ? "#ffb04a" : "#ff5050";
      ctx.fillRect(bx, by, bw * hpRatio, bh);
    }
  }
}
