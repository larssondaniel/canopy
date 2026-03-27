.PHONY: project build test release open clean

# Generate Xcode project from project.yml
project:
	xcodegen generate

# Build the app
build: project
	xcodebuild -project Canopy.xcodeproj -scheme Canopy -configuration Debug build

# Run tests
test: project
	xcodebuild -project Canopy.xcodeproj -scheme Canopy -configuration Debug test

# Build for release
release: project
	xcodebuild -project Canopy.xcodeproj -scheme Canopy -configuration Release build

# Open in Xcode
open: project
	open Canopy.xcodeproj

# Clean build artifacts
clean:
	xcodebuild -project Canopy.xcodeproj -scheme Canopy clean 2>/dev/null || true
	rm -rf DerivedData build
	rm -rf Canopy.xcodeproj
