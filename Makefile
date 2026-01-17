.PHONY: build install clean

build:
	xcodebuild -project Switchboard/Switchboard.xcodeproj -scheme Switchboard -configuration Debug build

install: build
	cp -R ~/Library/Developer/Xcode/DerivedData/Switchboard-*/Build/Products/Debug/Switchboard.app /Applications/

clean:
	xcodebuild -project Switchboard/Switchboard.xcodeproj -scheme Switchboard clean
