# flagdoc.awk: prints "ok" when a doc line naming CLI (or under a ## heading naming it, ### and deeper inherit it) has FLAG as a whole word, else the other CLIS it is under, comma-separated.
# usage: awk -v cli=NAME -v flag=--FLAG -v clis="NAME OTHER..." -f flagdoc.awk DOC...   (T912, T954)
function re(w) { sub(/\.sh$/, "", w); gsub(/\./, "[.]", w); return "(^|[^-A-Za-z0-9_])" w "([^-A-Za-z0-9_]|$)" }
BEGIN { me = re(cli); f = re(flag); n = split(clis, C, " ") }
FNR == 1 { h2 = h3 = ""; fence = 0 }
/^```/ { fence = !fence }
!fence && /^#+ / { match($0, /^#+/); if (RLENGTH > 2) h3 = $0; else { h2 = RLENGTH == 2 ? $0 : ""; h3 = "" } }
$0 !~ f { next }
{ line = $0 " " h2 " " h3 }
line ~ me { found = 1; exit }
{ for (i = 1; i <= n; i++) if (C[i] != cli && line ~ re(C[i])) other[C[i]] = 1 }
END { if (found) { print "ok"; exit } for (c in other) s = s (s ? "," : "") c; print s }
