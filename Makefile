.PHONY: install uninstall doctor preamble

# Wire this checkout into the machine (idempotent).
install:
	@./install.sh

# Remove the wiring; keeps secrets/, log/, backups/ and config.env.
uninstall:
	@./uninstall.sh

# Health check for the whole pc family.
doctor:
	@bin/pc doctor

# Regenerate AGENT-PREAMBLE.md from AGENTS.md, the single hand-edited contract.
preamble:
	@cat AGENT-PREAMBLE.head.md AGENTS.md > AGENT-PREAMBLE.md
	@echo "AGENT-PREAMBLE.md regenerated from AGENTS.md"
