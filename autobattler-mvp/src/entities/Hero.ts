import { Entity } from "./Entity";
import type { GameState } from "../core/GameState";
import type { HeroClass, ItemData, EquipSlot, ItemStats, Vec2 } from "../core/Types";
import {
  COLORS,
  BATTLE_TOP,
  BATTLE_BOTTOM,
  BATTLE_LEFT,
  BATTLE_RIGHT,
} from "../core/Types";
import { DamageText } from "../effects/DamageText";
import { Projectile } from "./Projectile";
import { SlashEffect } from "../effects/SlashEffect";
import { ExplosionEffect } from "../effects/ExplosionEffect";
import type { Enemy } from "./Enemy";
import { applyRoundedDamage } from "../combat/damageModifiers";

export interface HeroConfig {
  className: HeroClass;
  displayName: string;
  baseHp: number;
  baseAtk: number;
  /** 초당 공격 횟수 */
  baseAtkSpd: number;
  /** 적 탐지/공격 사거리 */
  attackRange: number;
  /** 유지하려는 거리(원거리 캐릭터). 근접은 0 */
  preferredDistance: number;
  moveSpeed: number;
  color: string;
  /** 마나 최대치 */
  maxMana: number;
  /** 공격 1회당 마나 획득 */
  manaPerAttack: number;
}

export class Hero extends Entity {
  readonly className: HeroClass;
  readonly displayName: string;
  readonly cfg: HeroConfig;

  level = 1;
  baseAtk: number;
  baseAtkSpd: number;
  baseMaxHp: number;

  attackCooldown = 0;
  /** 다음 공격까지의 충전 시각 효과(0~1) */
  attackCharge = 0;

  mana = 0;
  maxMana: number;

  /** 장비 슬롯 */
  equipment: { weapon?: ItemData; armor?: ItemData; accessory?: ItemData } = {};

  /** 자동 장착 모드 */
  autoEquip = true;

  /** 픽업 흡수 시 스케일 트윈 남은 시간(초). */
  private pickupTweenT = 0;
  private static readonly PICKUP_TWEEN_DUR = 0.22;

  /** 궁극기 사용 가능 여부(마나 풀) */
  get isUltReady(): boolean {
    return this.alive && this.mana >= this.maxMana;
  }

  constructor(cfg: HeroConfig, pos: Vec2) {
    super("ally", pos, cfg.baseHp);
    this.cfg = cfg;
    this.className = cfg.className;
    this.displayName = cfg.displayName;
    this.baseAtk = cfg.baseAtk;
    this.baseAtkSpd = cfg.baseAtkSpd;
    this.baseMaxHp = cfg.baseHp;
    this.maxMana = cfg.maxMana;
    this.radius = 11;
  }

  /** 장비/특성/레벨 보너스가 합쳐진 최종 스탯. */
  get stats(): { atk: number; atkSpd: number; maxHp: number; crit: number } {
    const eq = this.sumEquip();
    return {
      atk: this.baseAtk + eq.atk,
      atkSpd: (this.baseAtkSpd + eq.atkSpd) || this.baseAtkSpd,
      maxHp: this.baseMaxHp + eq.hp,
      crit: eq.crit,
    };
  }

  private sumEquip(): Required<ItemStats> {
    const acc = { atk: 0, hp: 0, atkSpd: 0, crit: 0 };
    for (const slot of ["weapon", "armor", "accessory"] as EquipSlot[]) {
      const it = this.equipment[slot];
      if (!it) continue;
      if (it.stats.atk) acc.atk += it.stats.atk;
      if (it.stats.hp) acc.hp += it.stats.hp;
      if (it.stats.atkSpd) acc.atkSpd += it.stats.atkSpd;
      if (it.stats.crit) acc.crit += it.stats.crit;
    }
    return acc;
  }

  /** 골드·아이템·힐 코어 등 픽업을 먹었을 때 짧은 스케일 피드백. */
  playPickupScaleTween(): void {
    this.pickupTweenT = Hero.PICKUP_TWEEN_DUR;
  }

