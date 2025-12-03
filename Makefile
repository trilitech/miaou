.PHONY: all build test fmt clean deps

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
