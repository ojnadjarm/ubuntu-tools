/* Agent avatars for lists and cards: the Familiar of agent `id` as an SVG, the same creature the stage draws in 3D; the ceo is the Conductor. */
import { genome } from "./familiars/genome.js";
import { svg } from "./familiars/svg.js";
import { ceoSvg } from "./familiars/ceo-svg.js";

/* SVG string for agent `id` in state working|idle|talking|error|sleep (done and stale rest), wearing the gear of role po|worker|crew; role ceo draws the Conductor with opts { motes, lamp }. */
export const creature = (id, state = "working", role = "worker", opts) => (role === "ceo" ? ceoSvg(state, opts) : svg(genome(id, role), state));
