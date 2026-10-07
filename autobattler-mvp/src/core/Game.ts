import { GameState } from "./GameState";
import { Renderer } from "./Renderer";
import { createParty } from "../entities/Heroes";
import { spawnWave, wavesForStage } from "../systems/WaveSystem";
import { dropFromEnemy } from "../systems/DropSystem";
import { rollPerks, shouldShowPerks } from "../systems/PerkSystem";
import { HUD } from "../ui/HUD";
import { BottomPanel } from "../ui/BottomPanel";
import { PerkOverlay } from "../ui/PerkOverlay";
import { TraitPreviewPanel } from "../ui/TraitPreviewPanel";
import { StartScreen } from "../ui/StartScreen";
import { GameOverScreen } from "../ui/GameOverScreen";
import { DamageText } from "../effects/DamageText";

export class Game {
  state = new GameState();
  renderer: Renderer;
  hud: HUD;
  panel!: BottomPanel;
  perkUI: PerkOverlay;
  startUI: StartScreen;
  gameOverUI: GameOverScreen;
  traitPreview: TraitPreviewPanel;

  private lastTime = performance.now();
  private uiOverlay: HTMLElement;

  constructor(canvas: HTMLCanvasElement, uiOverlay: HTMLElement) {
    this.renderer = new Renderer(canvas);
    this.uiOverlay = uiOverlay;

    this.hud = new HUD(uiOverlay);
    this.perkUI = new PerkOverlay(uiOverlay);
    this.startUI = new StartScreen(uiOverlay);
    this.gameOverUI = new GameOverScreen(uiOverlay);
    this.traitPreview = new TraitPreviewPanel(uiOverlay, () => this.state);

    const restartBtn = document.createElement("button");
    restartBtn.type = "button";
    restartBtn.className = "game-restart-btn";
    restartBtn.textContent = "재시작";
    restartBtn.title = "처음부터 다시 시작합니다";
    restartBtn.addEventListener("click", () => this.restartRun());
    uiOverlay.appendChild(restartBtn);

    // 시작 화면 표시
    this.startUI.show(() => this.beginRun());

    // 메인 루프 시작
    requestAnimationFrame(this.loop);
  }

  /** 언제든 새 런으로 초기화 (특성창·게임오버·특성 프리뷰 모달 정리). */
  private restartRun(): void {
    this.perkUI.cancel();
    this.uiOverlay.querySelectorAll(".start-screen").forEach((n) => n.remove());
    this.uiOverlay.querySelectorAll(".game-over").forEach((n) => n.remove());
    this.uiOverlay.querySelectorAll(".trait-preview-overlay").forEach((n) => n.remove());
    this.traitPreview.clearOverlayRef();
    this.beginRun();
  }

  private beginRun(): void {
    this.state.reset();
    this.state.heroes = createParty();
    if (this.panel) {
      // 기존 패널을 새로 만든다 (영웅 인스턴스가 새것)
      this.panel = new BottomPanel(this.uiOverlay, this.state);
    } else {
      this.panel = new BottomPanel(this.uiOverlay, this.state);
    }
    this.startStage(1);
  }

  private startStage(stage: number): void {
    this.state.stage = stage;
    this.state.wave = 0;
    this.state.totalWaves = wavesForStage(stage);
    this.queuePhase("wavePrep", 0.25);
  }

  private startNextWave(): void {
    this.state.wave += 1;
    spawnWave(this.state);
    this.state.phase = "fighting";
    this.state.phaseTimer = 0;
    this.state.camera.flash("rgba(255,255,255,0.4)", 0.18);
  }

  private queuePhase(next: GameState["phase"], delay: number): void {
    this.state.phase = next;
    this.state.phaseTimer = delay;
  }

  private async showPerkChoice(): Promise<boolean> {
    this.state.phase = "perkChoice";
    const perks = rollPerks();
    const chosen = await this.perkUI.show(perks);
    if (!chosen) return false;
    chosen.apply(this.state);
    this.state.perksTaken += 1;
    this.state.appliedPerks.push({
      id: chosen.id,
      name: chosen.name,
      desc: chosen.desc,
    });
    // 특성 효과 시각 피드백
    for (const h of this.state.heroes) {
      if (!h.alive) continue;
      this.state.effects.push(new DamageText(h.pos, "+" + chosen.name, "heal"));
    }
    this.state.camera.flash("rgba(255,220,120,0.5)", 0.4);
    return true;
  }

