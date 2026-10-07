import type { PerkData } from "../core/Types";
import { perkIconSvg } from "./perkIcons";

/** 특성 선택 오버레이. show()를 호출하면 Promise<선택된 특성> 반환. */
export class PerkOverlay {
  private activeRoot: HTMLElement | null = null;
  private activeResolve: ((p: PerkData | null) => void) | null = null;
  private activePerks: PerkData[] = [];

  constructor(private parent: HTMLElement) {}

  /** 오버레이만 제거. 대기 중 Promise는 null로 끝남 (재시작 시 적용 안 함). */
  cancel(): void {
    if (this.activeRoot) {
      this.activeRoot.remove();
      this.activeRoot = null;
    }
    if (this.activeResolve) {
      const r = this.activeResolve;
      this.activeResolve = null;
      this.activePerks = [];
      r(null);
    }
  }

  show(perks: PerkData[]): Promise<PerkData | null> {
    this.cancel();
    this.activePerks = perks.slice();
    return new Promise((resolve) => {
      this.activeResolve = resolve;
      const root = document.createElement("div");
      root.className = "perk-overlay";
      root.innerHTML = `
        <h2>특성 선택</h2>
        <div class="sub">3개 중 1개를 선택하면 파티 전체에 적용됩니다</div>
        <div class="perk-cards"></div>
      `;
      this.activeRoot = root;
      const cards = root.querySelector(".perk-cards")!;
      perks.forEach((p) => {
        const c = document.createElement("div");
        c.className = "perk-card";
        c.innerHTML = `
          <div class="perk-icon">${perkIconSvg(p.id)}</div>
          <div class="perk-text">
            <div class="perk-name">${p.name}</div>
            <div class="perk-desc">${p.desc}</div>
          </div>
        `;
        c.addEventListener("click", () => {
          root.remove();
          this.activeRoot = null;
          this.activeResolve = null;
          this.activePerks = [];
          resolve(p);
        });
        cards.appendChild(c);
      });
      this.parent.appendChild(root);
    });
  }
}
