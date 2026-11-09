/* Agent avatars for lists and cards: the Familiar of agent `id` as an SVG, the same creature the stage draws in 3D. */
import { genome } from "./familiars/genome.js";
import { svg } from "./familiars/svg.js";

/* SVG string for agent `id` in state working|idle|talking|error|sleep (done and stale rest), wearing the gear of role ceo|po|worker|crew. */
export const creature = (id, state = "working", role = "worker") => svg(genome(id, role), state);
