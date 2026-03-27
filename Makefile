APP     = cypher.app
BINARY  = cypher
BUNDLE  = $(APP)/Contents
CLI     = /usr/local/bin/cypher

.PHONY: build install uninstall clean

build:
	go build -o $(BINARY) .
	mkdir -p $(BUNDLE)/MacOS
	cp $(BINARY) $(BUNDLE)/MacOS/
	cp Info.plist $(BUNDLE)/
	codesign --sign - --force $(APP)

install: build
	rm -rf /Applications/$(APP)
	cp -r $(APP) /Applications/
	@sudo bash -c 'printf "#!/bin/sh\nopen -a cypher \"\$$@\"\n" > $(CLI) && chmod +x $(CLI)'
	@echo "Installed. Run 'cypher' from any terminal to launch."

uninstall:
	rm -rf /Applications/$(APP)
	sudo rm -f $(CLI)

clean:
	rm -rf $(BINARY) $(APP)
