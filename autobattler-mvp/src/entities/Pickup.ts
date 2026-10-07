import type { GameState } from "../core/GameState";
import type { ItemData, Vec2 } from "../core/Types";
import { RARITY_COLOR } from "../core/Types";
import type { Hero } from "./Hero";
import { DamageText } from "../effects/DamageText";

export type PickupKind = "gold" | "item" | "healCore";

/**
 * 적 처치 후 떨어지는 픽업.
 * 처음에는 위로 튀어오르며 약간 흩뿌려진 뒤,
 * 잠시 후 자동으로 가장 가까운 영웅에게 흡수된다.
 */
export class Pickup {
  pos: Vec2;
  vel: Vec2;
  kind: PickupKind;
  amount: number;
  item?: ItemData;
  alive = true;
  /** 자동 흡수까지 남은 시간 */
  attractDelay = 0.5;
  /** 전체 수명 (안전장치) */
  lifetime = 8;
  /** 튀어오르는 동안의 z축 (높이) */
  z = 0;
  vz = 0;
  /** 흡수 시작 후 가속도 적용 */
  attracting = false;

  constructor(pos: Vec2, kind: PickupKind, amount: number, item?: ItemData) {
    this.pos = { ...pos };
    this.kind = kind;
    /** gold: 골드량, healCore: 최대 체력 대비 회복 % (정수, 예: 12 = 12%), item: 1 */
    this.amount = amount;
    this.item = item;
    const a = Math.random() * Math.PI * 2;
    const sp = 50 + Math.random() * 50;
    this.vel = { x: Math.cos(a) * sp, y: Math.sin(a) * sp * 0.5 };
    this.vz = 90 + Math.random() * 60;
  }

  update(dt: number, state: GameState): void {
    this.lifetime -= dt;
    if (this.lifetime <= 0) {
      this.alive = false;
      return;
    }
    this.attractDelay -= dt;

    if (!this.attracting) {
      this.pos.x += this.vel.x * dt;
      this.pos.y += this.vel.y * dt;
      this.vel.x *= Math.max(0, 1 - dt * 6);
      this.vel.y *= Math.max(0, 1 - dt * 6);
      this.z += this.vz * dt;
      this.vz -= 220 * dt;
      if (this.z < 0) {
        this.z = 0;
        this.vz = 0;
      }
      if (this.attractDelay <= 0 && this.z <= 1) this.attracting = true;
    } else {
      // 가장 가까운 살아있는 영웅에게 흡수
      const target = this.nearestHero(state);
      if (!target) {
        this.alive = false;
        return;
      }
      const dx = target.pos.x - this.pos.x;
      const dy = target.pos.y - this.pos.y;
      const d = Math.hypot(dx, dy) || 1;
      const speed = 220 + (1 - Math.min(1, d / 200)) * 200;
      this.pos.x += (dx / d) * speed * dt;
      this.pos.y += (dy / d) * speed * dt;
      if (d < 12) {
        this.collect(state, target);
      }
    }
  }

  private nearestHero(state: GameState): Hero | null {
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

  private collect(state: GameState, collector: Hero): void {
    collector.playPickupScaleTween();

    if (this.kind === "gold") {
      state.gold += this.amount;
    } else if (this.kind === "healCore") {
      const pct = Math.max(1, Math.min(50, this.amount)) / 100;
      const heal = Math.max(1, Math.round(collector.maxHp * pct));
      collector.heal(heal);
      state.effects.push(new DamageText(collector.pos, `+${heal}`, "heal"));
    } else if (this.kind === "item" && this.item) {
      state.inventory.push(this.item);
      // 자동 장착 활성화된 영웅에게 적용
      if (state.heroes.length) {
        // 자동 장착: 가장 적합한 영웅(같은 슬롯 빈 슬롯 → 더 낮은 희귀도 교체)
        const candidates = state.heroes.filter((h) => h.alive && h.autoEquip);
        if (candidates.length > 0) {
          const bestHero = candidates[Math.floor(Math.random() * candidates.length)]!;
          const cur = bestHero.equipment[this.item.slot];
          const rarityRank = (r: string) =>
            r === "common" ? 0 : r === "rare" ? 1 : r === "epic" ? 2 : 3;
          if (!cur || rarityRank(this.item.rarity) > rarityRank(cur.rarity)) {
            bestHero.equip(this.item, state.inventory);
          }
        }
      }
    }
    this.alive = false;
  }

  draw(ctx: CanvasRenderingContext2D): void {
    const drawY = this.pos.y - this.z;
    ctx.save();
    if (this.kind === "gold") {
      // 코인
      ctx.fillStyle = "rgba(0,0,0,0.35)";
      ctx.beginPath();
      ctx.ellipse(this.pos.x, this.pos.y + 1, 5, 1.6, 0, 0, Math.PI * 2);
      ctx.fill();
      const grd = ctx.createRadialGradient(this.pos.x - 1, drawY - 1, 0, this.pos.x, drawY, 6);
      grd.addColorStop(0, "#fff2a0");
      grd.addColorStop(0.6, "#ffb800");
      grd.addColorStop(1, "#7a4f00");
      ctx.fillStyle = grd;
      ctx.beginPath();
      ctx.arc(this.pos.x, drawY, 4.5, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "rgba(0,0,0,0.4)";
      ctx.lineWidth = 0.7;
      ctx.stroke();
    } else if (this.kind === "healCore") {
      ctx.fillStyle = "rgba(0,0,0,0.35)";
      ctx.beginPath();
      ctx.ellipse(this.pos.x, this.pos.y + 1, 6, 2, 0, 0, Math.PI * 2);
      ctx.fill();
      const pulse = 0.45 + 0.35 * Math.abs(Math.sin(performance.now() * 0.006));
      ctx.globalAlpha = pulse;
      const grd = ctx.createRadialGradient(this.pos.x - 2, drawY - 2, 0, this.pos.x, drawY, 10);
      grd.addColorStop(0, "#e8fff0");
      grd.addColorStop(0.45, "#5aff9a");
      grd.addColorStop(0.85, "#1a8a52");
      grd.addColorStop(1, "rgba(0,40,20,0.35)");
      ctx.fillStyle = grd;
      ctx.beginPath();
      ctx.arc(this.pos.x, drawY, 7, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
      ctx.strokeStyle = "rgba(200,255,220,0.85)";
      ctx.lineWidth = 1.2;
      ctx.stroke();
      ctx.fillStyle = "rgba(255,255,255,0.9)";
      ctx.font = "bold 8px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("+", this.pos.x, drawY - 0.5);
    } else if (this.item) {
      const c = RARITY_COLOR[this.item.rarity];
      // 반짝이는 광원
      ctx.globalAlpha = 0.4 + 0.4 * Math.abs(Math.sin(performance.now() * 0.005));
      const grd = ctx.createRadialGradient(this.pos.x, drawY, 0, this.pos.x, drawY, 14);
      grd.addColorStop(0, c);
      grd.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = grd;
      ctx.beginPath();
      ctx.arc(this.pos.x, drawY, 14, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;

      ctx.fillStyle = "rgba(0,0,0,0.35)";
      ctx.beginPath();
      ctx.ellipse(this.pos.x, this.pos.y + 1, 6, 2, 0, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = c;
      ctx.fillRect(this.pos.x - 5, drawY - 5, 10, 10);
      ctx.strokeStyle = "rgba(255,255,255,0.6)";
      ctx.lineWidth = 1;
      ctx.strokeRect(this.pos.x - 5, drawY - 5, 10, 10);
    }
    ctx.restore();
  }
}
