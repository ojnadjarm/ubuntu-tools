# Invoicing: draft, issue and track the owner's freelance invoices (series YYYY-C-NN)

Ticket: T134 · Last verified: 2026-09-28 by selftest.sh (sandbox issue, totals, back-date refusal, paid, check) and a
field-token diff of the regenerated 2026-C-10 against his original PDF (75 of 75 tokens, only the total gained ".00")

## When to use
Any invoice for the owner: the monthly Moodle invoice, a new client, marking paid, the ledger, a lost PDF. Skill `/invoice`.
Not for Verifactu-compliant invoicing after 1 Jul 2027: that needs certified software (see Pitfalls).

## The path we took
- Survey: Invoice Ninja (his current PDFs look like its "Clean" design; self-hosted, but its team says no Verifactu for
  self-hosted), InvoiceShelf/Crater/Akaunting (PHP + DB + queue stacks, no verified Verifactu). Chosen: a stdlib-Python CLI +
  JSON ledger + HTML template printed by headless Chrome: no service, no DB, one private folder, drivable by agents.
- Modules (`~/.claude/skills/invoice/scripts/`):

| Module | Job |
|---|---|
| `invoice` | CLI (argparse): new, issue, list, pdf, paid, check, import; month rule |
| `invlib/store.py` | private store paths (`INVOICE_HOME`), atomic JSON writes, flock, numbering, check, backups |
| `invlib/model.py` | Decimal totals (base, IVA, IRPF, total), EUR conversion (ECB via Frankfurter), record build |
| `invlib/render.py` + `template.html` | record → HTML (A4, Roboto, traced SVG logo) → Chrome `--print-to-pdf` |

- Data flow: `clients.json` defaults → `new` → `drafts/<n>-<client>-draft.{json,pdf}` (number not consumed) → `issue`
  (under lock: read the draft, next number, date ≥ last, final `pdf/<n>.pdf`, append `ledger.json`) → tarball in `~/agents/backups/invoices/`.
- Records snapshot the client's billing data, so editing `clients.json` never changes old invoices.
- Logo: `potrace` trace of `logo-onj.png` (crop, 4× upscale, threshold 128, colour #1e2e39) → `assets/logo-onj.svg`, 16 KB.

## Exact commands
```bash
invoice new --client moodle          # month after the last invoice's period, dated the 1st of the next month
invoice issue <draft-name>           # only on the owner's word
invoice list --unpaid ; invoice paid 2026-C-11 ; invoice check
~/.claude/skills/invoice/scripts/selftest.sh
```

## Pitfalls (measured)
- Verifactu (RD 1007/2023, AEAT FAQ checked 2026-09-28): self-developed invoicing software is a SIF and its developer must
  certify it (declaración responsable); applies in Catalonia and to invoices for foreign clients. RDL 15/2025 moved the
  deadline to 1 Jan 2027 (IS taxpayers) and **1 Jul 2027 for autónomos**. This CLI is fine until then, not after.
- Python's default User-Agent gets HTTP 403 from api.frankfurter.app; use `api.frankfurter.dev/v1` with a UA header.
- A future date returns the latest ECB rate (2026-09-28 for 2026-10-01): re-run `new` on the issue day.
- Decimal is not JSON-serialisable: store amounts as strings, qty as int/float.
- Every amount (base, IVA, IRPF, EUR total, PDF line) rounds ROUND_HALF_UP; bare `.quantize()` is half-even and made
  10.05 x 2.5 hours bill 25.12 (F49, 2026-10-15; selftest case "half-cent rounds half-up").
- `issue` reads the draft under the lock: a second concurrent `issue` of the same draft exits "already issued"
  instead of taking a second number (F47, 2026-10-15; selftest case "concurrent issue of one draft").
- Chrome needs its own `--user-data-dir` per run or it clashes with an open profile; the HTML temp lives in `~/invoices/.tmp`.
- His original invoices carry no NIF and no IVA-exemption reason; `config.json` `issuer.tax_id` and client `defaults.notes`
  print them when filled.

## Links
- Code: `~/.claude/skills/invoice/`, CLI symlink `~/agents/bin/invoice`
- Tests: `~/.claude/skills/invoice/scripts/selftest.sh` (sandbox copy; prints PASS)
- Data (private, 700): `~/invoices/`; backups `~/agents/backups/invoices/`
