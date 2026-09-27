CC=clang
CFLAGS_COMMON=-mmacosx-version-min=14.0 -Wall -O2
FRAMEWORKS=-framework Cocoa
EXPORTS=-Wl,-exported_symbol,_instantmini_patch -Wl,-exported_symbol,_instantmini_verify

all: payload.dylib

payload.dylib: src/payload.m
	$(CC) $(CFLAGS_COMMON) -arch arm64e -dynamiclib $(FRAMEWORKS) $(EXPORTS) src/payload.m -o $@

install: payload.dylib osax/Info.plist
	sudo mkdir -p /Library/ScriptingAdditions/instantmini.osax/Contents/Resources
	sudo cp osax/Info.plist /Library/ScriptingAdditions/instantmini.osax/Contents/Info.plist
	sudo cp payload.dylib /Library/ScriptingAdditions/instantmini.osax/Contents/Resources/payload.dylib
	sudo codesign -s - -f /Library/ScriptingAdditions/instantmini.osax/Contents/Resources/payload.dylib || true
	sudo xattr -dr com.apple.quarantine /Library/ScriptingAdditions/instantmini.osax/Contents/Resources/payload.dylib || true

uninstall:
	sudo rm -rf /Library/ScriptingAdditions/instantmini.osax

clean:
	rm -f payload.dylib