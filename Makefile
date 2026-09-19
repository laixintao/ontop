.PHONY: help build test check package ci release
.DEFAULT_GOAL := help

# Export instead of interpolating shell arguments; VERSION is validated in Python.
export VERSION

help:
	@printf '%s\n' 'make build                     Build the native app' 'make test                      Run native tests in both languages' 'make check                     Check project metadata and release automation' 'make package                   Create universal installers in dist/' 'make ci                        Run all local checks and package verification' 'make release                   Bump patch version, commit, tag, and push; CI publishes' 'make release VERSION=1.2.0       Release a specific newer version'

build:
	./scripts/build.sh

test:
	./scripts/test.sh

check:
	python3 scripts/check-project.py
	python3 scripts/test-release.py

package:
	./scripts/package.sh

ci:
	./scripts/ci.sh

release:
	python3 scripts/release.py
