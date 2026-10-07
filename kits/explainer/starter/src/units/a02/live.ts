import type { Live } from 'explainer-kit';
import type { A02State } from './state';
import { output } from '../../sim/bias';
import { num, op } from '../../sim/format';

/** The numbers each callout shows right now (a newline starts a row), all through the plate's number rules. */
export const LIVE: Live<A02State> = {
  now(term, s) {
    switch (term) {
      case 'input': return `input ${num(s.x)}`;
      case 'weight': return `input × weight\n${op(s.x)} × ${op(s.w)} = ${num(s.x * s.w)}`;
      case 'bias': return `source × bias\n${op(s.src)} × ${op(s.b)} = ${num(s.src * s.b)}`;
      case 'output': return `${op(s.x)} × ${op(s.w)} + ${op(s.b)} = ${num(output(s.w, s.x, s.b, s.src))}`;
      default: return null;
    }
  },
};
