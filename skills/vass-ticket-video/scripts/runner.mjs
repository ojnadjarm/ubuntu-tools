// runner.mjs — the step loop: actions, a step's ws call at its place in the order, narration mark, cue, still, hold.
// d: { act(a), fetchWs(jobs) -> data, showWs(step, data), wait(ms), now() s, apply(step), still(i, step), clip(id) }
export async function runSteps(steps, d) {
  const marks = {};
  for (const [i, step] of steps.entries()) {
    const id = `s${i + 1}`;
    d.stepNo = i + 1;
    for (const a of step.pre || []) await d.act(a);
    // Fetched now, not before recording: earlier UI steps may have changed the data it shows.
    if (step.ws) await d.showWs(step, await d.fetchWs(step.ws));
    await d.act({ ...step, site: step.site || 'front' });
    await d.wait(step.settle ?? 1200);
    marks[id] = d.now();
    const clip = d.clip(id); const cueAt = clip.marks?.hl;
    if (cueAt != null) await d.wait((marks[id] + cueAt - d.now()) * 1000);
    await d.apply(step);
    const end = marks[id] + clip.duration + (step.hold ?? 0.6);
    if (step.still) { await d.wait((end - 0.4 - d.now()) * 1000); await d.still(i + 1, step); }
    await d.wait((end - d.now()) * 1000);
  }
  marks.end = d.now();
  return marks;
}
