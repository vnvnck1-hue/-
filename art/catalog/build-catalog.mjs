import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const defs = fs.readFileSync(path.join(root, 'godot/scripts/defs.gd'), 'utf8');
const gear = fs.readFileSync(path.join(root, 'godot/scripts/gear.gd'), 'utf8');
function table(text, name) {
  const marker = text.indexOf('const ' + name + ' :=');
  if (marker < 0) throw new Error('Missing table: ' + name);
  const start = text.indexOf('{', marker);
  let depth = 0, quote = false, escape = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (quote) { if (escape) escape = false; else if (c === '\\') escape = true; else if (c === '"') quote = false; continue; }
    if (c === '"') quote = true;
    else if (c === '{') depth++;
    else if (c === '}' && --depth === 0) return JSON.parse(text.slice(start, i + 1).replace(/,\s*([}\]])/g, '$1'));
  }
  throw new Error('Unclosed table: ' + name);
}
const familyNames = { sword: '검', axe: '도끼', bow: '활', staff: '지팡이', shield: '방패', helmet: '투구', ring: '반지', amulet: '목걸이' };
const grades = ['', '일반', '고급', '희귀', '영웅', '전설', '신화', '고대', '태초'];
const base = table(defs, 'ITEMS'), high = table(gear, 'HIGH_NAMES'), legendary = table(defs, 'LEGENDARY'), ascended = table(defs, 'TRANSCENDENT'), relics = table(defs, 'RELICS'), special = table(defs, 'SPECIAL');
const assets = {
  sword1: { image: '../equipment/common-20261011/iron-sword.png', note: '일반 검 시안. 원본 파일명은 iron-sword.png이며 게임의 낡은 검 슬롯에 배치했습니다.' },
  shield1: { image: '../equipment/common-20261011/wooden-shield.png' },
  helmet1: { image: '../equipment/common-20261011/leather-helmet.png' },
  axe1: { image: '../equipment/common-20261011/axe1-hand-axe.png' },
  bow1: { image: '../equipment/common-20261011/bow1-short-bow.png' },
  staff1: { image: '../equipment/common-20261011/staff1-wooden-staff.png' },
  ring1: { image: '../equipment/common-20261011/ring1-copper-ring.png' },
  amulet1: { image: '../equipment/common-20261011/amulet1-wooden-necklace.png' },
  sword2: { image: '../equipment-icons/v2-casual/sword2-steel-sword.png' },
  axe2: { image: '../equipment-icons/v2-casual/axe2-battle-axe.png' },
  shield2: { image: '../equipment-icons/v2-casual/shield2-iron-shield.png' },
  ...Object.fromEntries(Object.keys(relics).map(id => [id, { image: '../relic-icons/v1-casual/' + id + '.png' }]))
};
const completionDir = path.join(root, 'art/equipment-icons/v3-complete');
const completionManifestPath = path.join(completionDir, 'generation-manifest.json');
if (fs.existsSync(completionManifestPath)) {
  const manifest = JSON.parse(fs.readFileSync(completionManifestPath, 'utf8'));
  for (const asset of manifest.assets) {
    if (fs.existsSync(path.join(completionDir, asset.filename))) assets[asset.id] = { image: '../equipment-icons/v3-complete/' + asset.filename };
  }
}
const specialDir = path.join(root, 'art/special-icons/v1-complete');
const specialManifestPath = path.join(specialDir, 'generation-manifest.json');
if (fs.existsSync(specialManifestPath)) {
  const manifest = JSON.parse(fs.readFileSync(specialManifestPath, 'utf8'));
  for (const asset of manifest.assets) {
    if (fs.existsSync(path.join(specialDir, asset.filename))) assets[asset.id] = { image: '../special-icons/v1-complete/' + asset.filename };
  }
}
const items = [];
function add(id, data, group, extra = {}) {
  const asset = assets[id] || {};
  if (asset.image && !fs.existsSync(path.resolve(here, asset.image))) throw new Error('Missing PNG: ' + asset.image);
  items.push({ id, ...data, group, ...extra, ...asset });
}
const nice = v => v < 100 ? Math.round(v) : v < 1000 ? Math.round(v / 5) * 5 : Math.round(v / 10) * 10;
const steps = { critChance: [.02, .45], dmgReduce: [.015, .42], atkSpeedBonus: [.025, .6], dmgBonus: [.06, 1.6], explosionChance: [.02, .4], counterChance: [.02, .4] };
for (const family of Object.keys(familyNames)) for (let tier = 1; tier <= 8; tier++) {
  const id = family + tier;
  if (tier <= 4) add(id, base[id], 'family', { family, grade: grades[tier] });
  else {
    const source = base[family + '4'];
    const stats = Object.fromEntries(Object.entries(source.stats).map(([k, v]) => [k, steps[k] ? Math.min(steps[k][1], Math.round((v + steps[k][0] * (tier - 4)) * 100) / 100) : k === 'range' ? v : nice(v * 1.75 ** (tier - 4))]));
    add(id, { name: high[family][tier - 5], slot: source.slot, tier, stats }, 'family', { family, grade: grades[tier] });
  }
}
for (const [id, data] of Object.entries(legendary)) add(id, data, 'unique', { grade: data.ultra ? '최상위 고유' : '고유' });
add('crown', special.crown, 'unique', { grade: '고유' });
for (const [id, data] of Object.entries(ascended)) add(id, data, 'ascended', { grade: '초월' });
for (const [id, data] of Object.entries(relics)) add(id, data, 'relic', { grade: data.rarity === 'legendary' ? '전설' : '희귀' });
for (const [id, data] of Object.entries(special)) if (!data.equip) add(id, data, 'consumable', { grade: '소모품' });
add('skillbook', { name: '봉인된 스킬북', desc: '공통 책 아이콘 1종. 감정 후 9가지 스킬 표시를 오버레이로 구분하는 제작 계획입니다.' }, 'book', { grade: '공통 템플릿' });
if (items.length !== 99 || items.filter(x => x.group === 'family').length !== 64 || new Set(items.map(x => x.id)).size !== 99) throw new Error('Catalog totals changed; review data.');
const catalog = { title: '세명이 오리라 · 장비 리소스 도감', updated: '2026-10-11', familyNames, grades, items };
fs.writeFileSync(path.join(here, 'catalog-data.json'), JSON.stringify(catalog, null, 2) + '\n');
const template = fs.readFileSync(path.join(here, 'template.html'), 'utf8');
const pngCount = items.filter(x => x.image).length;
const equipmentPngCount = items.filter(x => x.image && ['family', 'unique', 'ascended'].includes(x.group)).length;
const otherPngCount = items.filter(x => x.image && ['consumable', 'book'].includes(x.group)).length;
const html = template.replaceAll('<!-- PNG_COUNT -->', String(pngCount)).replaceAll('<!-- PENDING_COUNT -->', String(items.length - pngCount)).replaceAll('<!-- EQUIPMENT_PNG_COUNT -->', String(equipmentPngCount)).replaceAll('<!-- OTHER_PNG_COUNT -->', String(otherPngCount)).replace('<!-- CATALOG_DATA -->', JSON.stringify(catalog).replace(/</g, '\\u003c'));
fs.writeFileSync(path.join(here, 'index.html'), html);
console.log(JSON.stringify({ html: 'art/catalog/index.html', items: items.length, equipment: items.filter(x => ['family', 'unique', 'ascended'].includes(x.group)).length, png: items.filter(x => x.image).length, pending: items.filter(x => !x.image).length }));

