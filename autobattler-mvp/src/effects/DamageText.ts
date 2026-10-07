import { Effect } from "./Effect";
import type { Vec2 } from "../core/Types";

export type DamageKind = "normal" | "crit" | "incoming" | "heal";

export class DamageText extends Effect {
  pos: Vec2;
  text: string;
  kind: DamageKind;
  vx: number;

  constructor(pos: Vec2, value: number | string, kind: DamageKind) {
    super(0.7);
    this.pos = { x: pos.x, y: pos.y - 14 };
    this.text = typeof value === "number" ? Math.max(1, Math.round(value)).toString() : value;
    this.kind = kind;
    this.vx = (Math.random() - 0.5) * 30;
  }

  override draw(ctx: CanvasRenderingContext2D): void {
    const t = this.t;
    const y = this.pos.y - t * 22;
    const x = this.pos.x + this.vx * t;
    const a = 1 - t * t;
    let color = "#fff";
    let size = 11;
    if (this.kind === "crit") {
      color = "#ffd84a";
      size = 16;
    } else if (this.kind === "incoming") {
      color = "#ff6464";
      size = 11;
    } else if (this.kind === "heal") {
      color = "#5aff8a";
      size = 12;
    }
    ctx.save();
    ctx.globalAlpha = a;
    ctx.font = `bold ${size}px sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineWidth = 3;
    ctx.strokeStyle = "rgba(0,0,0,0.85)";
    ctx.strokeText(this.text, x, y);
    ctx.fillStyle = color;
    ctx.fillText(this.text, x, y);
    ctx.restore();
  }
}
