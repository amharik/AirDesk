import { describe, expect, it } from 'vitest';
import { computeBspLayout, computeRibbonLayout, computeTilingLayout } from '../src/desktop/tiling';
import type { WindowBounds } from '../src/desktop/window-manager';

const bounds: WindowBounds = { x: 0, y: 0, width: 1000, height: 600 };

function expectContained(area: WindowBounds, layout: ReadonlyMap<string, WindowBounds>): void {
  for (const tile of layout.values()) {
    expect(tile.x).toBeGreaterThanOrEqual(area.x);
    expect(tile.y).toBeGreaterThanOrEqual(area.y);
    expect(tile.x + tile.width).toBeLessThanOrEqual(area.x + area.width);
    expect(tile.y + tile.height).toBeLessThanOrEqual(area.y + area.height);
  }
}

describe('desktop tiling', () => {
  it('splits BSP panes along the longest edge with gaps', () => {
    const layout = computeBspLayout(['terminal', 'notes', 'files', 'preview'], bounds, { gap: 10 });

    expect([...layout.keys()]).toEqual(['terminal', 'notes', 'files', 'preview']);
    expect(layout.get('terminal')).toEqual({ x: 0, y: 0, width: 495, height: 295 });
    expect(layout.get('notes')).toEqual({ x: 0, y: 305, width: 495, height: 295 });
    expect(layout.get('files')).toEqual({ x: 505, y: 0, width: 495, height: 295 });
    expect(layout.get('preview')).toEqual({ x: 505, y: 305, width: 495, height: 295 });
    expectContained(bounds, layout);
  });

  it('keeps a single pane at the full bounds', () => {
    expect(computeBspLayout(['terminal'], bounds)).toEqual(
      new Map([['terminal', bounds]])
    );
  });

  it('places overflow panes in a right-hand ribbon behind the main pane', () => {
    const layout = computeRibbonLayout(['terminal', 'notes', 'files'], bounds, {
      gap: 10,
      edge: 'right'
    });

    expect(layout.get('terminal')).toEqual({ x: 0, y: 0, width: 710, height: 600 });
    expect(layout.get('notes')).toEqual({ x: 720, y: 0, width: 280, height: 295 });
    expect(layout.get('files')).toEqual({ x: 720, y: 305, width: 280, height: 295 });
    expectContained(bounds, layout);
  });

  it('supports left, top and bottom ribbon edges', () => {
    const left = computeRibbonLayout(['main', 'one', 'two'], bounds, {
      gap: 10,
      edge: 'left',
      ribbonSize: 240
    });
    expect(left.get('main')).toEqual({ x: 250, y: 0, width: 750, height: 600 });
    expect(left.get('one')).toEqual({ x: 0, y: 0, width: 240, height: 295 });

    const top = computeRibbonLayout(['main', 'one', 'two'], bounds, {
      gap: 10,
      edge: 'top',
      ribbonSize: 180
    });
    expect(top.get('main')).toEqual({ x: 0, y: 190, width: 1000, height: 410 });
    expect(top.get('one')).toEqual({ x: 0, y: 0, width: 495, height: 180 });
    expect(top.get('two')).toEqual({ x: 505, y: 0, width: 495, height: 180 });

    const bottom = computeRibbonLayout(['main', 'one', 'two'], bounds, {
      gap: 10,
      edge: 'bottom',
      ribbonSize: 180
    });
    expect(bottom.get('main')).toEqual({ x: 0, y: 0, width: 1000, height: 410 });
    expect(bottom.get('one')).toEqual({ x: 0, y: 420, width: 495, height: 180 });
  });

  it('dispatches the selected tiling mode', () => {
    expect(computeTilingLayout('bsp', ['a', 'b'], bounds, { gap: 20 }).get('a')).toEqual({
      x: 0,
      y: 0,
      width: 490,
      height: 600
    });
    expect(computeTilingLayout('ribbon', ['a'], bounds, { gap: 20 }).get('a')).toEqual(bounds);
  });
});
