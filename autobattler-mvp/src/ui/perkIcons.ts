const SVG_NS = "http://www.w3.org/2000/svg";

function svg(inner: string, viewBox = "0 0 24 24"): string {
  return `<svg class="perk-icon-svg" viewBox="${viewBox}" xmlns="${SVG_NS}" aria-hidden="true">${inner}</svg>`;
}

export function perkIconSvg(perkId: string): string {
  switch (perkId) {
    case "atk":
      // 검
      return svg(
        `<path d="M14.6 3.2l6.2 6.2-2.3 2.3-6.2-6.2 2.3-2.3z" fill="currentColor" opacity="0.95"/>
         <path d="M11 6.8l6.2 6.2-7.9 7.9c-.5.5-1.3.5-1.8 0l-2-2c-.5-.5-.5-1.3 0-1.8L11 6.8z" fill="currentColor"/>
         <path d="M4 20l3.2-3.2 2 2L6 22H4v-2z" fill="currentColor" opacity="0.75"/>`
      );
    case "atkSpd":
      // 속도 화살표
      return svg(
        `<path d="M4 13h9l-2.5 2.5 1.4 1.4L17.8 12l-5.9-4.9-1.4 1.4L13 11H4v2z" fill="currentColor"/>
         <path d="M4 8h7l-2 2 1.4 1.4L15.8 7 10.4 2.6 9 4l2 2H4v2z" fill="currentColor" opacity="0.75"/>`
      );
    case "hp":
      // 하트
      return svg(
        `<path d="M12 21s-7-4.6-9.2-8.6C1 8.6 3.5 6 6.6 6c1.7 0 3.1.8 3.9 2 0 0 .8-2 3.9-2 3.1 0 5.6 2.6 3.8 6.4C19 16.4 12 21 12 21z" fill="currentColor"/>`
      );
    case "explode":
      // 폭발
      return svg(
        `<path d="M13 2l1.2 4.2L18 4l-2.2 3.8L20 9l-4.2 1.2L18 14l-3.8-2.2L13 16l-1.2-4.2L8 14l2.2-3.8L6 9l4.2-1.2L8 4l3.8 2.2L13 2z" fill="currentColor"/>
         <circle cx="12" cy="10" r="2.2" fill="currentColor" opacity="0.7"/>`
      );
    case "lifesteal":
      // 피 한방울
      return svg(
        `<path d="M12 2s-6 7-6 11a6 6 0 0012 0c0-4-6-11-6-11z" fill="currentColor"/>
         <path d="M9.5 14.2c.6 1.3 2 2.2 3.6 2.2" stroke="rgba(0,0,0,0.25)" stroke-width="2" stroke-linecap="round" fill="none"/>`
      );
    case "crit":
      // 별(치명)
      return svg(
        `<path d="M12 2l2.5 6.2L21 9l-5 4.1L17.6 20 12 16.7 6.4 20 8 13.1 3 9l6.5-.8L12 2z" fill="currentColor"/>`
      );
    case "critDmg":
      // 타겟
      return svg(
        `<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/>
         <circle cx="12" cy="12" r="5" fill="none" stroke="currentColor" stroke-width="2" opacity="0.85"/>
         <circle cx="12" cy="12" r="1.8" fill="currentColor"/>
         <path d="M12 3v3M12 18v3M3 12h3M18 12h3" stroke="currentColor" stroke-width="2" stroke-linecap="round" opacity="0.6"/>`,
        "0 0 24 24"
      );
    case "regen":
      // 십자가(회복)
      return svg(
        `<path d="M10 3h4v5h5v4h-5v5h-4v-5H5V8h5V3z" fill="currentColor"/>`
      );
    default:
      // 기본: 반짝임
      return svg(
        `<path d="M12 3l1.1 4.1L17 8l-3.9 1L12 13l-1.1-4-3.9-1 3.9-.9L12 3z" fill="currentColor"/>`
      );
  }
}

