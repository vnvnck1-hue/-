import { VIEW_W, VIEW_H } from "./Types";

/**
 * 가벼운 화면 흔들림과 줌 강조용 카메라.
 * 좌표 자체를 움직이지는 않고 렌더 전후 transform 값만 제공.
 */
export class Camera {
  shakeTime = 0;
  shakeIntensity = 0;
  flashTime = 0;
  flashColor = "rgba(255,255,255,0)";
  zoom = 1;
  zoomTarget = 1;

  shake(intensity: number, duration = 0.25): void {
    this.shakeTime = Math.max(this.shakeTime, duration);
    this.shakeIntensity = Math.max(this.shakeIntensity, intensity);
  }

  flash(color: string, duration = 0.25): void {
    this.flashTime = Math.max(this.flashTime, duration);
    this.flashColor = color;
  }

  punchZoom(target = 1.06, duration = 0.18): void {
    this.zoomTarget = target;
    this._zoomDuration = duration;
    this._zoomTimer = duration;
  }

  private _zoomDuration = 0;
  private _zoomTimer = 0;

  update(dt: number): void {
    if (this.shakeTime > 0) {
      this.shakeTime -= dt;
      if (this.shakeTime <= 0) {
        this.shakeTime = 0;
        this.shakeIntensity = 0;
      }
    }
    if (this.flashTime > 0) {
      this.flashTime -= dt;
      if (this.flashTime < 0) this.flashTime = 0;
    }
    if (this._zoomTimer > 0) {
      this._zoomTimer -= dt;
      const t = 1 - Math.max(0, this._zoomTimer) / this._zoomDuration;
      this.zoom = 1 + (this.zoomTarget - 1) * Math.sin(t * Math.PI);
      if (this._zoomTimer <= 0) this.zoom = 1;
    } else {
      this.zoom = 1;
    }
  }

  getOffset(): { x: number; y: number } {
    if (this.shakeTime <= 0) return { x: 0, y: 0 };
    const a = this.shakeIntensity * (this.shakeTime > 0.15 ? 1 : this.shakeTime / 0.15);
    return {
      x: (Math.random() - 0.5) * 2 * a,
      y: (Math.random() - 0.5) * 2 * a,
    };
  }

  applyTransform(ctx: CanvasRenderingContext2D): void {
    const off = this.getOffset();
    if (this.zoom !== 1) {
      const cx = VIEW_W / 2;
      const cy = VIEW_H / 2;
      ctx.translate(cx + off.x, cy + off.y);
      ctx.scale(this.zoom, this.zoom);
      ctx.translate(-cx, -cy);
    } else if (off.x !== 0 || off.y !== 0) {
      ctx.translate(off.x, off.y);
    }
  }

  drawFlash(ctx: CanvasRenderingContext2D): void {
    if (this.flashTime <= 0) return;
    const a = this.flashTime / 0.25;
    ctx.save();
    ctx.globalAlpha = Math.min(1, a) * 0.6;
    ctx.fillStyle = this.flashColor;
    ctx.fillRect(0, 0, VIEW_W, VIEW_H);
    ctx.restore();
  }
}