  /** 장비 교체 (같은 슬롯의 기존 장비는 인벤토리로 반환). */
  equip(item: ItemData, inventory: ItemData[]): void {
    const prev = this.equipment[item.slot];
    if (prev) inventory.push(prev);
    const idx = inventory.indexOf(item);
    if (idx >= 0) inventory.splice(idx, 1);
    this.equipment[item.slot] = item;
    // 장비 변경 시 max hp 변화에 비례하여 현재 hp 비율 유지
    const { maxHp } = this.stats;
    const ratio = this.maxHp > 0 ? this.hp / this.maxHp : 1;
    this.maxHp = maxHp;
    this.hp = Math.max(1, Math.min(maxHp, maxHp * ratio));
  }

  override update(dt: number, state: GameState): void {
    this.baseUpdate(dt);
    if (!this.alive) return;

    if (this.pickupTweenT > 0) {
      this.pickupTweenT = Math.max(0, this.pickupTweenT - dt);
    }

    // 버프 적용된 최대 체력
    const targetMax = Math.round(this.stats.maxHp * state.buffs.hpMul);
    if (targetMax !== this.maxHp) {
      const ratio = this.maxHp > 0 ? this.hp / this.maxHp : 1;
      this.maxHp = targetMax;
      this.hp = Math.min(this.maxHp, this.hp || ratio * this.maxHp);
    }

    const target = this.findTarget(state);
    this.attackCooldown -= dt;

    // 이동 결정
    if (target) {
      this.moveToward(target, dt);
    }
    this.applyAnchoring(state);

    // 공격
    if (target && this.canAttackNow(target)) {
      this.performAttack(target, state);
      const atkSpd = this.stats.atkSpd * state.buffs.atkSpdMul;
      this.attackCooldown = 1 / Math.max(0.1, atkSpd);
      this.attackCharge = 1;
    } else if (this.attackCharge > 0) {
      this.attackCharge = Math.max(0, this.attackCharge - dt * 4);
    }

    // 위치 보정 (전투 영역 내)
    this.pos.x += (this.vel.x + this.knockback.x) * dt;
    this.pos.y += (this.vel.y + this.knockback.y) * dt;
    this.pos.x = Math.max(BATTLE_LEFT, Math.min(BATTLE_RIGHT, this.pos.x));
    this.pos.y = Math.max(BATTLE_TOP + 8, Math.min(BATTLE_BOTTOM - 8, this.pos.y));
    this.vel.x = 0;
    this.vel.y = 0;
  }

  /** 스폰 시 진영 위치 — 전투 중 살짝 끌어당겨 구석 고착을 줄임. */
  private homeX = 0;
  private homeY = 0;

  setHome(x: number, y: number): void {
    this.homeX = x;
    this.homeY = y;
  }

  /**
   * 포메이션 홈으로 약한 닻 + 맵 가장자리 밀어내기 + 아군 간격.
   * 키트/추격만으로는 벽에 붙은 채로 멈추는 경우가 많아 전투 내내 유지됨.
   */
  private applyAnchoring(state: GameState): void {
    const cap = this.cfg.moveSpeed;
    let ax = 0;
    let ay = 0;

    const hx = this.homeX - this.pos.x;
    const hy = this.homeY - this.pos.y;
    const hd = Math.hypot(hx, hy);
    if (hd > 8) {
      const pull = Math.min(cap * 0.32, hd * 0.9);
      ax += (hx / hd) * pull;
      ay += (hy / hd) * pull;
    }

    const margin = 40;
    const push = cap * 0.42;
    const leftM = BATTLE_LEFT + margin;
    if (this.pos.x < leftM) {
      const t = Math.max(0, (leftM - this.pos.x) / margin);
      ax += push * t * t;
    }
    const rightM = BATTLE_RIGHT - margin;
    if (this.pos.x > rightM) {
      const t = Math.max(0, (this.pos.x - rightM) / margin);
      ax -= push * t * t;
    }
    const topM = BATTLE_TOP + 8 + margin;
    if (this.pos.y < topM) {
      const t = Math.max(0, (topM - this.pos.y) / margin);
      ay += push * t * t;
    }
    const botM = BATTLE_BOTTOM - 8 - margin;
    if (this.pos.y > botM) {
      const t = Math.max(0, (this.pos.y - botM) / margin);
      ay -= push * t * t;
    }

    const sepR = 30;
    for (const h of state.heroes) {
      if (h === this || !h.alive) continue;
      const sx = this.pos.x - h.pos.x;
      const sy = this.pos.y - h.pos.y;
      const sd = Math.hypot(sx, sy) || 1;
      if (sd < sepR) {
        const w = 1 - sd / sepR;
        const f = cap * 0.26 * w * w;
        ax += (sx / sd) * f;
        ay += (sy / sd) * f;
      }
    }

    this.vel.x += ax;
    this.vel.y += ay;

    const sp = Math.hypot(this.vel.x, this.vel.y);
    const maxSp = cap * 1.2;
    if (sp > maxSp) {
      const s = maxSp / sp;
      this.vel.x *= s;
      this.vel.y *= s;
    }
  }

