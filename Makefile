.PHONY: all build test fmt clean deps coverage

all: build

deps:
	opam install --deps-only --with-test -y .

build:
	dune build @all

test:
	dune runtest

fmt:
	dune fmt

clean:
	dune clean

coverage:
	rm -rf _coverage
	mkdir -p _coverage
	BISECT_ENABLE=YES BISECT_FILE=$(PWD)/_coverage/bisect dune build --instrument-with bisect_ppx @all
	# Run test executables manually so BISECT_* env vars are honored in sandboxed runs.
	find _build/default/test -maxdepth 1 -type f -name '*.exe' -print0 | \
		xargs -0 -n1 env BISECT_ENABLE=YES BISECT_FILE=$(PWD)/_coverage/bisect
	bisect-ppx-report summary --per-file --coverage-path _coverage > _coverage/summary.txt
	bisect-ppx-report html --coverage-path _coverage -o _coverage/html
	@cat _coverage/summary.txt
