// Weekly code-review swarm (T74), started from research-swarm/template.js. Args: state/runs/<date>/args.json (code-review prep).
export const meta = {
  name: 'code-review-weekly',
  description: 'Fleet code review: area x lens lanes, 3 refuters per finding, then fix, retire or queue lanes',
  phases: [
    { title: 'Review', detail: 'one read-only lane per area x lens' },
    { title: 'Merge', detail: 'one agent groups findings that share a root cause' },
    { title: 'Verify', detail: '3 independent refuters per fresh finding; survives when 2 cannot refute' },
    { title: 'Act', detail: 'per area, one fresh agent per confirmed finding: retire first, then fix or queue' },
  ],
}

const A = args
const head = `Read ${A.rules} first; it is binding. Mode: ${A.mode}. Home: ${A.home}. Run dir: ${A.run_dir}. Date: ${A.date}. ` +
  `CLI: \`${A.cli}\` (CR_HOME is already exported for fixture runs; never change it).`

const KINDS = ['bug', 'race', 'perf', 'not-useful', 'duplicate', 'stale-doc', 'replace', 'discoverability']
const WHY = ['broken', 'duplicate', 'superseded', 'obsolete']
const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' }, line: { type: 'integer' }, symbol: { type: 'string' },
          kind: { type: 'string', enum: KINDS }, title: { type: 'string' }, evidence: { type: 'string' },
          fix: { type: 'string' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          retire_reason: { type: 'string', enum: WHY }, replacement: { type: 'string' },
        },
        required: ['file', 'symbol', 'kind', 'title', 'evidence', 'fix', 'severity'],
      },
    },
    more: { type: 'integer' },
  },
  required: ['findings'],
}
const VERDICT = { type: 'object', properties: { refuted: { type: 'boolean' }, reason: { type: 'string' } }, required: ['refuted', 'reason'] }
const ACT = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['fixed', 'already-fixed', 'retired', 'reverted', 'kept', 'staged', 'queued', 'skipped', 'deferred', 'failed'] },
    files: { type: 'array', items: { type: 'string' } }, test: { type: 'string' }, restore: { type: 'string' },
    guide: { type: 'string' }, queue: { type: 'string' }, note: { type: 'string' },
  },
  required: ['status', 'note'],
}