  private update(dt: number): void {
    const s = this.state;
    s.time += dt;
    s.camera.update(dt);

    if (s.phase === "intro") return;
    if (s.phase === "perkChoice") return; // 입력 대기

    // 엔티티 업데이트
    for (const h of s.heroes) h.update(dt, s);
    for (const e of s.enemies) e.update(dt, s);
    for (const p of s.projectiles) p.update(dt, s);
    for (const p of s.pickups) p.update(dt, s);
    for (const e of s.effects) e.update(dt);

    // 사망 처리: 적 → 드랍
    for (const e of s.enemies) {
      if (!e.alive && !(e as any)._dropped) {
        (e as any)._dropped = true;
        dropFromEnemy(e, s);
        s.camera.shake(1.5, 0.12);
      }
    }

    // 정리
    s.enemies = s.enemies.filter((e) => e.alive);
    s.projectiles = s.projectiles.filter((p) => p.alive);
    s.pickups = s.pickups.filter((p) => p.alive);
    s.effects = s.effects.filter((e) => e.alive);

    // 페이즈 전환 로직
    if (s.phase === "wavePrep") {
      s.phaseTimer -= dt;
      if (s.phaseTimer <= 0) this.startNextWave();
    } else if (s.phase === "fighting") {
      if (s.waveModifier === "timeBonus" && s.waveTimeLeft > 0) {
        s.waveTimeLeft -= dt;
      }
      // 모두 사망 → 게임 오버
      if (s.heroes.every((h) => !h.alive)) {
        s.phase = "gameOver";
        this.gameOverUI.show(s, () => this.beginRun());
        return;
      }
      // 적 모두 처치 → 웨이브 클리어
      if (s.enemies.length === 0 && s.pickups.length === 0) {
        if (s.waveModifier === "timeBonus" && s.waveTimeLeft > 0) {
          const bonus = 14 + s.stage * 5;
          s.gold += bonus;
          const h = s.heroes.find((x) => x.alive);
          if (h) s.effects.push(new DamageText(h.pos, `+${bonus}G`, "heal"));
        }
        s.phase = "waveCleared";
        s.phaseTimer = 0.2;
      }
    } else if (s.phase === "waveCleared") {
      s.phaseTimer -= dt;
      if (s.phaseTimer <= 0) {
        if (shouldShowPerks(s)) {
          this.showPerkChoice().then((applied) => {
            if (applied) this.queueAfterPerk();
          });
        } else {
          this.queueAfterPerk();
        }
      }
    } else if (s.phase === "stageClear") {
      s.phaseTimer -= dt;
      if (s.phaseTimer <= 0) this.startStage(s.stage + 1);
    }

    // UI 갱신
    this.hud.update(s);
    if (this.panel) this.panel.update(s);
  }

  private queueAfterPerk(): void {
    const s = this.state;
    if (s.wave >= s.totalWaves) {
      s.phase = "stageClear";
      s.phaseTimer = 0.5;
      s.camera.flash("rgba(180,255,180,0.4)", 0.4);
    } else {
      this.queuePhase("wavePrep", 0.18);
    }
  }

  private draw(): void {
    const { ctx } = this.renderer;
    this.renderer.begin();
    ctx.save();
    this.state.camera.applyTransform(ctx);
    this.renderer.drawBackground(this.state.time * 1000);

    // 픽업 → 적 → 영웅 → 발사체 → 이펙트 순서로 그려서 가시성 확보
    for (const p of this.state.pickups) p.draw(ctx);
    for (const e of this.state.enemies) e.draw(ctx);
    for (const h of this.state.heroes) h.draw(ctx);
    for (const p of this.state.projectiles) p.draw(ctx);
    for (const e of this.state.effects) e.draw(ctx);

    ctx.restore();

    // 카메라 플래시는 고정된 화면 위에 그림
    this.state.camera.drawFlash(ctx);
    this.renderer.end();
  }

  private loop = (now: number): void => {
    const dt = Math.min(0.05, (now - this.lastTime) / 1000);
    this.lastTime = now;
    this.update(dt);
    this.draw();
    requestAnimationFrame(this.loop);
  };
}
