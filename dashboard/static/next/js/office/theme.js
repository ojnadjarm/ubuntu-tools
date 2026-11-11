/* The look of the loft (A2, warm neon) as data: palette, materials, lights and state colours; the builders read nothing else. */
export const GREEN = [0.3, 1, 0.63], AMBER = [1, 0.82, 0.4], VIOLET = [0.78, 0.36, 1], RED = [1, 0.32, 0.3], ICE = [0.55, 0.95, 1];
const STATE = { working: GREEN, talking: ICE, idle: AMBER, error: RED, sleep: null };

export const THEME = {
  id: "A2", name: "Warm neon", line: "amber lamps and wood kept under the neon",
  pal: { wood: [0.62, 0.42, 0.26], woodDark: [0.4, 0.26, 0.17], metal: [0.56, 0.5, 0.43], metalDark: [0.14, 0.13, 0.13], metalMedium: [0.34, 0.3, 0.27], metalLight: [0.74, 0.69, 0.6],
    carpet: [0.5, 0.22, 0.16], carpetBlue: [0.16, 0.32, 0.34], carpetDarker: [0.32, 0.15, 0.13], carpetWhite: [0.72, 0.66, 0.56], plant: [0.26, 0.66, 0.36], lamp: [1, 0.88, 0.64], glass: [0.4, 0.55, 0.48], fur: [0.56, 0.4, 0.27], _defaultMat: [0.6, 0.56, 0.5] },
  tints: [[0.5, 0.24, 0.16], [0.14, 0.34, 0.32], [0.5, 0.36, 0.16], [0.36, 0.2, 0.32], [0.26, 0.38, 0.24], [0.2, 0.25, 0.4]],
  env: { day: { sky: [0.56, 0.5, 0.44], ground: [0.36, 0.3, 0.26], sun: [0.16, 0.13, 0.08], dir: [0.5, 0.74, 0.45] }, night: { sky: [0.2, 0.2, 0.27], ground: [0.1, 0.1, 0.14], sun: [0.04, 0.04, 0.06], dir: [0.5, 0.74, 0.45] } },
  floor: { col: [0.5, 0.33, 0.21], cu: 0.22, cv: 1.6, stagger: true, sub: 6, k: 0.1 },
  wall: { col: [0.4, 0.22, 0.17], cell: 0.13, stagger: true, k: 0.12 },
  deck: [0.44, 0.3, 0.2], frame: [0.13, 0.1, 0.09], seat: [0.3, 0.22, 0.17],
  state: STATE, accent: GREEN, second: AMBER, grow: VIOLET, rest: VIOLET, city: [0.6, 0.36, 0.14], cityLit: AMBER,
  warm: true, minLight: 0.56, trace: 0.6,
};
