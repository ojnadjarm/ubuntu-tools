# TSP-NNN — <short title>

## Problem
One or two sentences: what is slow, wasteful, or missing.

## Evidence
What shows the problem is real. Each line cites a location: `path:line`, or a benchmark
coordinate `run/task/arm/i`. No evidence line, no proposal.

- `path/to/file:123` — ...
- `run-2026-09-01/O02/new/3` — ...

## Survey
What exists already, what was chosen, and why. Cite a URL when the option is web-sourced.

- exists: ...
- chosen: ...
- why: ...

## Proposed change
What changes, concretely: files touched, new behavior, interface.

## Success check
`metric / before (number) / target (number) / measured by (command)`

- metric: <name>
- before: <number>
- target: <number>
- measured by: `<command>`

## Effort
`model / sessions (integer) / resident (CPU/RSS or none)`

- model: <sonnet|opus|haiku>
- sessions: <integer>
- resident: <CPU/RSS figure, or "none">

## Class
`auto-ok` or `owner-go`, optionally with a contract reference `contract-§5`.

<auto-ok | owner-go> [contract-§N]

## Result
<optional — filled in once the change is measured>
