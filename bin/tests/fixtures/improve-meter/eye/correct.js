/** Fixture corrector: rewrites "kol" to "call". */
module.exports = { correct: (t) => ({ text: t.replace(/\bkol\b/gi, "call"), fixes: [] }) };
