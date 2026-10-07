/* The eye boundary: the one import that picks the eye variant /next draws. A variant exports { name, fs, create(ctx, U) → { draw(S, box), probe(S) } } over the shared eye uniforms. */
export { default as EYE } from "./eyes/swarm.js";
export * from "./cam.js";