  protected findTarget(state: GameState): Enemy | null {
    let best: Enemy | null = null;
    let bestScore = Infinity;
    for (const e of state.enemies) {
      if (!e.alive) continue;
      const dx = e.pos.x - this.pos.x;
      const dy = e.pos.y - this.pos.y;
      const d = Math.hypot(dx, dy);
      // 마법사는 적 밀집 우선 (가중치)
      let score = d;
      if (this.className === "mage") {
        const cluster = this.countNearby(e, state.enemies, 36);
        score = d - cluster * 10;
      }
      if (score < bestScore) {
        bestScore = score;
        best = e;
      }
    }
    return best;
  }

  private countNearby(target: Enemy, list: Enemy[], radius: number): number {
    let n = 0;
    for (const e of list) {
      if (!e.alive || e === target) continue;
      const dx = e.pos.x - target.pos.x;
      const dy = e.pos.y - target.pos.y;
      if (dx * dx + dy * dy < radius * radius) n++;
    }
    return n;
  }

  protected moveToward(target: Enemy, _dt: number): void {
    const dx = target.pos.x - this.pos.x;
    const dy = target.pos.y - this.pos.y;
    const dist = Math.hypot(dx, dy) || 1;
    const desired = this.cfg.preferredDistance;
    const speed = this.cfg.moveSpeed;

    if (this.className === "warrior") {
      if (dist > this.cfg.attackRange - 2) {
        this.vel.x = (dx / dist) * speed;
        this.vel.y = (dy / dist) * speed;
      }
    } else if (this.className === "archer") {
      // 거리 유지: 너무 가까우면 후퇴, 너무 멀면 접근
      if (dist < desired - 8) {
        this.vel.x = -(dx / dist) * speed;
        this.vel.y = -(dy / dist) * speed * 0.6;
      } else if (dist > desired + 8) {
        this.vel.x = (dx / dist) * speed * 0.6;
        this.vel.y = (dy / dist) * speed * 0.6;
      } else {
        // 미세 좌우 위빙
        this.vel.y = Math.sin(performance.now() * 0.003 + this.id) * 12;
      }
    } else if (this.className === "mage") {
      // 후방 유지 (큰 desired distance)
      if (dist < desired - 10) {
        this.vel.x = -(dx / dist) * speed;
      } else if (dist > desired + 30) {
        this.vel.x = (dx / dist) * speed * 0.4;
      }
      // y 위치는 가능한 가장 아래(아군 진영)
      const targetY = BATTLE_BOTTOM - 30;
      const dyHome = targetY - this.pos.y;
      this.vel.y = Math.sign(dyHome) * Math.min(speed * 0.5, Math.abs(dyHome) * 4);
    }
  }

  protected canAttackNow(target: Enemy): boolean {
    if (this.attackCooldown > 0) return false;
    const d = Math.hypot(target.pos.x - this.pos.x, target.pos.y - this.pos.y);
    return d <= this.cfg.attackRange + 4;
  }

