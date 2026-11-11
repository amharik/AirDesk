import type { WindowBounds } from './window-manager';

export type DesktopTilingMode = 'bsp' | 'ribbon';
export type RibbonEdge = 'left' | 'right' | 'top' | 'bottom';

export interface TilingOptions {
  gap?: number;
  bounds?: WindowBounds;
}

export interface RibbonTilingOptions extends TilingOptions {
  edge?: RibbonEdge;
  ribbonSize?: number;
}

export type WindowLayout = ReadonlyMap<string, WindowBounds>;

function layoutGap(gap: number | undefined): number {
  return Math.max(0, Math.round(gap ?? 8));
}

function splitLength(total: number, gap: number, count: number, index: number): number {
  const available = Math.max(0, total - gap * (count - 1));
  const base = Math.floor(available / count);
  return index === count - 1 ? available - base * (count - 1) : base;
}

function layoutBsp(
  ids: readonly string[],
  area: WindowBounds,
  gap: number,
  output: Map<string, WindowBounds>
): void {
  if (ids.length === 0) return;
  if (ids.length === 1) {
    output.set(ids[0]!, { ...area });
    return;
  }

  const midpoint = Math.ceil(ids.length / 2);
  const first = ids.slice(0, midpoint);
  const second = ids.slice(midpoint);

  if (area.width >= area.height) {
    const available = Math.max(0, area.width - gap);
    const firstWidth = Math.round((available * midpoint) / ids.length);
    layoutBsp(first, { x: area.x, y: area.y, width: firstWidth, height: area.height }, gap, output);
    layoutBsp(
      second,
      {
        x: area.x + firstWidth + gap,
        y: area.y,
        width: available - firstWidth,
        height: area.height
      },
      gap,
      output
    );
  } else {
    const available = Math.max(0, area.height - gap);
    const firstHeight = Math.round((available * midpoint) / ids.length);
    layoutBsp(first, { x: area.x, y: area.y, width: area.width, height: firstHeight }, gap, output);
    layoutBsp(
      second,
      {
        x: area.x,
        y: area.y + firstHeight + gap,
        width: area.width,
        height: available - firstHeight
      },
      gap,
      output
    );
  }
}

function layoutStrip(
  ids: readonly string[],
  area: WindowBounds,
  horizontal: boolean,
  gap: number,
  output: Map<string, WindowBounds>
): void {
  let offset = horizontal ? area.x : area.y;
  ids.forEach((id, index) => {
    const length = splitLength(horizontal ? area.width : area.height, gap, ids.length, index);
    output.set(
      id,
      horizontal
        ? { x: offset, y: area.y, width: length, height: area.height }
        : { x: area.x, y: offset, width: area.width, height: length }
    );
    offset += length + gap;
  });
}

export function computeBspLayout(
  ids: readonly string[],
  bounds: WindowBounds,
  options: TilingOptions = {}
): WindowLayout {
  const output = new Map<string, WindowBounds>();
  layoutBsp(ids, bounds, layoutGap(options.gap), output);
  return output;
}

export function computeRibbonLayout(
  ids: readonly string[],
  bounds: WindowBounds,
  options: RibbonTilingOptions = {}
): WindowLayout {
  const output = new Map<string, WindowBounds>();
  if (ids.length === 0) return output;
  if (ids.length === 1) {
    output.set(ids[0]!, { ...bounds });
    return output;
  }

  const gap = layoutGap(options.gap);
  const edge = options.edge ?? 'right';
  const horizontal = edge === 'left' || edge === 'right';
  const dimension = horizontal ? bounds.width : bounds.height;
  const preferred = options.ribbonSize ?? Math.min(320, Math.max(120, Math.round(dimension * 0.28)));
  const ribbonLength = Math.min(Math.max(0, Math.round(preferred)), Math.round(dimension * 0.75));
  const remaining = Math.max(0, dimension - ribbonLength - gap);
  const main = ids[0]!;
  const ribbon = ids.slice(1);

  if (edge === 'right') {
    output.set(main, { x: bounds.x, y: bounds.y, width: remaining, height: bounds.height });
    layoutStrip(
      ribbon,
      { x: bounds.x + remaining + gap, y: bounds.y, width: ribbonLength, height: bounds.height },
      false,
      gap,
      output
    );
  } else if (edge === 'left') {
    layoutStrip(
      ribbon,
      { x: bounds.x, y: bounds.y, width: ribbonLength, height: bounds.height },
      false,
      gap,
      output
    );
    output.set(main, { x: bounds.x + ribbonLength + gap, y: bounds.y, width: remaining, height: bounds.height });
  } else if (edge === 'bottom') {
    output.set(main, { x: bounds.x, y: bounds.y, width: bounds.width, height: remaining });
    layoutStrip(
      ribbon,
      { x: bounds.x, y: bounds.y + remaining + gap, width: bounds.width, height: ribbonLength },
      true,
      gap,
      output
    );
  } else {
    layoutStrip(
      ribbon,
      { x: bounds.x, y: bounds.y, width: bounds.width, height: ribbonLength },
      true,
      gap,
      output
    );
    output.set(main, { x: bounds.x, y: bounds.y + ribbonLength + gap, width: bounds.width, height: remaining });
  }

  return output;
}

export function computeTilingLayout(
  mode: DesktopTilingMode,
  ids: readonly string[],
  bounds: WindowBounds,
  options: RibbonTilingOptions = {}
): WindowLayout {
  return mode === 'ribbon'
    ? computeRibbonLayout(ids, bounds, options)
    : computeBspLayout(ids, bounds, options);
}
