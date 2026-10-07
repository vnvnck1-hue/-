import { Effect } from "./Effect";
import type { Vec2 } from "../core/Types";

export class ExplosionEffect extends Effect {
  pos: Vec2;
  radius: number;
  color: string;
  delay: number;

  constructor(pos: Vec2, radius: number, color = "rgba(255,200,80,0.8)", delay = 0) {
    super(0.4 + delay);
    this.pos = { ...pos };
    this.radius = radius;
    this.color = color;
    this.delay = delay;
  }

  override draw(ctx: CanvasRenderingContext2D): void {
    const elapsed = this.t * this.duration;
    if (elapsed < this.delay) return;
    const local = (elapsed - this.delay) / (this.duration - this.delay);
    const t = Math.min(1, Math.max(0, local));
    const r = this.radius * (0.4 + t * 0.9);
    const a = 1 - t;
    ctx.save();
    const grd = ctx.createRadialGradient(this.pos.x, this.pos.y, 0, this.pos.x, this.pos.y, r);
    grd.addColorStop(0, "rgba(255,255,255," + (0.9 * a) + ")");
    grd.addColorStop(0.4, this.color.replace(/[\d.]+\)$/, (a * 0.7).toFixed(2) + ")"));
    grd.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = grd;
    ctx.beginPath();
    ctx.arc(this.pos.x, this.pos.y, r, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = `rgba(255,255,255,${a * 0.6})`;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(this.pos.x, this.pos.y, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }
}
