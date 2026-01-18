.PHONY: build install release release-install clean

debug:
	xcodebuild -project Switchboard.xcodeproj -scheme Switchboard -configuration Debug build

debug-install: build
	cp -R ~/Library/Developer/Xcode/DerivedData/Switchboard-*/Build/Products/Debug/Switchboard.app /Applications/

release:
	xcodebuild -project Switchboard.xcodeproj -scheme Switchboard -configuration Release build

install: release
	cp -R ~/Library/Developer/Xcode/DerivedData/Switchboard-*/Build/Products/Release/Switchboard.app /Applications/

clean:
	xcodebuild -project Switchboard.xcodeproj -scheme Switchboard clean
