import { feature } from 'topojson-client';
import {
  geoMercator,
  geoPath,
  geoTransform,
  geoRotation,
  geoCentroid,
  geoInterpolate,
  geoGraticule10,
} from 'd3-geo';
import topo from 'world-atlas/countries-50m.json';

const fc: any = feature(topo as any, (topo as any).objects.countries);
export const allFeatures: any[] = fc.features;
export const features: any[] = allFeatures.filter((f) => f.properties.name !== 'Antarctica');
export const byName = new Map<string, any>(allFeatures.map((f) => [f.properties.name, f]));
export const landFC: any = { type: 'FeatureCollection', features: allFeatures };

export const AFRICA = [
  'Algeria', 'Angola', 'Benin', 'Botswana', 'Burkina Faso', 'Burundi', 'Cameroon', 'Central African Rep.',
  'Chad', 'Comoros', 'Congo', 'Dem. Rep. Congo', 'Djibouti', 'Egypt', 'Eq. Guinea', 'Eritrea', 'eSwatini',
  'Ethiopia', 'Gabon', 'Gambia', 'Ghana', 'Guinea', 'Guinea-Bissau', "Côte d'Ivoire", 'Kenya', 'Lesotho',
  'Liberia', 'Libya', 'Madagascar', 'Malawi', 'Mali', 'Mauritania', 'Morocco', 'Mozambique', 'Namibia',
  'Niger', 'Nigeria', 'Rwanda', 'Senegal', 'Sierra Leone', 'Somalia', 'Somaliland', 'South Africa',
  'S. Sudan', 'Sudan', 'Tanzania', 'Togo', 'Tunisia', 'Uganda', 'W. Sahara', 'Zambia', 'Zimbabwe',
];

export const idsFor = (ev: any): string[] => (ev.group === 'africa' ? AFRICA : ev.ids || []);
export const featsFor = (ids: string[]) => ids.map((n) => byName.get(n)).filter(Boolean);

// ---- Mercator (flat map) -------------------------------------------------
export const W = 4096;
export const merc = geoMercator().scale(W / (2 * Math.PI)).translate([W / 2, W / 2]).precision(0.2);
const mpath = geoPath(merc);
export const landD: string = mpath({ type: 'FeatureCollection', features } as any) || '';
export const gratD: string = mpath(geoGraticule10()) || '';

const hlCache = new Map<string, string>();
export function mercHighlightD(ids: string[]): string {
  const key = ids.join('|');
  let d = hlCache.get(key);
  if (d === undefined) {
    d = mpath({ type: 'FeatureCollection', features: featsFor(ids) } as any) || '';
    hlCache.set(key, d);
  }
  return d;
}

export function centroidOf(ev: any): [number, number] {
  if (ev.labelAt) return ev.labelAt;
  const f = byName.get((ev.ids || [])[0]);
  return f ? (geoCentroid(f) as [number, number]) : [0, 0];
}

/** "True size" ghost: moves a country along the globe keeping its real size, then draws it in Mercator. */
export function ghostPath(country: string, from: [number, number], to: [number, number], p: number): string {
  const f = byName.get(country);
  if (!f) return '';
  const rc = geoRotation([-from[0], -from[1]]);
  const cur: [number, number] = [from[0] + (to[0] - from[0]) * p, from[1] + (to[1] - from[1]) * p];
  const rt = geoRotation([-cur[0], -cur[1]]);
  const tr = geoTransform({
    point(this: any, x: number, y: number) {
      const q = rt.invert(rc([x, y])) as [number, number];
      const s = merc(q);
      if (s) this.stream.point(s[0], s[1]);
    },
  });
  return geoPath(tr)(f) || '';
}

// ---- great-circle polylines ----------------------------------------------
export function arcCoords(pts: [number, number][], p: number, n = 18): [number, number][] {
  const all: [number, number][] = [pts[0]];
  for (let i = 0; i < pts.length - 1; i++) {
    const it = geoInterpolate(pts[i], pts[i + 1]);
    for (let k = 1; k <= n; k++) all.push(it(k / n) as [number, number]);
  }
  const cnt = Math.max(2, Math.ceil((all.length - 1) * Math.min(1, Math.max(0, p))) + 1);
  return all.slice(0, cnt);
}
