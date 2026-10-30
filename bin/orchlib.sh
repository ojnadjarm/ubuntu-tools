#!/usr/bin/env bash
# orchlib.sh — orchestrator pane probes shared by orchestrator-pulse and orchestrator-update-restart. Source it, never execute it.
#   The caller defines tm (tmux wrapper) and sets PANE, MARK (orchestrator prompt file name) and CLAUDE_DIR.
#   orch_pid <root-pid>       pid of the orchestrator claude (argv names claude and --append-system-prompt-file …$MARK) below root
#   reg <pid> <field>         field of the Claude session registry entry $CLAUDE_DIR/sessions/<pid>.json (empty when absent)
#   pane                      the pane's text, joined
#   prompt_line               the last prompt-glyph line with ghost text (dim suggestions) removed
#   pane_busy <text>          prints why the pane text shows a running turn or background agents; empty when neither

orch_pid() { ps -eo pid=,ppid=,args= | awk -v root="$1" -v mark="$MARK" '
  { pp[$1] = $2; a = $0; sub(/^ *[0-9]+ +[0-9]+ +/, "", a); args[$1] = a }
  END { for (p in pp) { q = p; while (q in pp && q != root && q > 1) q = pp[q]; if (q != root || p == root) continue
          n = split(args[p], v, " "); c = 0
          for (i = 1; i <= n; i++) { if (v[i] ~ /(^|\/)claude$/) c = 1
            if (c && v[i] == "--append-system-prompt-file" && index(v[i+1], mark)) { print p; exit } } } }'; }
reg() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' "$CLAUDE_DIR/sessions/$1.json" "$2" 2>/dev/null; }
pane() { tm capture-pane -pJt "$PANE" 2>/dev/null; }
# Drops dim ghost text (prompt suggestions) and the inverse cursor cell right before it; other escapes removed.
unghost() { perl -ne '
  chomp; my ($o, $h) = ("", "");
  for my $t (split /(\e\[[0-9;:]*m)/) {
    if ($t =~ /^\e\[([0-9;:]*)m$/) {
      my @p = split /[;:]/, $1; @p = (0) unless @p;
      while (@p) {
        my $c = shift(@p) || 0;
        if ($c == 0) { $d = $i = 0 } elsif ($c == 2) { $d = 1 } elsif ($c == 22) { $d = 0 }
        elsif ($c == 7) { $i = 1 } elsif ($c == 27) { $i = 0 }
        elsif ($c =~ /^[345]8$/) { my $m = shift(@p) || 0; splice @p, 0, ($m == 5 ? 1 : $m == 2 ? 3 : 0) }
      }
      next;
    }
    next if $t eq "";
    if ($d) { $h = ""; next }
    $o .= $h; $h = "";
    if ($i) { $h = $t } else { $o .= $t }
  }
  $o .= $h; $o =~ s/\e(\[[0-9;?]*[A-Za-z]|\][^\a\e]*(\a|\e\\))//g; print "$o\n"'; }
prompt_line() { tm capture-pane -peJt "$PANE" 2>/dev/null | unghost | grep -E '^(❯|>)' | tail -n1; }
pane_busy() {
  case "$1" in
    *"esc to interrupt"*) echo "turn in progress" ;;
    *"Waiting for"*"background"*) echo "background agents running" ;;
  esac
}
