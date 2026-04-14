APP      = cypher.app
BINARY   = cypher
BUNDLE   = $(APP)/Contents
CLI      = /usr/local/bin/cypher
DEST     = /Applications/$(APP)
TEST_BIN = tests/test_helpers

.PHONY: build install update uninstall clean test

build:
	go build -o $(BINARY) .
	mkdir -p $(BUNDLE)/MacOS $(BUNDLE)/Resources
	cp $(BINARY) $(BUNDLE)/MacOS/
	cp Info.plist $(BUNDLE)/
	cp cypher.icns $(BUNDLE)/Resources/
	codesign --sign - --force $(APP)

install: build
	sudo cp -r $(APP) /Applications/
	@sudo bash -c 'printf "#!/bin/sh\nopen -a cypher \"\$$@\"\n" > $(CLI) && chmod +x $(CLI)'
	@echo "Installed. Run 'cypher' to launch."

# Update in-place — rsync preserves the bundle directory so macOS keeps
# Accessibility & Input Monitoring grants.
update: build
	@pkill -x cypher 2>/dev/null || true
	@sleep 0.3
	sudo rsync -a --delete $(APP)/ $(DEST)/
	open -a cypher
	@echo "Updated and relaunched."

uninstall:
	@pkill -x cypher 2>/dev/null || true
	sudo rm -rf $(DEST)
	sudo rm -f $(CLI)

test: build $(TEST_BIN)
	@echo "── Unit tests ──────────────────────────────"
	@./$(TEST_BIN)
	@echo ""
	@echo "── Smoke tests ─────────────────────────────"
	@bash tests/smoke_test.sh

$(TEST_BIN): tests/test_helpers.m hotkey_helpers.h
	@clang -x objective-c -fobjc-arc -mmacosx-version-min=11.0 \
	  -framework Foundation -framework Carbon -framework CoreGraphics \
	  -o $(TEST_BIN) tests/test_helpers.m

clean:
	rm -rf $(BINARY) $(APP) $(TEST_BIN)
