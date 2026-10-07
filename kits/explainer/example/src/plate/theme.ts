/** The plate's look: every colour and ink weight lives here; editing it repaints live through Vite HMR. */
export const THEME = {
  paper: '#f2ecdf',
  paperShade: '#e7dfcc',
  glass: '#f8f4ea',
  ink: '#1c2230',
  inkSoft: '#6b6a66',
  hatch: '#8f887a',
  signal: '#1d5fb0',
  weight: '#cc3a2b',
  target: '#e9ae2c',
  targetInk: '#a8740c',
  vignette: '#3a2f1c',
  /** Line weights in drawing units: hairline, thin, medium, bold. */
  hair: 0.7,
  thin: 1.25,
  med: 2.1,
  bold: 3.2,
};
export type Theme = typeof THEME;
export type ColorRole = { [K in keyof Theme]: Theme[K] extends string ? K : never }[keyof Theme];
