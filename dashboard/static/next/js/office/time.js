/* Durations for the office: how long ago, how long until, how far from the last run to the next, how long a run took. */
const ms = (t) => (typeof t === "number" || /^\d+$/.test(t) ? t * 1000 : Date.parse(t));

/* Time since t (epoch seconds or ISO) as "N min", "N.N h" or "N d"; "—" when t is unreadable. */
export const ago = (t, now = Date.now()) => {
  const m = ms(t) ? Math.max(0, (now - ms(t)) / 60000) : NaN;
  return isNaN(m) ? "—" : m < 60 ? Math.round(m) + " min" : m < 2880 ? (m / 60).toFixed(1) + " h" : Math.round(m / 1440) + " d";
};

/* Time left until t as "N min", "N h" or "N d"; "—" when t is unreadable. */
export const until = (t, now = Date.now()) => {
  const h = (ms(t) - now) / 3600000;
  return isNaN(h) ? "—" : h < 1 ? Math.max(0, Math.round(h * 60)) + " min" : h < 48 ? h.toFixed(0) + " h" : (h / 24).toFixed(0) + " d";
};

/* How far now is from the last run's end to the next run, 0..100. */
export const progress = (last, next, now = Date.now()) => {
  const a = ms(last), b = ms(next);
  return a && b && b > a ? Math.max(0, Math.min(100, (100 * (now - a)) / (b - a))) : 0;
};

/* A run's length in seconds as "N s"; "—" when unknown. */
export const took = (s) => (s == null || s === "" ? "—" : s + " s");