  /** 클래스별 공격 구현 */
  protected performAttack(target: Enemy, state: GameState): void {
    const s = this.stats;
    const dmgBase = s.atk * state.buffs.atkMul;
    const isCrit = Math.random() < (state.buffs.critChance + s.crit);
    const dmg = Math.round(dmgBase * (isCrit ? state.buffs.critMul : 1));

    if (this.className === "warrior") {
      // 근접 반달 베기: 전방 호 안의 모든 적
      const dir = this.angleTo(target);
      state.effects.push(new SlashEffect(this.pos, dir, this.cfg.attackRange + 6, this.cfg.color));
      const arc = Math.PI * 0.55;
      const range = this.cfg.attackRange + 6;
      for (const e of state.enemies) {
        if (!e.alive) continue;
        const dx = e.pos.x - this.pos.x;
        const dy = e.pos.y - this.pos.y;
        const d = Math.hypot(dx, dy);
        if (d > range) continue;
        const a = Math.atan2(dy, dx);
        const da = Math.atan2(Math.sin(a - dir), Math.cos(a - dir));
        if (Math.abs(da) <= arc / 2) {
          this.dealDamage(e, dmg, isCrit, state);
        }
      }
    } else if (this.className === "archer") {
      // 직선 화살
      const a = this.angleTo(target);
      const proj = new Projectile({
        pos: { ...this.pos },
        angle: a,
        speed: 560,
        damage: dmg,
        isCrit,
        faction: "ally",
        color: this.cfg.color,
        radius: 3,
        kind: "arrow",
        ownerId: this.id,
        lifetime: 1.4,
      });
      state.projectiles.push(proj);
    } else {
      // mage: 폭발형 마탄
      const a = this.angleTo(target);
      const proj = new Projectile({
        pos: { ...this.pos },
        angle: a,
        speed: 400,
        damage: dmg,
        isCrit,
        faction: "ally",
        color: this.cfg.color,
        radius: 5,
        kind: "magic",
        explodeRadius: 28 * state.buffs.explosionMul,
        ownerId: this.id,
        lifetime: 1.6,
      });
      state.projectiles.push(proj);
    }

    // 마나 충전
    this.mana = Math.min(this.maxMana, this.mana + this.cfg.manaPerAttack);
  }

  protected dealDamage(target: Enemy, dmg: number, isCrit: boolean, state: GameState): void {
    const dir = { x: target.pos.x - this.pos.x, y: target.pos.y - this.pos.y };
    const kbMul = isCrit ? 10 : 1;
    const shown = applyRoundedDamage(target, dmg, state, this.className, dir, kbMul);
    state.effects.push(new DamageText(target.pos, shown, isCrit ? "crit" : "normal"));
    if (this.className === "warrior") {
      target.markedUntil = state.time + 2.45;
    }
    if (state.buffs.lifesteal > 0) {
      this.heal(Math.round(shown * state.buffs.lifesteal));
    }
    if (!target.alive) {
      // 마나 보너스 (처치)
      this.mana = Math.min(this.maxMana, this.mana + 4);
    }
  }

  protected angleTo(t: { pos: Vec2 }): number {
    return Math.atan2(t.pos.y - this.pos.y, t.pos.x - this.pos.x);
  }

  /** 궁극기 발동. 마나가 가득 찼을 때만 동작. */
  castUltimate(state: GameState): boolean {
    if (!this.isUltReady) return false;
    this.mana = 0;
    state.camera.shake(6, 0.35);
    state.camera.flash("rgba(255,210,120,1)", 0.3);
    state.camera.punchZoom(1.06, 0.25);

    if (this.className === "warrior") {
      // 광역 도발 공격: 자신 주변 큰 원형 데미지 + 적 끌어당김 효과
      const r = 80;
      const dmg = this.stats.atk * state.buffs.atkMul * 2.2;
      state.effects.push(new ExplosionEffect(this.pos, r, "rgba(255,120,80,0.8)"));
      for (const e of state.enemies) {
        if (!e.alive) continue;
        const dx = e.pos.x - this.pos.x;
        const dy = e.pos.y - this.pos.y;
        const d = Math.hypot(dx, dy);
        if (d <= r) {
          this.dealDamage(e, Math.round(dmg), false, state);
          // 끌어당김(역방향 넉백)
          const len = d || 1;
          e.knockback.x -= (dx / len) * 90;
          e.knockback.y -= (dy / len) * 90;
        }
      }
    } else if (this.className === "archer") {
      // 화살 폭풍: 16발 부채꼴
      const count = 18;
      const dmg = this.stats.atk * state.buffs.atkMul * 0.7;
      for (let i = 0; i < count; i++) {
        const a = (i / count) * Math.PI * 2;
        state.projectiles.push(
          new Projectile({
            pos: { ...this.pos },
            angle: a,
            speed: 480,
            damage: Math.round(dmg),
            isCrit: false,
            faction: "ally",
            color: this.cfg.color,
            radius: 3,
            kind: "arrow",
            ownerId: this.id,
            lifetime: 1.4,
          })
        );
      }
    } else {
      // 메테오: 무작위 위치 5발
      const count = 6;
      const dmg = this.stats.atk * state.buffs.atkMul * 1.6;
      for (let i = 0; i < count; i++) {
        const x = BATTLE_LEFT + Math.random() * (BATTLE_RIGHT - BATTLE_LEFT);
        const y = BATTLE_TOP + Math.random() * (BATTLE_BOTTOM - BATTLE_TOP) * 0.7;
        const delay = i * 0.12;
        state.effects.push(new ExplosionEffect({ x, y }, 36 * state.buffs.explosionMul, "rgba(120,170,255,0.9)", delay));
        // 데미지 적용도 지연
        setTimeout(() => {
          const radius = 36 * state.buffs.explosionMul;
          for (const e of state.enemies) {
            if (!e.alive) continue;
            const dx = e.pos.x - x;
            const dy = e.pos.y - y;
            if (dx * dx + dy * dy <= radius * radius) {
              this.dealDamage(e, Math.round(dmg), false, state);
            }
          }
          state.camera.shake(3, 0.2);
        }, delay * 1000);
      }
    }
    return true;
  }

