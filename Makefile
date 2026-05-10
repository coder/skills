# Repo-level developer entry points. Defers to scripts/lint.sh and
# scripts/fmt.sh so the same logic runs locally and in CI without
# duplication.

.PHONY: help lint fmt fmt-check test test-claude test-codex

help:
	@echo "Targets:"
	@echo "  lint       Run every linter (shellcheck, shfmt, markdownlint, jq, claude plugin validate, emdash, SKILL.md description length)."
	@echo "  fmt        Apply auto-formatters in place (shfmt, markdownlint --fix, jq)."
	@echo "  fmt-check  Verify formatters would not change anything (alias for the formatting subset of lint)."
	@echo "  test       Run both end-to-end harnesses (Claude Code and Codex)."
	@echo "  test-claude  Run only the Claude Code end-to-end harness."
	@echo "  test-codex   Run only the Codex end-to-end harness."

lint:
	@bash scripts/lint.sh

fmt:
	@bash scripts/fmt.sh

fmt-check:
	@bash scripts/lint.sh

test: test-claude test-codex

test-claude:
	@bash test/run.sh

test-codex:
	@bash test/run-codex.sh
