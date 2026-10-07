import "./styles/main.css";
import { Game } from "./core/Game";

const canvas = document.getElementById("game-canvas") as HTMLCanvasElement | null;
const overlay = document.getElementById("ui-overlay") as HTMLDivElement | null;
if (!canvas || !overlay) {
  throw new Error("필수 DOM 요소를 찾을 수 없습니다");
}

new Game(canvas, overlay);
