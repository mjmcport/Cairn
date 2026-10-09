# Cairn build tasks. `make` on a clean clone bootstraps, generates, builds and tests.
#
# The Makefile does not depend on `xcode-select`. Override DEVELOPER_DIR to use
# an Xcode that is installed somewhere else:
#     make build DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT := Cairn.xcodeproj
DERIVED_DATA := build/DerivedData
PERFORMANCE := build/performance
DESTINATION := platform=macOS,arch=arm64
SWIFT_SOURCES := App UITests Packages
PACKAGES := TestSupport FileSystemCore FileMetadata FileOperations BrowserUI

XCODEBUILD := xcodebuild -project $(PROJECT) -destination '$(DESTINATION)' \
	-derivedDataPath $(DERIVED_DATA)

.PHONY: all bootstrap generate build test uitest perf perf-baseline lint format clean clean-clone

all: bootstrap build test

bootstrap: ## Check the toolchain and install build tools
	@scripts/bootstrap.sh

generate: ## Create Cairn.xcodeproj from project.yml
	xcodegen generate --quiet

build: generate ## Build the app (Debug)
	$(XCODEBUILD) -scheme Cairn -configuration Debug build

test: generate ## Run the script tests, the project-spec checks and every package's unit tests
	scripts/test-check-governance.sh
	scripts/test-bootstrap.sh
	scripts/check-project-spec.sh
	scripts/test-check-appkit-boundary.sh
	scripts/check-appkit-boundary.sh
	scripts/test-source-checks.sh
	scripts/check-main-thread-guard.sh
	scripts/check-no-network.sh
	scripts/check-accessibility.sh
	scripts/test-performance.sh
	scripts/test-pre-commit.sh
	scripts/test-ci-select-xcode.sh
	@set -e; for package in $(PACKAGES); do \
		echo "== $$package"; \
		xcrun swift test --package-path Packages/$$package --scratch-path build/packages/$$package \
			--skip PerformanceTests; \
	done

uitest: generate ## Run the end-to-end tests
	$(XCODEBUILD) -scheme CairnUITests -skip-testing:CairnUITests/PerformanceTests test

perf: generate ## Run the performance tests and compare them with the committed baseline
	@mkdir -p $(PERFORMANCE)
	@echo "Running the listing performance tests (release build)..."
	@xcrun swift test -c release --package-path Packages/FileSystemCore \
		--scratch-path build/packages-release/FileSystemCore \
		--filter FileSystemCorePerformanceTests > $(PERFORMANCE)/unit.log 2>&1 \
		|| { tail -30 $(PERFORMANCE)/unit.log; exit 1; }
	@echo "Running the time-to-first-rows test..."
	@$(XCODEBUILD) -scheme CairnUITests -only-testing:CairnUITests/PerformanceTests test \
		> $(PERFORMANCE)/ui.log 2>&1 || { tail -30 $(PERFORMANCE)/ui.log; exit 1; }
	@scripts/performance.py parse $(PERFORMANCE)/unit.log $(PERFORMANCE)/ui.log \
		--output $(PERFORMANCE)/latest.json
	@scripts/performance.py compare docs/performance/baseline.json $(PERFORMANCE)/latest.json

perf-baseline: ## Record this Mac's measurements as the new committed baseline
	@rm -f $(PERFORMANCE)/latest.json
	@$(MAKE) perf || true
	@test -f $(PERFORMANCE)/latest.json
	cp $(PERFORMANCE)/latest.json docs/performance/baseline.json

lint: ## Check governance files and Swift formatting
	scripts/check-governance.sh
	xcrun swift-format lint --strict --recursive --configuration .swift-format $(SWIFT_SOURCES)

format: ## Reformat every Swift file in place
	xcrun swift-format format --in-place --recursive --configuration .swift-format $(SWIFT_SOURCES)

clean-clone: ## Prove a clean copy of the repository builds and tests with one command
	scripts/test-clean-clone.sh

clean: ## Remove build output and the generated project
	rm -rf build $(PROJECT)