  override draw(ctx: CanvasRenderingContext2D): void {
    if (!this.alive) {
      // 사망 표시
      ctx.save();
      ctx.globalAlpha = 0.4;
      ctx.fillStyle = "#444";
      ctx.beginPath();
      ctx.arc(this.pos.x, this.pos.y, this.radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
      return;
    }
    const sq = this.squash;
    const sx = 1 + (sq - 1);
    const sy = 1 - (sq - 1) * 0.5;
    const u = Hero.PICKUP_TWEEN_DUR > 0 ? this.pickupTweenT / Hero.PICKUP_TWEEN_DUR : 0;
    const pickupBoost = 1 + 0.13 * Math.sin((1 - u) * Math.PI);

    ctx.save();
    ctx.translate(this.pos.x, this.pos.y);
    ctx.scale(sx * pickupBoost, sy * pickupBoost);

    // 그림자
    ctx.fillStyle = "rgba(0,0,0,0.35)";
    ctx.beginPath();
    ctx.ellipse(0, this.radius * 0.9, this.radius * 0.9, this.radius * 0.35, 0, 0, Math.PI * 2);
    ctx.fill();

    // 본체 (둥근 캐릭터 + 클래스 컬러)
    ctx.fillStyle = this.cfg.color;
    ctx.beginPath();
    ctx.arc(0, 0, this.radius, 0, Math.PI * 2);
    ctx.fill();

    // 외곽선
    ctx.strokeStyle = "rgba(0,0,0,0.45)";
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // 클래스 표식
    ctx.fillStyle = "#fff";
    ctx.font = "bold 11px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const mark = this.className === "warrior" ? "전" : this.className === "archer" ? "궁" : "마";
    ctx.fillText(mark, 0, 0);

    // 충전 링
    if (this.attackCharge > 0) {
      ctx.strokeStyle = `rgba(255,255,255,${this.attackCharge * 0.6})`;
      ctx.lineWidth = 1.8;
      ctx.beginPath();
      ctx.arc(0, 0, this.radius + 3, 0, Math.PI * 2 * this.attackCharge);
      ctx.stroke();
    }

    // 피격 플래시
    if (this.hitFlash > 0) {
      ctx.globalCompositeOperation = "lighter";
      ctx.fillStyle = `rgba(255,255,255,${this.hitFlash * 0.7})`;
      ctx.beginPath();
      ctx.arc(0, 0, this.radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    // HP/MP 바
    const bw = 26;
    const bh = 3;
    const bx = this.pos.x - bw / 2;
    const by = this.pos.y - this.radius - 10;
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.fillRect(bx, by, bw, bh);
    ctx.fillStyle = "#3aff70";
    ctx.fillRect(bx, by, bw * (this.hp / Math.max(1, this.maxHp)), bh);

    if (this.maxMana > 0) {
      ctx.fillStyle = "rgba(0,0,0,0.55)";
      ctx.fillRect(bx, by + bh + 1, bw, 2);
      ctx.fillStyle = this.isUltReady ? "#ffe060" : "#5aa6ff";
      ctx.fillRect(bx, by + bh + 1, bw * (this.mana / this.maxMana), 2);
    }
  }
}
