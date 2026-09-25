.PHONY: test lint check-skills

TESTS := $(sort $(wildcard test/run*.lua))

test:
	@set -u; \
	status=0; \
	printf '\n==> skill frontmatter\n'; \
	if ./scripts/check_skill_frontmatter.sh; then \
		printf 'PASS: skill frontmatter\n'; \
	else \
		status=1; \
		printf 'FAIL: skill frontmatter\n' >&2; \
	fi; \
	for test in $(TESTS); do \
		printf '\n==> %s\n' "$$test"; \
		if nvim --headless -u NONE -l "$$test"; then \
			printf 'PASS: %s\n' "$$test"; \
		else \
			test_status=$$?; \
			status=1; \
			printf 'FAIL: %s (exit %s)\n' "$$test" "$$test_status" >&2; \
		fi; \
	done; \
	if [ "$$status" -ne 0 ]; then \
		printf '\nTEST SUITE FAILED\nFix the failures and re-run: make test\n' >&2; \
		exit "$$status"; \
	fi; \
	printf '\nAll tests passed.\n'

lint:
	luacheck lua test

check-skills:
	./scripts/check_skill_frontmatter.sh
