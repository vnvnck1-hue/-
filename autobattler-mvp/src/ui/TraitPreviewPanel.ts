import type { GameState } from "../core/GameState";

function partyBuffSummaryLines(state: GameState): string[] {
  const b = state.buffs;
  const lines: string[] = [
    `공격력 ×${b.atkMul.toFixed(2)}`,
    `공격 속도 ×${b.atkSpdMul.toFixed(2)}`,
    `최대 체력 ×${b.hpMul.toFixed(2)}`,
    `마법 폭발 크기 ×${b.explosionMul.toFixed(2)}`,
    `흡혈 ${(b.lifesteal * 100).toFixed(0)}%`,
    `치명타 확률 ${(b.critChance * 100).toFixed(0)}% (장비 치명 별도 합산)`,
    `치명타 피해 ×${b.critMul.toFixed(2)}`,
  ];
  return lines;
}

/** 우상단 특성 프리뷰: 선택한 특성 목록 + 파티 보정 종합. */
export class TraitPreviewPanel {
  private btn: HTMLButtonElement;
  private overlay: HTMLElement | null = null;

  constructor(
    private parent: HTMLElement,
    private getState: () => GameState,
  ) {
    this.btn = document.createElement("button");
    this.btn.type = "button";
    this.btn.className = "trait-preview-btn";
    this.btn.textContent = "특성 프리뷰";
    this.btn.addEventListener("click", () => this.open());
    this.parent.appendChild(this.btn);
  }

  private close(): void {
    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
    }
  }

  private open(): void {
    if (this.overlay?.isConnected) return;
    this.overlay = null;

    const state = this.getState();
    const root = document.createElement("div");
    root.className = "trait-preview-overlay";
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-label", "특성 프리뷰");

    const panel = document.createElement("div");
    panel.className = "trait-preview-panel";

    const head = document.createElement("div");
    head.className = "trait-preview-head";
    const title = document.createElement("h2");
    title.textContent = "특성 프리뷰";
    const closeBtn = document.createElement("button");
    closeBtn.type = "button";
    closeBtn.className = "trait-preview-close";
    closeBtn.textContent = "닫기";
    closeBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      this.close();
    });
    head.appendChild(title);
    head.appendChild(closeBtn);

    const secList = document.createElement("section");
    secList.className = "trait-preview-section";
    const hList = document.createElement("h3");
    hList.textContent = "적용 중인 특성";
    secList.appendChild(hList);

    if (state.appliedPerks.length === 0) {
      const empty = document.createElement("p");
      empty.className = "trait-preview-empty";
      empty.textContent = "아직 선택한 특성이 없습니다.";
      secList.appendChild(empty);
    } else {
      const ol = document.createElement("ol");
      ol.className = "trait-preview-list";
      for (const p of state.appliedPerks) {
        const li = document.createElement("li");
        const name = document.createElement("div");
        name.className = "trait-preview-name";
        name.textContent = p.name;
        const desc = document.createElement("div");
        desc.className = "trait-preview-desc";
        desc.textContent = p.desc;
        li.appendChild(name);
        li.appendChild(desc);
        ol.appendChild(li);
      }
      secList.appendChild(ol);
    }

    const secSum = document.createElement("section");
    secSum.className = "trait-preview-section trait-preview-section--summary";
    const hSum = document.createElement("h3");
    hSum.textContent = "최종 종합 특성";
    secSum.appendChild(hSum);
    const sub = document.createElement("p");
    sub.className = "trait-preview-sub";
    sub.textContent = "선택한 특성이 곱해·더해진 실제 전투 수치입니다.";
    secSum.appendChild(sub);
    const ul = document.createElement("ul");
    ul.className = "trait-preview-summary";
    for (const line of partyBuffSummaryLines(state)) {
      const li = document.createElement("li");
      li.textContent = line;
      ul.appendChild(li);
    }
    secSum.appendChild(ul);

    panel.appendChild(head);
    panel.appendChild(secList);
    panel.appendChild(secSum);
    root.appendChild(panel);

    root.addEventListener("click", (e) => {
      if (e.target === root) this.close();
    });

    this.overlay = root;
    this.parent.appendChild(root);
  }

  /** DOM이 바깥에서 제거된 경우(재시작 등) 참조 정리. */
  clearOverlayRef(): void {
    if (this.overlay && !this.overlay.isConnected) {
      this.overlay = null;
    }
  }
}
