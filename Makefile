# The editor's workflows. `make help` lists them.

.PHONY: help build run test check fmt check-files hooks pictures

help:
	@echo "make build        build the editor into zig-out/bin"
	@echo "make run          build and run the editor (ARGS='<mod folder>' to open one)"
	@echo "make test         run the tests"
	@echo "make check        run the checks CI runs: formatting, files, tests"
	@echo "make fmt          format the Zig code"
	@echo "make hooks        install the pre-commit hook that keeps the game's files out"
	@echo "make pictures     take the design's pictures again (design/pictures.sh)"

build:
	zig build --release=safe

run:
	zig build run --release=safe -- $(ARGS)

test:
	zig build test --summary all

check: check-files
	zig fmt --check src build.zig
	zig build test --summary all

fmt:
	zig fmt src build.zig

check-files:
	scripts/check-files.sh

hooks:
	printf '#!/bin/sh\nexec scripts/check-files.sh --staged\n' > .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit

pictures:
	design/pictures.sh
