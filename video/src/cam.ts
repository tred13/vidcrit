import { Easing } from 'remotion';
import { Scene, ViewState } from './types';
import { merc, W } from './geo';

export const ease = Easing.bezier(0.65, 0, 0.2, 1);
export const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;

export type MapCam = { cx: number; cy: number; span: number };
export type GlobeCam = { lon: number; lat: number; r: number };

type Gen<T> = {
  mk: (v: ViewState) => T;
  drift: (c: T, f: number) => T;
  intro: (c: T) => T;
  lerp: (a: T, b: T, p: number) => T;
  dist: (a: T, b: T) => number;
};

export const mapGen: Gen<MapCam> = {
  mk: (v) => {
    const p = merc([v.lon, v.lat]) as [number, number];
    return { cx: p[0], cy: p[1], span: v.span || 100 };
  },
  drift: (c, f) => ({ ...c, span: c.span * (1 - 0.06 * f) }),
  intro: (c) => ({ ...c, span: c.span * 1.18 }),
  dist: (a, b) =>
    Math.hypot(b.cx - a.cx, b.cy - a.cy) / ((W * Math.min(a.span, b.span)) / 360) +
    Math.abs(Math.log(b.span / a.span)) * 0.5,
  lerp: (a, b, p) => {
    const d = mapGen.dist(a, b);
    const bump = Math.min(0.7, 0.22 * Math.log(1 + d * 1.5));
    const ls = lerp(Math.log(a.span), Math.log(b.span), p) + bump * Math.sin(Math.PI * p);
    return { cx: lerp(a.cx, b.cx, p), cy: lerp(a.cy, b.cy, p), span: Math.exp(ls) };
  },
};

const dlon = (a: number, b: number) => ((((b - a) % 360) + 540) % 360) - 180;
export const globeGen: Gen<GlobeCam> = {
  mk: (v) => ({ lon: v.lon, lat: v.lat, r: v.r || 520 }),
  drift: (c, f) => ({ lon: c.lon + 3 * f, lat: c.lat, r: c.r * (1 + 0.05 * f) }),
  intro: (c) => ({ lon: c.lon - 18, lat: c.lat - 6, r: c.r * 0.82 }),
  dist: (a, b) => (Math.abs(dlon(a.lon, b.lon)) + Math.abs(b.lat - a.lat)) / 70 + Math.abs(Math.log(b.r / a.r)) * 0.5,
  lerp: (a, b, p) => {
    const d = globeGen.dist(a, b);
    const bump = Math.min(0.35, 0.12 * Math.log(1 + d * 2));
    const lr = lerp(Math.log(a.r), Math.log(b.r), p) - bump * Math.sin(Math.PI * p);
    return { lon: a.lon + dlon(a.lon, b.lon) * p, lat: lerp(a.lat, b.lat, p), r: Math.exp(lr) };
  },
};

export function sceneIndexAt(scenes: Scene[], t: number): number {
  let i = 0;
  for (let k = 0; k < scenes.length; k++) if (scenes[k].start <= t) i = k;
  return i;
}

export function layerState<T>(scenes: Scene[], t: number, mode: 'map' | 'globe', g: Gen<T>) {
  const i = sceneIndexAt(scenes, t);
  let j = -1;
  for (let k = i; k >= 0; k--) {
    if (scenes[k].mode === mode) {
      j = k;
      break;
    }
  }
  if (j < 0) return null;
  const s = scenes[j];
  const tt = Math.min(t, s.end);
  const dur = s.end - s.start;
  const frac = clamp01((tt - s.start) / dur);
  const to = g.drift(g.mk(s.view), frac);
  let prev = -1;
  for (let k = j - 1; k >= 0; k--) {
    if (scenes[k].mode === mode) {
      prev = k;
      break;
    }
  }
  let from: T;
  if (s.view.from) from = g.mk(s.view.from);
  else if (prev >= 0) from = g.drift(g.mk(scenes[prev].view), 1);
  else from = g.intro(to);
  const Tm = Math.min(0.9, dur * 0.55);
  const p = ease(clamp01((tt - s.start) / Tm));
  const cam = g.lerp(from, to, p);
  const m = Math.min(1, g.dist(from, to) / 1.5);
  return { cam, p, blur: 18 * m * 4 * p * (1 - p) };
}

export function layerOpacity(scenes: Scene[], t: number, mode: 'map' | 'globe'): number {
  const i = sceneIndexAt(scenes, t);
  const cur = scenes[i];
  const prev = i > 0 ? scenes[i - 1] : null;
  const f = ease(clamp01((t - cur.start) / 0.35));
  if (cur.mode === mode) return prev && prev.mode !== mode ? f : 1;
  return prev && prev.mode === mode ? 1 - f : 0;
}
