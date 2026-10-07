export class StartScreen {
  constructor(private parent: HTMLElement) {}

  show(onStart: () => void): void {
    const root = document.createElement("div");
    root.className = "start-screen";
    root.innerHTML = `
      <h1>3인 파티<br/>로그라이크 오토배틀러</h1>
      <div class="tagline">전사·궁수·마법사가 자동 전투합니다</div>
      <button class="start-btn">전투 시작</button>
      <div class="hint">
        · 적 처치로 골드와 장비를 획득합니다<br/>
        · 장비는 자동 장착되며, 인벤토리에서 직접 옮길 수도 있습니다<br/>
        · 3 웨이브마다 특성을 선택해 빌드를 강화하세요<br/>
        · 마나가 가득 차면 하단의 궁극기 버튼이 활성화됩니다
      </div>
    `;
    const btn = root.querySelector(".start-btn")!;
    btn.addEventListener("click", () => {
      root.remove();
      onStart();
    });
    this.parent.appendChild(root);
  }
}
