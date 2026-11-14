import React, { useMemo } from 'react';
import { AbsoluteFill, interpolate, random, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { loadFont } from '@remotion/google-fonts/Montserrat';
import { geoDistance, geoGraticule10, geoOrthographic, geoPath } from 'd3-geo';
import timingJson from './timing.json';
import { Ev, Scene, Timing, Word } from './types';
import {
  arcCoords, centroidOf, featsFor, gratD, ghostPath, idsFor, landD, landFC, merc, mercHighlightD, W,
} from './geo';
import { clamp01, ease, globeGen, layerOpacity, layerState, mapGen, sceneIndexAt } from './cam';

export const timing = timingJson as unknown as Timing;
const { fontFamily } = loadFont('normal', { weights: ['800', '900'], subsets: ['latin'] });

const VW = 1080;
const VH = 1920;
const MAP_CY = 860;
const GLOBE_CY = 830;
const OCEAN_TOP = '#8fdcfa';
const OCEAN_BOTTOM = '#6cc9f2';
const LAND = '#fbf8ef';

const fmtNum = (v: number, f?: string) => (f === 'comma' ? Math.round(v).toLocaleString('en-US') : String(Math.round(v)));

// ------------------------------------------------------------------ captions
type Chunk = { start: number; end: number; words: Word[] };
function buildChunks(scenes: Scene[]): Chunk[] {
  const out: Chunk[] = [];
  scenes.forEach((sc) => {
    let cur: Word[] = [];
    const flush = () => {
      if (cur.length) out.push({ start: cur[0].start, end: sc.end, words: cur });
      cur = [];
    };
    sc.words.forEach((w) => {
      cur.push(w);
      const len = cur.map((x) => x.w).join(' ').length;
      if (cur.length >= 3 || /[.,?!:;]$/.test(w.w) || (cur.length === 2 && len > 15)) flush();
    });
    flush();
  });
  for (let i = 0; i < out.length - 1; i++) {
    if (out[i + 1].start > out[i].start && out[i].end > out[i + 1].start) out[i].end = out[i + 1].start;
  }
  return out;
}

const Caption: React.FC<{ t: number; chunks: Chunk[] }> = ({ t, chunks }) => {
  const { fps } = useVideoConfig();
  let idx = -1;
  for (let i = 0; i < chunks.length; i++) if (chunks[i].start <= t) idx = i;
  if (idx < 0) return null;
  const c = chunks[idx];
  if (t > timing.voiceEnd) return null;
  const text = c.words.map((w) => w.w).join(' ');
  const size = Math.min(96, Math.floor(950 / (text.length * 0.74)));
  const sp = spring({ frame: (t - c.start) * fps, fps, config: { damping: 13, stiffness: 260, mass: 0.6 } });
  const scale = interpolate(sp, [0, 1], [0.7, 1]);
  return (
    <div style={{ position: 'absolute', left: 40, right: 40, top: 1330, height: 190, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div
        style={{
          transform: `scale(${scale})`,
          fontFamily, fontWeight: 900, fontSize: size, lineHeight: 1.05, textAlign: 'center', textTransform: 'uppercase',
          color: '#fff', WebkitTextStroke: `${Math.round(size * 0.2)}px #0a0a0a`, paintOrder: 'stroke fill',
          textShadow: '0 8px 0 rgba(0,0,0,0.55)', letterSpacing: 1,
        }}
      >
        {c.words.map((w, i) => (
          <span key={i} style={{ color: w.emph ? '#ffe14d' : '#fff' }}>
            {w.w}
            {i < c.words.length - 1 ? ' ' : ''}
          </span>
        ))}
      </div>
    </div>
  );
};

// ------------------------------------------------------------------ overlays
const Sticker: React.FC<{ ev: Ev; t: number }> = ({ ev, t }) => {
  const { fps } = useVideoConfig();
  const sp = spring({ frame: (t - ev.time) * fps, fps, config: { damping: 8, stiffness: 150, mass: 0.7 } });
  const out = clamp01((ev.end - t) / 0.15);
  const scale = sp * out;
  const wob = Math.sin((t - ev.time) * 5) * 4;
  const float = Math.sin((t - ev.time) * 2.4) * 8;
  const o = 7;
  const filter = [`${o}px 0 0 #fff`, `-${o}px 0 0 #fff`, `0 ${o}px 0 #fff`, `0 -${o}px 0 #fff`, `${o}px ${o}px 0 #fff`, `-${o}px -${o}px 0 #fff`]
    .map((s) => `drop-shadow(${s})`)
    .join(' ') + ' drop-shadow(0 14px 14px rgba(0,0,0,0.4))';
  return (
    <img
      src={staticFile(`emoji/${ev.emoji}.svg`)}
      style={{
        position: 'absolute', left: ev.x * VW - ev.size / 2, top: ev.y * VH - ev.size / 2 + float, width: ev.size, height: ev.size,
        transform: `rotate(${ev.rot + wob}deg) scale(${scale})`, filter,
      }}
    />
  );
};

const Stat: React.FC<{ ev: Ev; t: number }> = ({ ev, t }) => {
  const { fps } = useVideoConfig();
  const sp = spring({ frame: (t - ev.time) * fps, fps, config: { damping: 9, stiffness: 170, mass: 0.8 } });
  const out = clamp01((ev.end - t) / 0.15);
  let text: string = ev.text || '';
  if (ev.to !== undefined) {
    const q = 1 - Math.pow(1 - clamp01((t - ev.time) / 1.0), 3);
    text = (ev.prefix || '') + fmtNum(ev.to * q, ev.format) + (ev.suffix === 'x' ? '×' : ev.suffix || '');
  }
  const style = ev.style || 'num';
  const color = style === 'stamp' ? '#ff2d2d' : '#ff8a1f';
  const lines = text.split('\n');
  return (
    <div
      style={{
        position: 'absolute', left: 0, width: VW, top: ev.y * VH, transform: `translateY(-50%) rotate(${ev.rot}deg) scale(${sp * out})`,
        display: 'flex', flexDirection: 'column', alignItems: 'center', fontFamily,
      }}
    >
      {style === 'pill' ? (
        <div style={{ background: '#ff2d2d', color: '#fff', fontWeight: 900, fontSize: ev.size, padding: '22px 56px', borderRadius: 999, boxShadow: '0 12px 0 rgba(0,0,0,0.35)', border: '8px solid #fff' }}>
          {text}
        </div>
      ) : (
        <div
          style={{
            fontWeight: 900, fontSize: ev.size, lineHeight: 0.95, textAlign: 'center', color,
            WebkitTextStroke: `${Math.round(ev.size * 0.11)}px #fff`, paintOrder: 'stroke fill',
            textShadow: '0 12px 0 rgba(0,0,0,0.35)', whiteSpace: 'pre',
          }}
        >
          {lines.join('\n')}
        </div>
      )}
      {ev.sub ? (
        <div style={{ marginTop: 22, background: '#0b1e4a', color: '#fff', fontWeight: 800, fontSize: 54, letterSpacing: 3, padding: '10px 34px', borderRadius: 18, border: '5px solid #fff' }}>
          {ev.sub}
        </div>
      ) : null}
    </div>
  );
};

const Label: React.FC<{ x: number; y: number; text: string; p: number }> = ({ x, y, text, p }) => (
  <div
    style={{
      position: 'absolute', left: x, top: y, transform: `translate(-50%,-50%) scale(${p})`, background: '#fff', color: '#0b1e4a',
      fontFamily, fontWeight: 900, fontSize: 38, letterSpacing: 2, padding: '6px 22px', borderRadius: 14,
      boxShadow: '0 6px 0 rgba(0,0,0,0.25)', whiteSpace: 'nowrap', border: '4px solid #0b1e4a',
    }}
  >
    {text}
  </div>
);

// ------------------------------------------------------------------ map layer
const MapLayer: React.FC<{ t: number; scenes: Scene[]; events: Ev[]; opacity: number }> = ({ t, scenes, events, opacity }) => {
  const st = layerState(scenes, t, 'map', mapGen);
  if (!st) return null;
  const { cam, blur } = st;
  const k = VW / ((W * cam.span) / 360);
  const tx = VW / 2 - cam.cx * k;
  const ty = MAP_CY - cam.cy * k;
  const toScreen = (lon: number, lat: number): [number, number] | null => {
    const p = merc([lon, lat]);
    return p ? [VW / 2 + (p[0] - cam.cx) * k, MAP_CY + (p[1] - cam.cy) * k] : null;
  };
  const hls = events.filter((e) => e.t === 'hl' && e.time <= t && t < e.end);
  const ghosts = events.filter((e) => e.t === 'ghost' && e.time <= t && t < e.end);
  const pins = events.filter((e) => e.t === 'pin' && e.time <= t && t < e.end);
  return (
    <AbsoluteFill style={{ opacity }}>
      <svg width={VW} height={VH} style={{ filter: blur > 0.4 ? `blur(${blur.toFixed(1)}px)` : undefined }}>
        <defs>
          <linearGradient id="ocean" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={OCEAN_TOP} />
            <stop offset="1" stopColor={OCEAN_BOTTOM} />
          </linearGradient>
        </defs>
        <rect width={VW} height={VH} fill="url(#ocean)" />
        <g transform={`translate(${tx} ${ty}) scale(${k})`}>
          <path d={gratD} fill="none" stroke="#ffffff" strokeOpacity={0.28} strokeWidth={1.2} vectorEffect="non-scaling-stroke" />
          <path d={landD} fill={LAND} stroke="#a9dff5" strokeWidth={1.6} strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
          {hls.map((e, i) => {
            const p = ease(clamp01((t - e.time) / 0.35));
            return (
              <path key={i} d={mercHighlightD(idsFor(e))} fill={e.color} fillOpacity={0.93 * p} stroke="#fff" strokeOpacity={p} strokeWidth={2.5} strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
            );
          })}
          {ghosts.map((e, i) => {
            const p = ease(clamp01((t - e.time) / e.dur));
            const pop = clamp01((t - e.time) / 0.2);
            return (
              <path key={i} d={ghostPath(e.country, e.from, e.to, p)} fill={e.color} fillOpacity={0.9 * pop} stroke="#fff" strokeWidth={4} strokeOpacity={pop} strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
            );
          })}
        </g>
        {pins.map((e, i) => {
          const s = toScreen(e.lon, e.lat);
          if (!s) return null;
          return <Pin key={i} x={s[0]} y={s[1]} t={t - e.time} />;
        })}
      </svg>
      {hls.filter((e) => e.label).map((e, i) => {
        const c = centroidOf(e);
        const s = toScreen(c[0], c[1]);
        if (!s) return null;
        return <Label key={i} x={s[0]} y={s[1]} text={e.label} p={ease(clamp01((t - e.time - 0.15) / 0.3))} />;
      })}
      {pins.filter((e) => e.label).map((e, i) => {
        const s = toScreen(e.lon, e.lat);
        return s ? <Label key={i} x={s[0]} y={s[1] + 70} text={e.label} p={ease(clamp01((t - e.time - 0.1) / 0.3))} /> : null;
      })}
    </AbsoluteFill>
  );
};

const Pin: React.FC<{ x: number; y: number; t: number }> = ({ x, y, t }) => (
  <g>
    {[0, 0.5, 1].map((o, i) => {
      const ph = (((t - o * 0.8) % 1.6) + 1.6) % 1.6 / 1.6;
      return <circle key={i} cx={x} cy={y} r={14 + ph * 90} fill="none" stroke="#ff2d2d" strokeWidth={6} strokeOpacity={(1 - ph) * 0.9} />;
    })}
    <circle cx={x} cy={y} r={17} fill="#ff2d2d" stroke="#fff" strokeWidth={6} />
  </g>
);

// ------------------------------------------------------------------ globe layer
const STARS = Array.from({ length: 170 }, (_, i) => ({
  x: random(`sx${i}`) * VW, y: random(`sy${i}`) * VH, r: 0.8 + random(`sr${i}`) * 2.2, ph: random(`sp${i}`) * 6.28,
}));

const GlobeLayer: React.FC<{ t: number; scenes: Scene[]; events: Ev[]; opacity: number }> = ({ t, scenes, events, opacity }) => {
  const st = layerState(scenes, t, 'globe', globeGen);
  if (!st) return null;
  const { cam } = st;
  const proj = geoOrthographic().rotate([-cam.lon, -cam.lat]).scale(cam.r).translate([VW / 2, GLOBE_CY]).clipAngle(90).precision(0.4);
  const path = geoPath(proj);
  const sphere = path({ type: 'Sphere' } as any) || '';
  const land = path(landFC) || '';
  const grat = path(geoGraticule10()) || '';
  const hls = events.filter((e) => e.t === 'hl' && e.time <= t && t < e.end);
  const arcs = events.filter((e) => e.t === 'arc' && e.time <= t && t < e.end);
  const pins = events.filter((e) => e.t === 'pin' && e.time <= t && t < e.end);
  const visible = (c: [number, number]) => geoDistance(c, [cam.lon, cam.lat]) < 1.3;
  const scr = (lon: number, lat: number): [number, number] | null => (visible([lon, lat]) ? (proj([lon, lat]) as [number, number]) : null);
  return (
    <AbsoluteFill style={{ opacity, background: 'radial-gradient(circle at 50% 40%, #0d1b3d 0%, #04060f 70%)' }}>
      <svg width={VW} height={VH}>
        <defs>
          <radialGradient id="atmo" cx="50%" cy="50%" r="50%">
            <stop offset="0.93" stopColor="#5cc8ff" stopOpacity="0" />
            <stop offset="0.97" stopColor="#5cc8ff" stopOpacity="0.45" />
            <stop offset="1" stopColor="#5cc8ff" stopOpacity="0" />
          </radialGradient>
          <radialGradient id="sea" cx="38%" cy="30%" r="80%">
            <stop offset="0" stopColor="#58c6f5" />
            <stop offset="1" stopColor="#1d78c9" />
          </radialGradient>
          <radialGradient id="shade" cx="35%" cy="28%" r="85%">
            <stop offset="0.5" stopColor="#000" stopOpacity="0" />
            <stop offset="1" stopColor="#001030" stopOpacity="0.45" />
          </radialGradient>
        </defs>
        {STARS.map((s, i) => (
          <circle key={i} cx={s.x} cy={(s.y + t * 6 * (0.4 + s.r * 0.3)) % VH} r={s.r} fill="#fff" opacity={0.45 + 0.4 * Math.sin(t * 2 + s.ph)} />
        ))}
        <circle cx={VW / 2} cy={GLOBE_CY} r={cam.r * 1.1} fill="url(#atmo)" />
        <path d={sphere} fill="url(#sea)" />
        <path d={grat} fill="none" stroke="#fff" strokeOpacity={0.22} strokeWidth={1.2} />
        <path d={land} fill={LAND} stroke="#9fd3ee" strokeWidth={1} strokeLinejoin="round" />
        {hls.map((e, i) => {
          const p = ease(clamp01((t - e.time) / 0.35));
          const d = path({ type: 'FeatureCollection', features: featsFor(idsFor(e)) } as any) || '';
          return <path key={i} d={d} fill={e.color} fillOpacity={0.94 * p} stroke="#fff" strokeOpacity={p} strokeWidth={2.5} strokeLinejoin="round" />;
        })}
        {arcs.map((e, i) => {
          const p = ease(clamp01((t - e.time) / e.dur));
          const co = arcCoords(e.pts, p);
          const d = path({ type: 'LineString', coordinates: co } as any) || '';
          const head = scr(co[co.length - 1][0], co[co.length - 1][1]);
          return (
            <g key={i}>
              <path d={d} fill="none" stroke={e.color} strokeOpacity={0.35} strokeWidth={22} strokeLinecap="round" strokeLinejoin="round" />
              <path d={d} fill="none" stroke="#fff" strokeWidth={9} strokeLinecap="round" strokeLinejoin="round" />
              <path d={d} fill="none" stroke={e.color} strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" />
              {head ? <circle cx={head[0]} cy={head[1]} r={15} fill={e.color} stroke="#fff" strokeWidth={5} /> : null}
            </g>
          );
        })}
        {pins.map((e, i) => {
          const s = scr(e.lon, e.lat);
          return s ? <Pin key={i} x={s[0]} y={s[1]} t={t - e.time} /> : null;
        })}
        <circle cx={VW / 2} cy={GLOBE_CY} r={cam.r} fill="url(#shade)" />
      </svg>
      {hls.filter((e) => e.label).map((e, i) => {
        const c = centroidOf(e);
        const s = scr(c[0], c[1]);
        return s ? <Label key={i} x={s[0]} y={s[1]} text={e.label} p={ease(clamp01((t - e.time - 0.15) / 0.3))} /> : null;
      })}
      {pins.filter((e) => e.label).map((e, i) => {
        const s = scr(e.lon, e.lat);
        return s ? <Label key={i} x={s[0]} y={s[1] + 70} text={e.label} p={ease(clamp01((t - e.time - 0.1) / 0.3))} /> : null;
      })}
    </AbsoluteFill>
  );
};

// ------------------------------------------------------------------ end card
const EndCard: React.FC<{ t: number }> = ({ t }) => {
  const a = ease(clamp01((t - timing.voiceEnd) / 0.5));
  if (a <= 0) return null;
  return (
    <AbsoluteFill style={{ opacity: a, background: 'rgba(4,8,22,0.92)', alignItems: 'center', justifyContent: 'center', fontFamily, padding: 70 }}>
      <div style={{ color: '#fff', fontWeight: 900, fontSize: 110, letterSpacing: 8 }}>{timing.channel}</div>
      <div style={{ color: '#7fd6f7', fontWeight: 800, fontSize: 38, letterSpacing: 6, marginBottom: 70 }}>MAPS THAT EXPLAIN THE WORLD</div>
      {timing.credits.map(([h, v], i) => {
        const p = ease(clamp01((t - timing.voiceEnd - 0.25 - i * 0.12) / 0.35));
        return (
          <div key={i} style={{ opacity: p, transform: `translateY(${(1 - p) * 24}px)`, width: '100%', marginBottom: 34 }}>
            <div style={{ color: '#ffb347', fontWeight: 900, fontSize: 30, letterSpacing: 5 }}>{h}</div>
            <div style={{ color: '#fff', fontWeight: 700, fontSize: 38, lineHeight: 1.25 }}>{v}</div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

// ------------------------------------------------------------------ main
export const Video: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const scenes = timing.scenes;
  const events = useMemo(() => scenes.flatMap((s) => s.events), [scenes]);
  const chunks = useMemo(() => buildChunks(scenes), [scenes]);
  const i = sceneIndexAt(scenes, t);

  let sx = 0;
  let sy = 0;
  events.filter((e) => e.t === 'shake').forEach((e) => {
    const x = t - e.time;
    if (x >= 0 && x < 0.5) {
      const amp = 20 * Math.pow(1 - x / 0.5, 2);
      sx += amp * Math.sin(x * 70);
      sy += amp * Math.cos(x * 83);
    }
  });
  let flash = 0;
  events.filter((e) => e.t === 'flash').forEach((e) => {
    const x = t - e.time;
    if (x >= 0 && x < 0.28) flash = Math.max(flash, 0.7 * (1 - x / 0.28));
  });

  const active = (type: string) => events.filter((e) => e.t === type && e.time <= t && t < e.end);

  return (
    <AbsoluteFill style={{ background: '#000', fontFamily }}>
      <AbsoluteFill style={{ transform: `translate(${sx}px, ${sy}px) scale(1.02)` }}>
        <MapLayer t={t} scenes={scenes} events={events} opacity={layerOpacity(scenes, t, 'map')} />
        <GlobeLayer t={t} scenes={scenes} events={events} opacity={layerOpacity(scenes, t, 'globe')} />
        {active('sticker').map((e, k) => (
          <Sticker key={`s${k}-${e.time}`} ev={e} t={t} />
        ))}
        {active('stat').map((e, k) => (
          <Stat key={`t${k}-${e.time}`} ev={e} t={t} />
        ))}
      </AbsoluteFill>
      <AbsoluteFill style={{ background: 'radial-gradient(ellipse at center, rgba(0,0,0,0) 55%, rgba(0,0,0,0.38) 100%)' }} />
      <Caption t={t} chunks={chunks} />
      {t <= timing.voiceEnd ? (
        <div style={{ position: 'absolute', left: 0, right: 0, top: 1512, textAlign: 'center', fontFamily, fontWeight: 800, fontSize: 30, letterSpacing: 9, color: 'rgba(255,255,255,0.8)', textShadow: '0 3px 6px rgba(0,0,0,0.7)' }}>
          {timing.channel}
        </div>
      ) : null}
      <div style={{ position: 'absolute', left: 0, top: 0, height: 9, width: `${(t / timing.total) * 100}%`, background: '#ffe14d' }} />
      <AbsoluteFill style={{ background: '#fff', opacity: flash }} />
      <EndCard t={t} />
      <div style={{ display: 'none' }}>{i}</div>
    </AbsoluteFill>
  );
};
