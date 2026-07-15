.PHONY: all build test fmt check clean deps coverage

# All dune invocations are pinned to this project's local opam switch and
# project root, regardless of which switch is active in the calling shell
# or how deep the invoking directory is nested (e.g. under a worktree that
# lives inside the main checkout and therefore has no _opam of its own).
# This guards against silent builds/tests against the wrong switch.
OPAM_SWITCH_DIR := $(shell d="$(CURDIR)"; while [ "$$d" != "/" ]; do \
	if [ -d "$$d/_opam" ]; then echo "$$d"; break; fi; \
	d=$$(dirname "$$d"); done)
ifeq ($(strip $(OPAM_SWITCH_DIR)),)
$(error No _opam switch found in any ancestor of $(CURDIR); create the project switch first: opam switch create . --deps-only --with-test)
endif
DUNE := opam exec --switch $(OPAM_SWITCH_DIR) -- dune

all: build

deps:
	opam install --deps-only --with-test -y --switch $(OPAM_SWITCH_DIR) .

build:
	$(DUNE) build --root . @all

test:
	$(DUNE) runtest --root .

fmt:
	$(DUNE) fmt --root .

check: build test fmt

clean:
	$(DUNE) clean --root .

coverage:
	rm -rf _coverage
	mkdir -p _coverage
	BISECT_ENABLE=YES BISECT_FILE=$(PWD)/_coverage/bisect $(DUNE) build --root . --instrument-with bisect_ppx @all
	# Run test executables manually so BISECT_* env vars are honored in sandboxed runs.
	find _build/default/test -maxdepth 1 -type f -name '*.exe' -print0 | \
		xargs -0 -n1 env BISECT_ENABLE=YES BISECT_FILE=$(PWD)/_coverage/bisect
	bisect-ppx-report summary --per-file --coverage-path _coverage > _coverage/summary.txt
	bisect-ppx-report html --coverage-path _coverage -o _coverage/html
	@cat _coverage/summary.txt
