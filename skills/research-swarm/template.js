// Research swarm → judge → critic. Copied from T70 (wf_dce39017-bb9); fill TICKET, BRIEF, OUT and LANES (each lane's `guide` words too).
export const meta = {
  name: 'TNN-topic',
  description: 'Parallel lanes (research, spikes or mockups), then a judge, then a critic',
  phases: [
    { title: 'Lanes', detail: 'one fresh worker per lane, each writes its own file' },
    { title: 'Judge', detail: 'score, recommend, publish' },
    { title: 'Critic', detail: 'gaps and bias, re-check links and builds' },
  ],
}

const BRIEF = '~/agent-work/briefs/TNN-topic.md'
const OUT = '~/agent-work/research/YYYY-MM-DD/TNN'
const guide = words => `First run \`guide ${words}\` and use the top hit (load any \`→ invoke /<name>\` skill it prints).`
const head = `Read ${BRIEF} first; it is binding. Output root: ${OUT}. Write findings.md, never report.md. Architecture note first; start from something (template, example, earlier fleet work). Use wait-for for every wait.`

const LANES = [
  { key: 'a', guide: 'lane a topic words', task: `LANE A: … Write ${OUT}/a/findings.md.` },
  { key: 'b', guide: 'lane b topic words', task: `LANE B: … Write ${OUT}/b/findings.md.` },
]
const LANE_OUT = { type: 'object', properties: { file: { type: 'string' }, headline: { type: 'string' }, test_link: { type: 'string' } }, required: ['file', 'headline'] }

phase('Lanes')
const found = (await parallel(LANES.map(l => () =>
  agent(`${guide(l.guide)}\n${head}\n\n${l.task}\n\nReturn the file, a 3-line headline and any https test link (drop-link).`, { label: `lane:${l.key}`, phase: 'Lanes', agentType: 'worker', schema: LANE_OUT })
))).filter(Boolean)
log(`${found.length}/${LANES.length} lanes done`)

phase('Judge')
const J_OUT = { type: 'object', properties: { file: { type: 'string' }, recommendation: { type: 'string' } }, required: ['file', 'recommendation'] }
const judge = await agent(`${guide('research swarm judge')}\n${head}\n\nJUDGE. Reports: ${JSON.stringify(found)}. Open every test link and play it yourself. Score the options on the brief's criteria, measured values only, and mark estimates. Write ${OUT}/options.md (phone-readable) with the recommendation and what is missing.`, { label: 'judge', phase: 'Judge', agentType: 'worker', schema: J_OUT })

phase('Critic')
const C_OUT = { type: 'object', properties: { gaps: { type: 'array', items: { type: 'string' } }, bias_flags: { type: 'array', items: { type: 'string' } }, verdict_holds: { type: 'boolean' } }, required: ['gaps', 'bias_flags', 'verdict_holds'] }
const critic = await agent(`${guide('research swarm judge')}\n${head}\n\nCRITIC. The judge concluded: ${JSON.stringify(judge)}. Try to refute it with your own measurements and scripts: re-run one number per lane, load every link over https, check every build starts. Flag bias (what was easiest to spike, laptop numbers standing in for the owner's PC, numbers taken under contention). Append a "Critic" section to ${OUT}/options.md.`, { label: 'critic', phase: 'Critic', agentType: 'worker', schema: C_OUT })

return { found, judge, critic }
