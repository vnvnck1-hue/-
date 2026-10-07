import type { GameState } from "../core/GameState";
import type { ItemData } from "../core/Types";

const INV_COLS = 6;
const INV_MIN_ROWS = 3;
const INV_MAX_ROWS = 8;
const INV_MAX_SLOTS = INV_COLS * INV_MAX_ROWS;

function inventorySlotCount(invLen: number): number {
  const minSlots = INV_COLS * INV_MIN_ROWS;
  const need = invLen <= minSlots ? minSlots : Math.ceil(invLen / INV_COLS) * INV_COLS;
  return Math.min(INV_MAX_SLOTS, Math.max(minSlots, need));
}

/** 하단 패널: 영웅 카드 3개 + 인벤토리 그리드 + 궁극기 버튼. */
export class BottomPanel {
  private root: HTMLElement;
  private cardsEl!: HTMLElement;
  private invEl!: HTMLElement;
  private ultBtn!: HTMLButtonElement;

  /** 인벤토리에서 선택된 아이템 (장착할 영웅 선택을 위해) */
  private pendingItem: ItemData | null = null;

  constructor(parent: HTMLElement, private state: GameState) {
    this.root = document.createElement("div");
    this.root.className = "bottom-panel";
    this.root.innerHTML = `
      <div class="inventory-section">
        <div class="inventory-label">인벤토리</div>
        <div class="inventory-grid" style="--inv-cols:${INV_COLS}"></div>
      </div>
      <div class="hero-cards"></div>
      <button class="ult-btn" disabled>궁극기 충전중</button>
    `;
    parent.appendChild(this.root);
    this.cardsEl = this.root.querySelector(".hero-cards")!;
    this.invEl = this.root.querySelector(".inventory-grid")!;
    this.ultBtn = this.root.querySelector(".ult-btn")!;

    this.ultBtn.addEventListener("click", () => this.castReadyUlt());
    this.renderCards();
  }

  private renderCards(): void {
    this.cardsEl.innerHTML = "";
    for (const h of this.state.heroes) {
      const card = document.createElement("div");
      card.className = "hero-card";
      card.dataset.heroId = h.id.toString();
      card.innerHTML = `
        <div class="hero-card-name">
          <span class="name"></span>
          <span class="lvl">Lv.<span class="lv">1</span></span>
        </div>
        <div class="bar hp"><div class="fill"></div></div>
        <div class="bar mp"><div class="fill"></div></div>
        <div class="equip-slots">
          <div class="equip-slot" data-slot="weapon" title="무기"></div>
          <div class="equip-slot" data-slot="armor" title="방어구"></div>
          <div class="equip-slot" data-slot="accessory" title="악세서리"></div>
        </div>
      `;
      // 장착할 아이템이 선택된 상태에서 카드 클릭 → 해당 영웅에게 장착
      card.addEventListener("click", () => {
        if (this.pendingItem) {
          h.equip(this.pendingItem, this.state.inventory);
          this.pendingItem = null;
          this.update(this.state);
        }
      });
      this.cardsEl.appendChild(card);
    }
  }