const norm = s => String(s || '').replace(/^~\//, A.home + '/').replace(/\s+/g, ' ').trim()
const keyOf = f => `${norm(f.file)}|${f.kind}|${norm(f.symbol) || 'file'}`.toLowerCase()
const policyOf = file => {
  const p = norm(file).startsWith('/') ? norm(file) : `${A.home}/${norm(file)}`
  let best = ['', 'review-only']
  for (const [prefix, pol] of A.policy) if ((p === prefix || p.startsWith(prefix + '/')) && prefix.length > best[0].length) best = [prefix, pol]
  return best[1]
}
const areaOf = file => {
  const p = norm(file)
  const hit = A.areas.find(a => a.paths.some(x => p === x || p.startsWith(x + '/')))
  return hit ? hit.key : 'other'
}
const isWhole = f => ['file', '', '*'].includes(norm(f.symbol).toLowerCase()) || norm(f.symbol) === norm(f.file).split('/').pop()
// Findings that end in removing an item: they go through a retire lane and need all 3 refuters to stand.
const removes = f => f.kind === 'not-useful' || (['duplicate', 'replace'].includes(f.kind) && isWhole(f))
const under = (file, item) => norm(file) === norm(item) || norm(file).startsWith(norm(item) + '/')

// ---- Review ------------------------------------------------------------------------------------------
phase('Review')
const lanes = A.areas.flatMap(a => A.lenses.map(l => ({ area: a, lens: l })))
const open = A.open_items.length ? `Already open elsewhere (skip these): ${JSON.stringify(A.open_items)}.` : ''
const reviewed = await parallel(lanes.map(({ area, lens }) => () =>
  agent(`${head}\n\nREVIEW LANE — area "${area.key}": ${area.paths.join(', ')}. Lens: ${lens.ask}\n` +
    `Audit log: ${JSON.stringify(A.audit)}. Area tests: ${JSON.stringify(area.tests)}. ${open}\n` +
    `Read the code in this area through this lens only; stay read-only. Report real defects you can point at ` +
    `(path:line plus evidence), most severe first, at most 8; put the count of any others in "more". ` +
    `symbol = the function, section or command name involved (a code identifier), or "file" when the finding is about ` +
    `the whole file or tool. A finding that would remove an item (kind not-useful, or a whole-file duplicate or replace) ` +
    `must set retire_reason and argue it in evidence; low or zero use alone is never such a reason. ` +
    `Use absolute paths under ${A.home}. Zero findings is a valid answer.`,
    { label: `review:${area.key}:${lens.key}`, phase: 'Review', agentType: 'worker', schema: FINDINGS })
    .then(r => r && r.findings.map(f => ({ ...f, lens: lens.key, lane: `${area.key}:${lens.key}` })))))
const raw = reviewed.filter(Boolean).flat()
log(`${reviewed.filter(Boolean).length}/${lanes.length} lanes returned · ${raw.length} raw findings`)

// Dedup across lanes (a barrier: needs every lane) and against earlier weeks.
const skip = new Set(A.seen.filter(s => A.skip_verdicts.includes(s.verdict)).map(s => s.key))
const byKey = new Map()
for (const f of raw) {
  const k = keyOf(f)
  if (!byKey.has(k)) byKey.set(k, { ...f, key: k, lenses: [f.lens] })
  else byKey.get(k).lenses.push(f.lens)
}
const unique = [...byKey.values()]
const claimed = f => A.claimed.some(c => norm(f.file) === c || norm(f.file).startsWith(c + '/'))
const fresh = unique.filter(f => !skip.has(f.key) && !claimed(f)).map((f, i) => ({ ...f, id: `F${String(i + 1).padStart(2, '0')}` }))
log(`${unique.length} unique · ${unique.filter(f => skip.has(f.key)).length} seen before (skipped) · ` +
  `${unique.filter(f => !skip.has(f.key) && claimed(f)).length} on claimed files (skipped) · ${fresh.length} to verify`)

// ---- Merge: lanes word the same defect differently; one agent groups them so each is verified and fixed once.
phase('Merge')
const MERGE = {
  type: 'object',
  properties: {
    groups: { type: 'array', items: { type: 'object', properties: { keep: { type: 'string' }, merge: { type: 'array', items: { type: 'string' } } }, required: ['keep', 'merge'] } },
    seen_before: { type: 'array', items: { type: 'string' } },
  },
  required: ['groups'],
}
const mergedInto = new Map()
const seenBefore = new Set()
const decided = A.seen.filter(s => A.skip_verdicts.includes(s.verdict) && s.title &&
  fresh.some(f => norm(f.file) === norm(s.file)))
if (fresh.length > 1 || decided.length) {
  const m = await agent(`${head}\n\nMERGE. These findings come from independent lanes. Group the ones that describe the same defect or ` +
    `that one change would fix (same root cause; a code file and its guide count as one when the guide only mirrors the code bug). ` +
    `keep = the id with the strongest evidence, merge = the other ids. Leave findings without a twin out. Do not judge validity; ` +
    `read files only if two titles are ambiguous. Findings: ` +
    JSON.stringify(fresh.map(f => ({ id: f.id, file: f.file, kind: f.kind, symbol: f.symbol, title: f.title }))) +
    (decided.length ? `\nAlso put in seen_before the ids of findings that repeat one of these earlier, already decided findings ` +
      `(same file and same defect, whatever the wording): ${JSON.stringify(decided.map(s => ({ file: s.file, title: s.title, verdict: s.verdict })))}` : ''),
    { label: 'merge', phase: 'Merge', agentType: 'worker', schema: MERGE })
  const ids = new Set(fresh.map(f => f.id))
  for (const id of (m && m.seen_before) || []) if (ids.has(id)) seenBefore.add(id)
  for (const g of (m && m.groups) || []) {
    if (!ids.has(g.keep) || mergedInto.has(g.keep)) continue
    for (const id of g.merge) if (id !== g.keep && ids.has(id) && !mergedInto.has(id) && ![...mergedInto.values()].includes(id)) mergedInto.set(id, g.keep)
  }
}
const twins = id => fresh.filter(f => mergedInto.get(f.id) === id).map(f => `${f.id}: ${f.title} (${f.file})`)
const distinct = fresh.filter(f => !mergedInto.has(f.id) && !seenBefore.has(f.id)).map(f => (twins(f.id).length ? { ...f, also: twins(f.id) } : f))
log(`${fresh.length} fresh → ${distinct.length} distinct after merge (${mergedInto.size} merged, ${seenBefore.size} decided in earlier weeks)`)

// ---- Verify --------------------------------------------------------------------------------------------
phase('Verify')
const REFUTERS = [
  ['reproduce', 'Try to make it happen: a reproduction in a scratch copy (mktemp -d, copy only what you need, fixtures only). ' +
    'If you cannot reproduce it, refuted=true.',
  'Run the item and its named replacement side by side on the same inputs (its tests, its documented calls) in a scratch copy. ' +
    'If the replacement is missing, gives different output, fails a case or is worse, refuted=true.'],
  ['intent', 'Read the code at the cited line, its tests, its guide in KB/guides and any brief that mentions it. Is the line ' +
    'real, is the behaviour intended or documented, is it already handled elsewhere or already queued? Any yes = refuted=true.',
  'Ask: what would a future agent lose without this item? Read its header, guide, briefs, runbooks and KB. If it does a job ' +
    'nothing else does as well (a recovery or restore path, a rare but real task), it is useful: refuted=true. Low use is never evidence.'],
  ['evidence', 'Re-check every number and log line the finding cites against the real files yourself, and judge whether the ' +
    'fix is worth it (a real caller or user is affected). Wrong, missing or unmeasured evidence = refuted=true.',
  'Find every caller yourself: `code-review refs <path>`, systemd units and timers (~/.config/systemd/user, agents/units), cron, ' +
    'hooks, other tools, briefs, guides. Any live caller not migrated, or a retire_reason the evidence does not prove = refuted=true.'],
]
const verified = await parallel(distinct.map(f => () =>
  parallel(REFUTERS.map(([lens, how, removal]) => () =>
    agent(`${head}\n\nREFUTER (${lens}) for finding ${f.id}: ${JSON.stringify(f)}\nYour job is to REFUTE it. ` +
      `${removes(f) ? `This finding would REMOVE an item (retire_reason ${f.retire_reason || 'none given, which alone refutes it'}). ${removal}` : how} ` +
      `Stay read-only on the tree. Default to refuted=true when uncertain. reason: one or two sentences with the fact that decided it.`,
      { label: `verify:${f.id}:${lens}`, phase: 'Verify', agentType: 'worker', schema: VERDICT })))
    .then(vs => {
      const standing = vs.filter(v => v && !v.refuted).length
      const need = removes(f) ? 3 : 2
      return { ...f, votes: `${standing}/3`, verdict: standing >= need ? 'confirmed' : 'refuted',
        reasons: vs.map((v, i) => `${REFUTERS[i][0]}: ${v ? (v.refuted ? 'refuted' : 'stands') + ' — ' + v.reason : 'no answer'}`) }
    })))
const judged = verified.filter(Boolean)
const confirmed = judged.filter(f => f.verdict === 'confirmed')
log(`${confirmed.length}/${judged.length} findings survived the refuters`)

// ---- Act -------------------------------------------------------------------------------------------------
phase('Act')
const route = f => {
  const pol = policyOf(f.file)
  if (removes(f) && f.kind !== 'replace') return ['edit', 'retire-only'].includes(pol) ? 'retire' : `left:${pol}`
  return pol === 'edit' ? 'fix' : `left:${pol}`
}
const T = id => `\`code-review tests ${id} before\` / \`code-review tests ${id} after\``
const fixPrompt = (f, area) => `${head}\n\nFIX LANE for finding ${f.id} (confirmed ${f.votes}): ${JSON.stringify(f)}\n` +
  `Area "${area ? area.key : 'other'}" tests (the CLI runs them for you): ${JSON.stringify(area ? area.tests : [])}.\n` +
  `Steps, in order:\n` +
  `1. List every path you will touch or create; \`code-review policy <paths>\` must print edit for all, else status skipped.\n` +
  `2. If the change needs a package install, a new or changed systemd unit, a settings.json edit or a reboot, do not apply it: ` +
  `\`code-review queue-new "<title>" --cls owner-go\` (owner-reboot for reboot), fill every section with the evidence, a numeric ` +
  `before/target and a rollback line, run \`improve-gate check <file>\` until it prints ok; status queued (staged for reboot), queue = the file.\n` +
  `   For kind replace: migrate only if the replacement is already on this machine, every caller is policy edit, and a side-by-side ` +
  `run on the same inputs shows it does the job at least as well (save that run to ${A.run_dir}/${f.id}-proof.txt). Then ` +
  `\`code-review retire <old path> --id ${f.id} --why superseded --by <replacement> --proof ${A.run_dir}/${f.id}-proof.txt\`. Otherwise queue it.\n` +
  `3. \`code-review claim ${f.id} <paths>\` (rc 3 = status skipped).\n` +
  `4. \`code-review backup ${f.id} <paths, including files you will create and guides you will correct>\`.\n` +
  `5. \`code-review tests ${f.id} before\` (the baseline; it runs the area tests one lane at a time).\n` +
  `6. Write the failing test or reproduction first (in the area's tests dir when it has one) and show it fails.\n` +
  `7. Make the minimal fix; your test passes. Never delete, move or empty a file or skill here: removal is only done by ` +
  `\`code-review retire\`, and the verify step refuses deletions.\n` +
  `8. Correct every claim in ${A.home}/agents/KB/guides that your fix changes (grep for the file and command names).\n` +
  `9. \`code-review tests ${f.id} after\`: it must print "verified". If not (rc 5): \`code-review restore ${A.run} ${f.id}\`, status reverted.\n` +
  `10. \`code-review unclaim ${f.id}\` whatever happened.\n` +
  `"fixed" counts only with a verified test record; finish restores any fix without one. ` +
  `If an earlier lane already fixed it (the code no longer has the defect), change nothing and return already-fixed. ` +
  `The "also" list names duplicate reports of this same defect: make sure your fix covers them.\n` +
  `Return status, files, test (path + before/after result), restore (\`code-review restore ${A.run} ${f.id}\`), guide (file or "none"), note.`
const retirePrompt = f => `${head}\n\nRETIRE LANE for finding ${f.id} (confirmed ${f.votes}, all refuters agree it is not useful): ${JSON.stringify(f)}\n` +
  `1. Reason: ${f.retire_reason || 'none given'}${f.replacement ? `, replacement ${f.replacement}` : ''}. For duplicate: run both on the ` +
  `same inputs and save the side-by-side output to ${A.run_dir}/${f.id}-proof.txt.\n` +
  `2. \`code-review retire ${f.file} --id ${f.id} --why ${f.retire_reason || '<reason>'}` +
  `${f.replacement ? ` --by ${f.replacement} --proof ${A.run_dir}/${f.id}-proof.txt` : ''} --check\`. rc 4 prints why it stays: return status kept with that reason.\n` +
  `3. Otherwise run the same command without --check; it copies the item to backups/retired/${A.date}/, removes it and prints the ` +
  `one-line restore command. Never rm anything yourself.\n` +
  `4. Run the area tests; if anything that passed before now fails, run the restore command and return reverted.\n` +
  `5. Remove the item from any guide index line that lists it (${A.home}/agents/KB/guides/INDEX.md) only if one exists.\n` +
  `Return status (retired | kept | reverted), restore (the exact line), note.`

const groups = new Map()
const left = []
for (const f of confirmed) {
  const r = route(f)
  if (r.startsWith('left:')) { left.push({ ...f, status: 'left', note: `policy ${r.slice(5)}: reported, not edited` }); continue }
  const k = areaOf(f.file)
  if (!groups.has(k)) groups.set(k, [])
  groups.get(k).push({ ...f, route: r })
}
const capped = []
for (const [k, list] of groups) {
  const order = { high: 0, medium: 1, low: 2 }
  // Retire lanes first: a fix on an item that is then retired is wasted, and a retired item's bugs must not count as fixed.
  list.sort((a, b) => (a.route === 'retire' ? 0 : 1) - (b.route === 'retire' ? 0 : 1) || order[a.severity] - order[b.severity])
  if (list.length > A.fix_cap_per_area) capped.push(...list.splice(A.fix_cap_per_area).map(f => ({ ...f, status: 'deferred', note: 'over this week\'s per-area cap; comes back next week' })))
}
if (capped.length) log(`${capped.length} confirmed findings over the per-area cap of ${A.fix_cap_per_area}: deferred to next week`)

// Toolsmith lane (TSP-029): open auto-ok proposals from toolsmith/BACKLOG.md; each proposal is an owner-backlog finding.
const tsItems = (A.toolsmith_backlog || []).map(t => ({
  id: t.id, key: `toolsmith|${t.id}`.toLowerCase(), file: t.path, line: 1, symbol: t.id, kind: 'toolsmith',
  title: `${t.id} — ${t.title}`, severity: 'medium', lenses: ['toolsmith-backlog'], evidence: t.path,
  verdict: 'confirmed', votes: 'backlog', accept: t.accept,
}))
const backlog = `${A.home}/agents/toolsmith/BACKLOG.md`
const toolsmithPrompt = t => `${head}\n\nTOOLSMITH LANE for ${t.id} (toolsmith backlog, class auto-ok, status proposed). ` +
  `The finding is the proposal ${t.file}; read it whole, every "Evidence update" and "rev." note included (the newest revision ` +
  `wins). Its Success check is the acceptance: ${t.accept || 'see the proposal'}. Follow "Toolsmith lane" in ${A.rules}.\n` +
  `Steps, in order:\n` +
  `1. Paths = the files the proposal names + ${t.file} + ${backlog}; \`code-review policy <paths>\` must print edit for all, ` +
  `else status skipped. A change that needs a package, a unit, settings.json or a reboot: queue it as a fix lane does, status queued.\n` +
  `2. \`code-review claim ${t.id} <paths>\` (rc 3 = status skipped), \`code-review backup ${t.id} <paths>\`, \`code-review tests ${t.id} before\`.\n` +
  `3. Failing test or reproduction first (fixtures only), then the change exactly as the proposal says; your test passes.\n` +
  `4. Re-read the Success check's before number with its measured-by command when that is read-only; never run pcbench.\n` +
  `5. Append to ${t.file} a \`## Result\` section (files touched, validation output, before number re-read, ` +
  `"measurement pending on the next toolsmith run"); in ${backlog} change only the ${t.id} row's status word proposed → measuring. ` +
  `Never change an earlier line of either file: finish restores the whole fix if you do.\n` +
  `6. \`code-review tests ${t.id} after\` must print "verified". If not (rc 5): \`code-review restore ${A.run} ${t.id}\`, then ` +
  `append \`## Result: reverted <why>\` to ${t.file}, leave the row at proposed, status reverted.\n` +
  `7. \`code-review unclaim ${t.id}\` whatever happened.\n` +
  `Return status, files, test, restore (\`code-review restore ${A.run} ${t.id}\`), guide, note.`
const toolsmithLanes = async () => {
  const out = []
  for (const t of tsItems) {
    const r = await agent(toolsmithPrompt(t), { label: `toolsmith:${t.id}`, phase: 'Act', agentType: 'worker', schema: ACT })
    out.push({ ...t, ...(r || { status: 'failed', note: 'lane returned nothing' }) })
  }
  return out
}

// Areas run in parallel; inside one area the lanes run one after another so two fixes never share a file.
const acted = await parallel([toolsmithLanes, ...[...groups.entries()].map(([k, list]) => async () => {
  const area = A.areas.find(a => a.key === k)
  const out = []
  const gone = []
  for (const f of list) {
    const hit = gone.find(g => under(f.file, g))
    if (hit) {
      out.push({ ...f, status: 'deferred', note: `${hit} was retired first in this run; the defect goes with it and comes back if it is restored` })
      continue
    }
    const r = await agent(f.route === 'retire' ? retirePrompt(f) : fixPrompt(f, area),
      { label: `${f.route}:${f.id}`, phase: 'Act', agentType: 'worker', schema: ACT })
    out.push({ ...f, ...(r || { status: 'failed', note: 'lane returned nothing' }) })
    if (r && r.status === 'retired') gone.push(f.file)
  }
  return out
})])
const done = acted.filter(Boolean).flat()
log(`acted on ${done.length}: ${['fixed', 'retired', 'queued', 'staged', 'reverted', 'kept', 'skipped', 'deferred', 'failed']
  .map(s => `${s} ${done.filter(f => f.status === s).length}`).join(', ')}`)

const cut = s => String(s || '').slice(0, 300)
const slim = f => ({
  id: f.id, key: f.key, file: f.file, line: f.line, kind: f.kind, title: f.title, severity: f.severity,
  lenses: f.lenses, evidence: cut(f.evidence), verdict: f.verdict, votes: f.votes, status: f.status || null,
  note: cut(f.note || (f.verdict === 'refuted' ? f.reasons.join(' · ') : '')), test: cut(f.test), restore: f.restore || '',
  queue: f.queue || '', guide: f.guide || '',
})
const actedIds = new Set([...done, ...left, ...capped].map(f => f.id))
const main = [...done, ...left, ...capped, ...judged.filter(f => !actedIds.has(f.id))]
const byId = new Map(main.map(f => [f.id, f]))
const twinsOut = fresh.filter(f => mergedInto.has(f.id)).map(f => {
  const k = byId.get(mergedInto.get(f.id)) || {}
  return { ...f, merged_into: mergedInto.get(f.id), verdict: k.verdict, votes: k.votes, status: k.status, note: `merged into ${mergedInto.get(f.id)}` }
})
return {
  date: A.date, run: A.run, mode: A.mode, lanes: lanes.length, raw: raw.length, unique: unique.length, fresh: fresh.length,
  found: distinct.length + tsItems.length, toolsmith: tsItems.length, merged: mergedInto.size,
  items: [...main.map(slim), ...twinsOut.map(f => ({ ...slim(f), merged_into: f.merged_into }))],
}
