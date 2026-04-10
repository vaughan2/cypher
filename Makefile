APP      = cypher.app
BINARY   = cypher
BUNDLE   = $(APP)/Contents
CLI      = /usr/local/bin/cypher
DEST     = /Applications/$(APP)
SIGN_ID  = CypherCodeSign
TEST_BIN = tests/test_helpers

.PHONY: build install update uninstall clean setup-cert trust-cert test

# One-time setup: creates a local code-signing cert in your login keychain.
# With a stable cert, TCC anchors permissions to the cert identity instead of
# the binary hash — so Accessibility & Input Monitoring survive rebuilds.
setup-cert:
	@printf '[req]\ndistinguished_name=dn\nx509_extensions=v3_req\nprompt=no\n[dn]\nCN=$(SIGN_ID)\nO=Local\n[v3_req]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n' > /tmp/cypher-cert.cnf
	@/usr/bin/openssl req -new -x509 -newkey rsa:2048 -nodes \
	  -keyout /tmp/cypher-sign.key \
	  -out /tmp/cypher-sign.crt \
	  -days 3650 \
	  -config /tmp/cypher-cert.cnf 2>/dev/null
	@/usr/bin/openssl pkcs12 -export \
	  -in /tmp/cypher-sign.crt \
	  -inkey /tmp/cypher-sign.key \
	  -out /tmp/cypher-sign.p12 \
	  -passout pass:cypher
	@security import /tmp/cypher-sign.p12 \
	  -k ~/Library/Keychains/login.keychain-db \
	  -P "cypher" \
	  -T /usr/bin/codesign
	@security add-trusted-cert \
	  -r trustRoot \
	  -k ~/Library/Keychains/login.keychain-db \
	  /tmp/cypher-sign.crt
	@rm -f /tmp/cypher-sign.* /tmp/cypher-cert.cnf
	@echo "Certificate '$(SIGN_ID)' installed and trusted."
	@security find-identity -p codesigning | grep $(SIGN_ID) || echo "Warning: cert not found, check Keychain Access"

# Run this if you already imported the cert but it still shows CSSMERR_TP_NOT_TRUSTED.
trust-cert:
	@security find-certificate -c "$(SIGN_ID)" -p > /tmp/cypher-trust.crt
	@security add-trusted-cert \
	  -r trustRoot \
	  -k ~/Library/Keychains/login.keychain-db \
	  /tmp/cypher-trust.crt
	@rm /tmp/cypher-trust.crt
	@echo "Done. Verify: security find-identity -p codesigning | grep $(SIGN_ID)"

build:
	go build -o $(BINARY) .
	mkdir -p $(BUNDLE)/MacOS $(BUNDLE)/Resources
	cp $(BINARY) $(BUNDLE)/MacOS/
	cp Info.plist $(BUNDLE)/
	cp cypher.icns $(BUNDLE)/Resources/
	codesign --sign "$(SIGN_ID)" --force $(APP)

# First-time install only — sets up the bundle and CLI wrapper.
# Run make setup-cert first if you haven't already.
install: build
	sudo cp -r $(APP) /Applications/
	@sudo bash -c 'printf "#!/bin/sh\nopen -a cypher \"\$$@\"\n" > $(CLI) && chmod +x $(CLI)'
	@echo "Installed. Run 'cypher' to launch."

# Update in-place — rsync preserves the bundle directory so macOS keeps
# Accessibility & Input Monitoring grants. Stable cert keeps TCC happy too.
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