  update(state: GameState): void {
    // 카드 갱신
    const cards = this.cardsEl.querySelectorAll<HTMLElement>(".hero-card");
    state.heroes.forEach((h, i) => {
      const card = cards[i];
      if (!card) return;
      card.classList.toggle("dead", !h.alive);
      card.querySelector(".name")!.textContent = h.displayName;
      (card.querySelector(".lv") as HTMLElement).textContent = h.level.toString();
      const hpFill = card.querySelector(".bar.hp .fill") as HTMLElement;
      const mpFill = card.querySelector(".bar.mp .fill") as HTMLElement;
      hpFill.style.width = `${Math.max(0, (h.hp / h.maxHp) * 100)}%`;
      mpFill.style.width = `${Math.max(0, (h.mana / h.maxMana) * 100)}%`;
      // 장비 슬롯
      for (const slot of ["weapon", "armor", "accessory"] as const) {
        const slotEl = card.querySelector(`.equip-slot[data-slot="${slot}"]`) as HTMLElement;
        const item = h.equipment[slot];
        slotEl.innerHTML = "";
        if (item) {
          slotEl.classList.add("has-item");
          const icon = document.createElement("div");
          icon.className = "icon";
          icon.style.background = `linear-gradient(180deg, ${rarityBg(item.rarity).a}, ${rarityBg(item.rarity).b})`;
          icon.title = `${item.name}\n${formatStats(item.stats)}`;
          icon.textContent = slotMark(slot);
          slotEl.appendChild(icon);
        } else {
          slotEl.classList.remove("has-item");
        }
      }
    });

    // 인벤토리 (고정 슬롯 그리드)
    this.invEl.innerHTML = "";
    const slots = inventorySlotCount(state.inventory.length);
    for (let i = 0; i < slots; i++) {
      const item = state.inventory[i];
      if (item) {
        const el = document.createElement("div");
        el.className = `inv-item rarity-${item.rarity}`;
        el.textContent = slotMark(item.slot);
        el.title = `${item.name}\n${formatStats(item.stats)}\n클릭: 장착할 영웅 선택`;
        el.addEventListener("click", () => {
          this.pendingItem = this.pendingItem === item ? null : item;
          this.update(state);
        });
        if (this.pendingItem === item) {
          el.classList.add("inv-item--selected");
        }
        this.invEl.appendChild(el);
      } else {
        const slot = document.createElement("div");
        slot.className = "inv-slot-empty";
        slot.title = i === 0 && state.inventory.length === 0 ? "획득한 장비가 여기에 쌓입니다" : "";
        this.invEl.appendChild(slot);
      }
    }

    // 궁극기 버튼: 가장 먼저 준비된 영웅의 궁극기 트리거
    const readyHero = state.heroes.find((h) => h.isUltReady);
    if (readyHero) {
      this.ultBtn.disabled = false;
      this.ultBtn.classList.add("ready");
      this.ultBtn.textContent = `${readyHero.displayName} 궁극기 발동!`;
      this.ultBtn.dataset.heroId = readyHero.id.toString();
    } else {
      const charging = state.heroes
        .filter((h) => h.alive)
        .sort((a, b) => b.mana / b.maxMana - a.mana / a.maxMana)[0];
      this.ultBtn.disabled = true;
      this.ultBtn.classList.remove("ready");
      if (charging) {
        const pct = Math.round((charging.mana / charging.maxMana) * 100);
        this.ultBtn.textContent = `${charging.displayName} 궁극기 충전 ${pct}%`;
      } else {
        this.ultBtn.textContent = "궁극기 충전중";
      }
    }

    this.flashCardsForPending();
  }

  private castReadyUlt(): void {
    const id = this.ultBtn.dataset.heroId;
    if (!id) return;
    const hero = this.state.heroes.find((h) => h.id === Number(id));
    hero?.castUltimate(this.state);
  }

  private flashCardsForPending(): void {
    const cards = this.cardsEl.querySelectorAll<HTMLElement>(".hero-card");
    cards.forEach((c) => {
      c.style.boxShadow = this.pendingItem ? "inset 0 0 0 2px #ffd84a" : "";
    });
  }
}

function slotMark(slot: string): string {
  return slot === "weapon" ? "검" : slot === "armor" ? "갑" : "악";
}

function rarityBg(r: string): { a: string; b: string } {
  switch (r) {
    case "rare":
      return { a: "#2a5aa0", b: "#15356a" };
    case "epic":
      return { a: "#6a2aa0", b: "#3a155a" };
    case "legendary":
      return { a: "#c9882a", b: "#6a4515" };
    default:
      return { a: "#5a5a5a", b: "#2a2a2a" };
  }
}

function formatStats(s: { atk?: number; hp?: number; atkSpd?: number; crit?: number }): string {
  const parts: string[] = [];
  if (s.atk) parts.push(`공격력 +${s.atk}`);
  if (s.hp) parts.push(`체력 +${s.hp}`);
  if (s.atkSpd) parts.push(`공속 +${(s.atkSpd * 100).toFixed(0)}%`);
  if (s.crit) parts.push(`치명 +${(s.crit * 100).toFixed(0)}%`);
  return parts.join(", ");
}
