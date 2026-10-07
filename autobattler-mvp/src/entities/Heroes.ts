import { Hero, type HeroConfig } from "./Hero";
import { COLORS, BATTLE_BOTTOM, BATTLE_LEFT, BATTLE_RIGHT } from "../core/Types";

export const WARRIOR_CFG: HeroConfig = {
  className: "warrior",
  displayName: "전사",
  baseHp: 400,
  baseAtk: 14,
  baseAtkSpd: 2.2,
  attackRange: 28,
  preferredDistance: 0,
  moveSpeed: 140,
  color: COLORS.warrior,
  maxMana: 100,
  manaPerAttack: 8,
};

export const ARCHER_CFG: HeroConfig = {
  className: "archer",
  displayName: "궁수",
  baseHp: 120,
  baseAtk: 12,
  baseAtkSpd: 3.2,
  attackRange: 160,
  preferredDistance: 130,
  moveSpeed: 150,
  color: COLORS.archer,
  maxMana: 100,
  manaPerAttack: 6,
};

export const MAGE_CFG: HeroConfig = {
  className: "mage",
  displayName: "마법사",
  baseHp: 100,
  baseAtk: 16,
  baseAtkSpd: 1.7,
  attackRange: 180,
  preferredDistance: 170,
  moveSpeed: 120,
  color: COLORS.mage,
  maxMana: 110,
  manaPerAttack: 7,
};

export function createParty(): Hero[] {
  const yBottom = BATTLE_BOTTOM - 30;
  const cx = (BATTLE_LEFT + BATTLE_RIGHT) / 2;
  const warrior = new Hero(WARRIOR_CFG, { x: cx, y: yBottom - 10 });
  const archer = new Hero(ARCHER_CFG, { x: cx - 60, y: yBottom });
  const mage = new Hero(MAGE_CFG, { x: cx + 60, y: yBottom });
  warrior.setHome(cx, yBottom - 10);
  archer.setHome(cx - 60, yBottom);
  mage.setHome(cx + 60, yBottom);
  return [warrior, archer, mage];
}
