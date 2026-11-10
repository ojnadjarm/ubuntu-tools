/* A list Familiar that moves: the SVG twin in its state pose inside a .fam box that familiars.css animates; a talking seat acts "talking". */
import { esc } from "/static/js/core/fmt.js";
import { creature } from "../avatar.js";
import { hash } from "./genome.js";
import { talking } from "./talk.js";

if (!document.querySelector('link[href="/static/css/familiars.css"]')) {
  const l = document.createElement("link");
  l.rel = "stylesheet"; l.href = "/static/css/familiars.css";
  document.head.appendChild(l);
}
const away = () => document.documentElement.classList.toggle("away", document.hidden);
document.addEventListener("visibilitychange", away);
away();

/* The pose of a seat or session state: working and idle act, every other state sleeps. */
export const poseOf = (st) => (st === "working" || st === "idle" ? st : "sleep");

/* Markup of agent `id` in `state`, wearing `role` gear; with a message id it talks only while that message is the new one. */
export function familiar(id, state, role, mid) {
  const pose = talking(id, mid) ? "talking" : poseOf(state);
  return `<span class="fam ph${hash(id) % 4} ${pose}" data-fam="${esc(id)}">${creature(id, pose, role)}</span>`;
}
