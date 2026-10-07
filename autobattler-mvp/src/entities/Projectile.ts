import type { GameState } from "../core/GameState";
import type { Faction, HeroClass, Vec2 } from "../core/Types";
import { BATTLE_LEFT, BATTLE_RIGHT, BATTLE_TOP, BATTLE_BOTTOM } from "../core/Types";
import { ExplosionEffect } from "../effects/ExplosionEffect";
import { DamageText } from "../effects/DamageText";
import type { Hero } from "./Hero";
import type { Enemy } from "./Enemy";
import { applyRoundedDamage } from "../combat/damageModifiers";

export interface ProjectileConfig {
  pos: Vec2;
  angle: number;
  speed: number;
  damage: number;
  isCrit: boolean;
  faction: Faction;
  color: string;
  radius: number;
  kind: "arrow" | "magic";
  /** 폭발 반경 - 0이면 단일 타격 */
  explodeRadius?: number;
  ownerId: number;
  lifetime: number;
}

function ownerHeroClass(state: GameState, ownerId: number): HeroClass | null {
  const h = state.heroes.find((x) => x.id === ownerId);
  return h?.className ?? null;
}

export class Projectile {
  pos: Vec2;
  vel: Vec2;
  damage: number;
  isCrit: boolean;
  faction: Faction;
  color: string;
  radius: number;
  kind: "arrow" | "magic";
  explodeRadius: number;
  ownerId: number;
  lifetime: number;
  alive = true;
  trail: Vec2[] = [];

  constructor(cfg: ProjectileConfig) {
    this.pos = { ...cfg.pos };
    this.vel = {
      x: Math.cos(cfg.angle) * cfg.speed,
      y: Math.sin(cfg.angle) * cfg.speed,
    };
    this.damage = cfg.damage;
    this.isCrit = cfg.isCrit;
    this.faction = cfg.faction;
    this.color = cfg.color;
    this.radius = cfg.radius;
    this.kind = cfg.kind;
    this.explodeRadius = cfg.explodeRadius ?? 0;
    this.ownerId = cfg.ownerId;
    this.lifetime = cfg.lifetime;
  }

  get angle(): number {
    return Math.atan2(this.vel.y, this.vel.x);
  }

  update(dt: number, state: GameState): void {
    this.lifetime -= dt;
    if (this.lifetime <= 0) {
      this.detonate(state);
      return;
    }
    this.pos.x += this.vel.x * dt;
    this.pos.y += this.vel.y * dt;

    // 잔상
    this.trail.push({ x: this.pos.x, y: this.pos.y });
    if (this.trail.length > 6) this.trail.shift();

    if (
      this.pos.x < BATTLE_LEFT - 10 ||
      this.pos.x > BATTLE_RIGHT + 10 ||
      this.pos.y < BATTLE_TOP - 10 ||
      this.pos.y > BATTLE_BOTTOM + 10
    ) {
      this.alive = false;
      return;
    }

    // 충돌 검사
    if (this.faction === "ally") {
      for (const e of state.enemies) {
        if (!e.alive) continue;
        if (this.collides(e)) {
          this.hitTarget(e, state);
          return;
        }
      }
    } else {
      for (const h of state.heroes) {
        if (!h.alive) continue;
        if (this.collides(h)) {
          this.hitTarget(h, state);
          return;
        }
      }
    }
  }

  private collides(target: Hero | Enemy): boolean {
    const dx = target.pos.x - this.pos.x;
    const dy = target.pos.y - this.pos.y;
    const r = target.radius + this.radius;
    return dx * dx + dy * dy <= r * r;
  }

  private hitTarget(target: Hero | Enemy, state: GameState): void {
    if (this.explodeRadius > 0) {
      this.detonate(state);
    } else {
      const dir = { x: this.vel.x, y: this.vel.y };
      const kbMul = this.faction === "ally" && this.isCrit ? 10 : 1;
      if (this.faction === "ally") {
        const oc = ownerHeroClass(state, this.ownerId);
        const dmg = applyRoundedDamage(target as Enemy, this.damage, state, oc, dir, kbMul);
        state.effects.push(new DamageText(target.pos, dmg, this.isCrit ? "crit" : "normal"));
        if (state.buffs.lifesteal > 0) {
          const owner = state.heroes.find((h) => h.id === this.ownerId);
          if (owner) owner.heal(Math.round(dmg * state.buffs.lifesteal));
        }
      } else {
        target.takeDamage(this.damage, dir, kbMul);
        state.effects.push(
          new DamageText(target.pos, this.damage, this.isCrit ? "crit" : "incoming"),
        );
      }
      this.alive = false;
    }
  }

  private detonate(state: GameState): void {
    if (this.explodeRadius > 0) {
      state.effects.push(new ExplosionEffect(this.pos, this.explodeRadius, "rgba(120,180,255,0.85)"));
      state.camera.shake(2, 0.15);
      const targets = this.faction === "ally" ? state.enemies : state.heroes;
      const oc = ownerHeroClass(state, this.ownerId);
      const owner = state.heroes.find((h) => h.id === this.ownerId);
      let lsHeal = 0;
      for (const t of targets) {
        if (!t.alive) continue;
        const dx = t.pos.x - this.pos.x;
        const dy = t.pos.y - this.pos.y;
        if (dx * dx + dy * dy <= this.explodeRadius * this.explodeRadius) {
          const dir = { x: dx, y: dy };
          const kbMul = this.faction === "ally" && this.isCrit ? 10 : 1;
          if (this.faction === "ally") {
            const dmg = applyRoundedDamage(t as Enemy, this.damage, state, oc, dir, kbMul);
            state.effects.push(new DamageText(t.pos, dmg, this.isCrit ? "crit" : "normal"));
            if (this.kind === "magic" && oc === "mage") {
              (t as Enemy).shockedUntil = state.time + 2.45;
            }
            if (state.buffs.lifesteal > 0 && owner) lsHeal += Math.round(dmg * state.buffs.lifesteal);
          } else {
            t.takeDamage(this.damage, dir, kbMul);
            state.effects.push(new DamageText(t.pos, this.damage, this.isCrit ? "crit" : "normal"));
          }
        }
      }
      if (lsHeal > 0 && owner) owner.heal(lsHeal);
    }
    this.alive = false;
  }

  draw(ctx: CanvasRenderingContext2D): void {
    // 잔상
    ctx.save();
    for (let i = 0; i < this.trail.length; i++) {
      const p = this.trail[i]!;
      const a = (i / this.trail.length) * 0.5;
      ctx.fillStyle = this.color;
      ctx.globalAlpha = a;
      ctx.beginPath();
      ctx.arc(p.x, p.y, this.radius * (i / this.trail.length), 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    ctx.save();
    ctx.translate(this.pos.x, this.pos.y);
    ctx.rotate(this.angle);
    if (this.kind === "arrow") {
      ctx.fillStyle = this.color;
      ctx.beginPath();
      ctx.moveTo(8, 0);
      ctx.lineTo(-4, -2);
      ctx.lineTo(-4, 2);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = "rgba(0,0,0,0.4)";
      ctx.lineWidth = 0.6;
      ctx.stroke();
    } else {
      // magic orb
      const grd = ctx.createRadialGradient(0, 0, 0, 0, 0, this.radius * 2.5);
      grd.addColorStop(0, "#fff");
      grd.addColorStop(0.4, this.color);
      grd.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = grd;
      ctx.beginPath();
      ctx.arc(0, 0, this.radius * 2.5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }
}
