export type Word = { w: string; emph: boolean; start: number; end: number };
export type ViewState = { lon: number; lat: number; span?: number; r?: number };
export type View = ViewState & { from?: ViewState };
export type Ev = { t: string; time: number; end: number; [k: string]: any };
export type Scene = {
  id: string;
  text: string;
  mode: 'map' | 'globe';
  view: View;
  keep: boolean;
  start: number;
  end: number;
  words: Word[];
  events: Ev[];
  sfx: { time: number; s: string; v: number }[];
};
export type Timing = {
  fps: number;
  total: number;
  voiceEnd: number;
  channel: string;
  credits: [string, string][];
  scenes: Scene[];
};
