# Cairn build tasks. `make` on a clean clone bootstraps, generates, builds and tests.
#
# The Makefile does not depend on `xcode-select`. Override DEVELOPER_DIR to use
# an Xcode that is installed somewhere else:
#     make build DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT := Cairn.xcodeproj
DERIVED_DATA := build/DerivedData
DESTINATION := platform=macOS,arch=arm64
SWIFT_SOURCES := App UITests

XCODEBUILD := xcodebuild -project $(PROJECT) -destination '$(DESTINATION)' \
	-derivedDataPath $(DERIVED_DATA)

.PHONY: all bootstrap generate build test uitest lint clean clean-clone

all: bootstrap build test

bootstrap: ## Check the toolchain and install build tools
	@scripts/bootstrap.sh

generate: ## Create Cairn.xcodeproj from project.yml
	xcodegen generate --quiet

build: generate ## Build the app (Debug)
	$(XCODEBUILD) -scheme Cairn -configuration Debug build

test: generate ## Run the script tests and the project-spec checks
	scripts/test-check-governance.sh
	scripts/test-bootstrap.sh
	scripts/check-project-spec.sh

uitest: generate ## Run the end-to-end tests
	$(XCODEBUILD) -scheme CairnUITests test

lint: ## Check governance files and Swift formatting
	scripts/check-governance.sh
	xcrun swift-format lint --recursive $(SWIFT_SOURCES)

clean-clone: ## Prove a clean copy of the repository builds and tests with one command
	scripts/test-clean-clone.sh

clean: ## Remove build output and the generated project
	rm -rf build $(PROJECT)
