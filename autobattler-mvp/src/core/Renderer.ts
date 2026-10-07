import { VIEW_W, VIEW_H, BATTLE_TOP, BATTLE_BOTTOM } from "./Types";

export class Renderer {
  readonly ctx: CanvasRenderingContext2D;
  readonly canvas: HTMLCanvasElement;
  dpr = 1;
  scale = 1;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("2D context not available");
    this.ctx = ctx;
    this.resize();
    window.addEventListener("resize", () => this.resize());
  }

  resize(): void {
    const rect = this.canvas.getBoundingClientRect();
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.floor(rect.width * this.dpr);
    this.canvas.height = Math.floor(rect.height * this.dpr);
    const sx = this.canvas.width / VIEW_W;
    const sy = this.canvas.height / VIEW_H;
    this.scale = Math.min(sx, sy);
  }

  begin(): void {
    const { ctx, canvas } = this;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const offsetX = (canvas.width - VIEW_W * this.scale) / 2;
    const offsetY = (canvas.height - VIEW_H * this.scale) / 2;
    ctx.setTransform(this.scale, 0, 0, this.scale, offsetX, offsetY);
  }

  end(): void {
    this.ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  drawBackground(time: number): void {
    const { ctx } = this;
    const grd = ctx.createLinearGradient(0, 0, 0, VIEW_H);
    grd.addColorStop(0, "#1a2235");
    grd.addColorStop(0.6, "#0e1320");
    grd.addColorStop(1, "#070a14");
    ctx.fillStyle = grd;
    ctx.fillRect(0, 0, VIEW_W, VIEW_H);

    // 별 같은 점들 (가벼운 분위기)
    ctx.fillStyle = "rgba(255,255,255,0.18)";
    for (let i = 0; i < 30; i++) {
      const x = (i * 53.7) % VIEW_W;
      const y = (i * 91.3) % BATTLE_TOP;
      ctx.fillRect(x, y, 1, 1);
    }

    // 전투장 바닥 (다층 표현용 가로 라인)
    const groundLines = 3;
    for (let i = 0; i <= groundLines; i++) {
      const y = BATTLE_TOP + ((BATTLE_BOTTOM - BATTLE_TOP) / groundLines) * i;
      ctx.strokeStyle = "rgba(255,255,255,0.04)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(VIEW_W, y);
      ctx.stroke();
    }

    // 전투 영역 약한 테두리 글로우
    const pulse = 0.5 + 0.5 * Math.sin(time * 0.002);
    ctx.strokeStyle = `rgba(120,160,255,${0.06 + 0.04 * pulse})`;
    ctx.lineWidth = 1;
    ctx.strokeRect(2, BATTLE_TOP - 2, VIEW_W - 4, BATTLE_BOTTOM - BATTLE_TOP + 4);
  }
}
