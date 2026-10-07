// Runs code-review/swarm.js with canned agents (no model): node swarm-mock.mjs <swarm.js> <args.json> → result JSON on stdout.
import fs from 'node:fs'
const [swarmPath, argsPath] = process.argv.slice(2)
const args = JSON.parse(fs.readFileSync(argsPath, 'utf8'))
const H = args.home
const calls = []
let live = {}, maxLive = {}
const F = {
  race: { file: `${H}/agents/bin/orbit-lite`, line: 14, symbol: 'label_for', kind: 'race', title: 'label read before meta lands', evidence: 'log/orbit-lite.log: 29/40 fallback', fix: 'poll 0.5 s', severity: 'high' },
  unused: { file: `${H}/agents/bin/old-sweeper`, line: 1, symbol: 'file', kind: 'not-useful', retire_reason: 'obsolete', title: 'old-sweeper unused', evidence: 'replaced by maintenance; ~/agents/tmp gone', fix: 'retire', severity: 'low' },
  sweeperbug: { file: `${H}/agents/bin/old-sweeper`, line: 4, symbol: 'find', kind: 'bug', title: 'old-sweeper hides errors', evidence: '|| true', fix: 'drop it', severity: 'medium' },
  valuable: { file: `${H}/agents/bin/restore-config`, line: 1, symbol: 'file', kind: 'not-useful', retire_reason: 'obsolete', title: 'restore-config never used', evidence: '0 uses', fix: 'retire', severity: 'low' },
  reworded: { file: `${H}/agents/bin/log-size`, line: 21, symbol: 'main loop', kind: 'bug', title: 'old refuted claim, new words', evidence: 'x', fix: 'y', severity: 'low' },
  dup: { file: `${H}/agents/bin/log-size`, line: 8, symbol: 'human_size', kind: 'duplicate', title: 'human_size copied', evidence: 'disk-report:8', fix: 'share', severity: 'medium' },
  bogus: { file: `${H}/agents/bin/disk-report`, line: 20, symbol: 'main', kind: 'perf', title: 'walk is slow', evidence: 'guess', fix: 'cache', severity: 'low' },
  seen: { file: `${H}/agents/bin/log-size`, line: 20, symbol: 'main', kind: 'bug', title: 'old refuted claim', evidence: 'x', fix: 'y', severity: 'low' },
  doc: { file: `${H}/agents/KB/guides/disk-report.md`, line: 12, symbol: 'Exact commands', kind: 'stale-doc', title: '--json documented', evidence: 'usage: disk-report <dir>', fix: 'fix guide', severity: 'medium' },
  race2: { file: `${H}/agents/KB/guides/orbit-lite.md`, line: 9, symbol: 'The path we took', kind: 'stale-doc', title: 'guide label claim wrong', evidence: 'log', fix: 'guide', severity: 'low' },
  ro: { file: `${H}/moodle-harness/skills/x/SKILL.md`, line: 1, symbol: 'file', kind: 'bug', title: 'harness skill typo', evidence: 'line 1', fix: 'typo', severity: 'low' },
}
const agent = async (prompt, opts) => {
  const l = opts.label; calls.push(l)
  const area = l.split(':')[1]
  if (l.startsWith('review:')) {
    const lens = l.split(':')[2]
    const map = { 'bin:data': [F.race, F.seen, F.reworded], 'bin:correctness': [F.race, F.sweeperbug], 'bin:value': [F.unused, F.dup, F.valuable], 'bin:perf': [F.bogus], 'guides:correctness': [F.doc], 'guides:data': [F.race2], 'skills:correctness': [F.ro] }
    return { findings: map[`${area}:${lens}`] || [] }
  }
  if (l === 'merge') {
    const list = JSON.parse(prompt.slice(prompt.indexOf('Findings: ') + 10).split('\n')[0])
    const id = t => list.find(f => f.title === t).id
    return { groups: [{ keep: id(F.race.title), merge: [id(F.race2.title)] }],
      seen_before: prompt.includes('already decided findings') ? list.filter(f => f.title === F.reworded.title).map(f => f.id) : [] }
  }
  if (l.startsWith('verify:')) return { refuted: prompt.includes('walk is slow') || (prompt.includes('restore-config') && l.endsWith(':intent') && prompt.includes('what would a future agent lose')), reason: 'mock' }
  const k = prompt.includes(`${H}/agents/bin/`) ? 'bin' : 'other'
  live[k] = (live[k] || 0) + 1; maxLive[k] = Math.max(maxLive[k] || 0, live[k])
  await new Promise(r => setTimeout(r, 20)); live[k]--
  if (l.startsWith('retire:')) return { status: 'retired', restore: 'mv a b', note: 'ok' }
  return { status: 'fixed', files: [], test: 't', restore: 'code-review restore', note: 'ok' }
}
const parallel = thunks => Promise.all(thunks.map(t => t().catch(() => null)))
const src = fs.readFileSync(swarmPath, 'utf8').replace(/^export const meta/m, 'const meta')
const run = new Function('args', 'agent', 'parallel', 'phase', 'log', `return (async () => {${src}})()`)
const res = await run(args, agent, parallel, () => {}, m => process.stderr.write(`log: ${m}\n`))
console.log(JSON.stringify({ res, calls, maxBinLive: maxLive.bin || 0 }))
