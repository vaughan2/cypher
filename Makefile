APP     = hotkey-incognito.app
BINARY  = hotkey-incognito
BUNDLE  = $(APP)/Contents

.PHONY: build install clean

build:
	go build -o $(BINARY) .
	mkdir -p $(BUNDLE)/MacOS
	cp $(BINARY) $(BUNDLE)/MacOS/
	cp Info.plist $(BUNDLE)/
	codesign --sign - --force $(APP)

install: build
	rm -rf /Applications/$(APP)
	cp -r $(APP) /Applications/

clean:
	rm -rf $(BINARY) $(APP)
