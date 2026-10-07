export function rand(min: number, max: number): number {
  return min + Math.random() * (max - min);
}

export function randInt(min: number, max: number): number {
  return Math.floor(min + Math.random() * (max - min + 1));
}

export function chance(p: number): boolean {
  return Math.random() < p;
}

export function pick<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]!;
}

export function pickN<T>(arr: readonly T[], n: number): T[] {
  const pool = [...arr];
  const result: T[] = [];
  while (result.length < n && pool.length > 0) {
    const idx = Math.floor(Math.random() * pool.length);
    result.push(pool.splice(idx, 1)[0]!);
  }
  return result;
}

export function weightedPick<T>(items: readonly T[], weights: readonly number[]): T {
  const total = weights.reduce((a, b) => a + b, 0);
  let r = Math.random() * total;
  for (let i = 0; i < items.length; i++) {
    r -= weights[i]!;
    if (r <= 0) return items[i]!;
  }
  return items[items.length - 1]!;
}
