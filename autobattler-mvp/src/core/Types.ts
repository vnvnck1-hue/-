export type Vec2 = { x: number; y: number };

export type Faction = "ally" | "enemy";

export type HeroClass = "warrior" | "archer" | "mage";

export type EnemyKind =
  | "goblin"
  | "goblinArcher"
  | "orc"
  | "brute"
  | "charger"
  | "shaman";

export type Rarity = "common" | "rare" | "epic" | "legendary";

export const RARITY_COLOR: Record<Rarity, string> = {
  common: "#9aa0aa",
  rare: "#4aa6ff",
  epic: "#c66aff",
  legendary: "#ffc83a",
};

export const RARITY_WEIGHT: Record<Rarity, number> = {
  common: 60,
  rare: 28,
  epic: 10,
  legendary: 2,
};

export type EquipSlot = "weapon" | "armor" | "accessory";

export interface ItemStats {
  atk?: number;
  hp?: number;
  atkSpd?: number;
  crit?: number;
}

export interface ItemData {
  id: string;
  name: string;
  slot: EquipSlot;
  rarity: Rarity;
  stats: ItemStats;
}

export interface PerkData {
  id: string;
  name: string;
  desc: string;
  apply: (state: import("./GameState").GameState) => void;
}

export const COLORS = {
  warrior: "#ff5a4a",
  archer: "#52d680",
  mage: "#5aa6ff",
  enemy: "#c46666",
  enemyArcher: "#a4624a",
  enemyTank: "#7a3a3a",
  enemyBrute: "#8a4a8a",
  enemyCharger: "#c45a40",
  enemyShaman: "#3a8a6a",
};

/** 게임 좌표계 (논리 해상도). 실제 캔버스는 이 비율로 스케일됨. */
export const VIEW_W = 360;
export const VIEW_H = 640;

/** 전투가 진행되는 영역 (상단/하단 UI 제외) */
export const BATTLE_TOP = 90;
export const BATTLE_BOTTOM = VIEW_H - 200;
export const BATTLE_LEFT = 16;
export const BATTLE_RIGHT = VIEW_W - 16;
