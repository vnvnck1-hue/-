import type { GameState } from "../core/GameState";

/** 상단 HUD: 골드, 스테이지/웨이브 표시. */
export class HUD {
  private root: HTMLElement;
  private goldEl!: HTMLElement;
  private stageEl!: HTMLElement;
  private waveFillEl!: HTMLElement;
  private waveTextEl!: HTMLElement;

  constructor(parent: HTMLElement) {
    this.root = document.createElement("div");
    this.root.innerHTML = `
      <div class="hud-top">
        <div class="hud-gold"><span class="gold-val">0</span></div>
        <div class="hud-stage">
          <div class="hud-stage-label">STAGE</div>
          <div class="hud-stage-value">1-1</div>
        </div>
        <div style="width: 96px; flex-shrink: 0" aria-hidden="true"></div>
      </div>
      <div class="hud-wave-bar"><div class="hud-wave-fill"></div></div>
      <div class="hud-wave-text">웨이브 준비중...</div>
    `;
    parent.appendChild(this.root);
    this.goldEl = this.root.querySelector(".gold-val")!;
    this.stageEl = this.root.querySelector(".hud-stage-value")!;
    this.waveFillEl = this.root.querySelector(".hud-wave-fill")!;
    this.waveTextEl = this.root.querySelector(".hud-wave-text")!;
  }

  update(state: GameState): void {
    this.goldEl.textContent = state.gold.toLocaleString();
    this.stageEl.textContent = `${state.stage}-${state.wave || 1}`;
    const peak = Math.max(1, state.enemiesAlivePeak);
    const alive = state.enemies.filter((e) => e.alive).length;
    const ratio = state.phase === "fighting" ? 1 - alive / peak : 0;
    this.waveFillEl.style.width = `${Math.round(ratio * 100)}%`;

    let text = "";
    switch (state.phase) {
      case "intro": text = "준비중..."; break;
      case "wavePrep": text = `웨이브 ${state.wave} 시작!`; break;
      case "fighting":
        text = `웨이브 ${state.wave} / ${state.totalWaves}  ·  남은 적 ${alive}`;
        if (state.waveModifier === "timeBonus" && state.waveTimeLeft > 0) {
          text += ` · 시간 보너스 ${Math.ceil(state.waveTimeLeft)}s`;
        } else if (state.waveModifier === "eliteShield") {
          const eliteUp = state.enemies.some((e) => e.isElite && e.alive);
          text += eliteUp ? " · 엘리트 실드!" : " · 실드 붕괴";
        }
        break;
      case "waveCleared": text = "웨이브 클리어!"; break;
      case "perkChoice": text = "특성 선택"; break;
      case "stageClear": text = `스테이지 ${state.stage} 클리어`; break;
      case "gameOver": text = "GAME OVER"; break;
    }
    this.waveTextEl.textContent = text;
  }
}
