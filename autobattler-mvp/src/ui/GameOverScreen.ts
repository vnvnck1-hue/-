import type { GameState } from "../core/GameState";

export class GameOverScreen {
  constructor(private parent: HTMLElement) {}

  show(state: GameState, onRestart: () => void): void {
    const root = document.createElement("div");
    root.className = "game-over";
    root.innerHTML = `
      <h1>GAME OVER</h1>
      <div class="stats">
        도달 스테이지: <b>${state.stage}-${state.wave || 1}</b><br/>
        획득 골드: <b>${state.gold.toLocaleString()}</b><br/>
        선택한 특성: <b>${state.perksTaken}개</b>
      </div>
      <button>다시 시작</button>
    `;
    root.querySelector("button")!.addEventListener("click", () => {
      root.remove();
      onRestart();
    });
    this.parent.appendChild(root);
  }
}
