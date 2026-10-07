/** The cutaway look in one place: paper, ink, hatch, Byrne primaries and ink weights; editing it repaints live through Vite HMR. */
export const THEME = {
  paper: '#f2ecdf',
  paperShade: '#e7dfcc',
  glass: '#f8f4ea',
  ink: '#1c2230',
  inkSoft: '#6b6a66',
  hatch: '#8f887a',
  /** Byrne primaries: one per live concept, never decoration. */
  blue: '#1d5fb0',
  red: '#cc3a2b',
  yellow: '#e9ae2c',
  /** Yellow is too light for text and thin lines on paper: labels of the yellow concept use this. */
  yellowInk: '#a8740c',
  vignette: '#3a2f1c',
  /** Line weights in drawing units: hairline (hatching, ticks), thin (callouts, detail), medium (walls), bold (the casing). */
  hair: 0.7,
  thin: 1.25,
  med: 2.1,
  bold: 3.2,
};
export type Theme = typeof THEME;
export type ColorRole = { [K in keyof Theme]: Theme[K] extends string ? K : never }[keyof Theme];

/** Hatch pitch in drawing units: bands and flanges are dense, large cut shells are open. */
export const HATCH = { dense: 3.4, band: 3.2, shell: 6.5 };

/** Type sizes in drawing units, measured on the neuron plate framed at 1920. */
export const TYPE = { term: 26, dimension: 34, title: 36, scale: 14, caption: 19, balloon: 17, zone: 11 };

/** Font families registered by `loadFonts` (all SIL OFL 1.1, files in the kit's `fonts/`). */
export const FONT = { label: '"Plex Cond"', mono: '"Plex Mono"', serif: '"Caslon"' };

const FILES: [string, string, string, string][] = [
  ['Plex Cond', '400', 'normal', 'ibm-plex-sans-condensed-latin-400-normal'], ['Plex Cond', '500', 'normal', 'ibm-plex-sans-condensed-latin-500-normal'],
  ['Plex Cond', '600', 'normal', 'ibm-plex-sans-condensed-latin-600-normal'], ['Plex Mono', '400', 'normal', 'ibm-plex-mono-latin-400-normal'],
  ['Plex Mono', '500', 'normal', 'ibm-plex-mono-latin-500-normal'],
  ['Caslon', '400', 'normal', 'libre-caslon-text-latin-400-normal'], ['Caslon', '400', 'italic', 'libre-caslon-text-latin-400-italic'],
];

/** Load the plate's faces before any text plate is drawn (canvas text never waits for fonts). */
export function loadFonts(base = 'fonts/'): Promise<void[]> {
  return Promise.all(FILES.map(async ([f, w, st, u]) => {
    const ff = new FontFace(f, `url(${base}${u}.woff2)`, { weight: w, style: st });
    await ff.load();
    document.fonts.add(ff);
  }));
}
