import type { ItemData, Rarity, EquipSlot } from "../core/Types";
import { RARITY_WEIGHT } from "../core/Types";
import { weightedPick, pick, randInt } from "../core/Random";

const WEAPON_NAMES = ["검", "도끼", "창", "활", "마법봉", "단검", "곤봉"];
const ARMOR_NAMES = ["사슬갑옷", "가죽갑옷", "판금", "로브", "비늘갑옷"];
const ACC_NAMES = ["반지", "목걸이", "팔찌", "부적", "장갑"];

let itemSeq = 0;

export function rollRarity(scaleBoost = 0): Rarity {
  const ws = { ...RARITY_WEIGHT };
  // 후반 스테이지로 갈수록 희귀도 가중
  ws.rare = ws.rare + scaleBoost * 6;
  ws.epic = ws.epic + scaleBoost * 4;
  ws.legendary = ws.legendary + scaleBoost * 1.2;
  const items = ["common", "rare", "epic", "legendary"] as Rarity[];
  return weightedPick(items, items.map((r) => ws[r]));
}

export function rollItem(level = 1): ItemData {
  const slot = pick<EquipSlot>(["weapon", "armor", "accessory"]);
  const rarity = rollRarity(level / 10);
  const tier = rarityTier(rarity);
  const name =
    slot === "weapon" ? pick(WEAPON_NAMES) :
    slot === "armor" ? pick(ARMOR_NAMES) : pick(ACC_NAMES);

  const stats = rollStats(slot, tier, level);
  return {
    id: `item-${++itemSeq}`,
    slot,
    name: prefixForRarity(rarity) + name,
    rarity,
    stats,
  };
}

function rarityTier(r: Rarity): number {
  return r === "common" ? 1 : r === "rare" ? 2 : r === "epic" ? 3 : 5;
}

function prefixForRarity(r: Rarity): string {
  return r === "common" ? "" : r === "rare" ? "정교한 " : r === "epic" ? "영웅의 " : "전설의 ";
}

function rollStats(slot: EquipSlot, tier: number, level: number): ItemData["stats"] {
  const lv = Math.max(1, level);
  if (slot === "weapon") {
    return {
      atk: randInt(2, 5) * tier + lv * 2,
      atkSpd: tier > 2 ? +(0.05 * tier).toFixed(2) : 0,
      crit: tier > 2 ? +(0.03 * (tier - 2)).toFixed(2) : 0,
    };
  }
  if (slot === "armor") {
    return {
      hp: randInt(15, 30) * tier + lv * 6,
      atk: tier > 2 ? randInt(0, 2) * tier : 0,
    };
  }
  // accessory
  return {
    hp: randInt(5, 12) * tier + lv * 2,
    atk: randInt(0, 2) * tier,
    atkSpd: +(0.04 * tier).toFixed(2),
    crit: +(0.02 * tier).toFixed(2),
  };
}
