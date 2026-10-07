export abstract class Effect {
  alive = true;
  /** 0~1 진행도. 모든 이펙트 공통 */
  t = 0;
  duration: number;

  constructor(duration: number) {
    this.duration = duration;
  }

  update(dt: number): void {
    this.t += dt / this.duration;
    if (this.t >= 1) this.alive = false;
  }

  abstract draw(ctx: CanvasRenderingContext2D): void;
}
