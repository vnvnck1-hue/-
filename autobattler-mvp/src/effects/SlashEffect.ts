import { Effect } from "./Effect";
import type { Vec2 } from "../core/Types";

/** 전사의 반달 베기 잔상. */
export class SlashEffect extends Effect {
  pos: Vec2;
  angle: number;
  radius: number;
  color: string;

  constructor(pos: Vec2, angle: number, radius: number, color: string) {
    super(0.22);
    this.pos = { ...pos };
    this.angle = angle;
    this.radius = radius;
    this.color = color;
  }

  override draw(ctx: CanvasRenderingContext2D): void {
    const t = this.t;
    const a = (1 - t) * 0.85;
    const sweep = Math.PI * 0.7;
    ctx.save();
    ctx.translate(this.pos.x, this.pos.y);
    ctx.rotate(this.angle - sweep / 2 + sweep * t);
    ctx.globalAlpha = a;
    ctx.strokeStyle = this.color;
    ctx.lineWidth = 6 * (1 - t * 0.4);
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.arc(0, 0, this.radius * (0.6 + t * 0.4), -0.18, 0.18);
    ctx.stroke();

    // 흰 코어
    ctx.strokeStyle = `rgba(255,255,255,${a})`;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, 0, this.radius * (0.6 + t * 0.4), -0.18, 0.18);
    ctx.stroke();
    ctx.restore();
  }
}
