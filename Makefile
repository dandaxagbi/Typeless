.PHONY: all build run model install clean check

APP_NAME = Typeless
ROOT_DIR = $(shell pwd)

all: build

build:
	@./scripts/build_app.sh

model:
	@./scripts/download_model.sh small.en

model-tiny:
	@./scripts/download_model.sh tiny.en

model-base:
	@./scripts/download_model.sh base.en

install: build
	@./scripts/install.sh

run: build
	@echo "Launching $(APP_NAME).app..."
	@open $(APP_NAME).app

run-cli:
	@swiftc -O Sources/Typeless/*.swift -o $(APP_NAME) -framework Cocoa -framework Carbon
	@./$(APP_NAME)

check:
	@echo "Checking system dependencies:"
	@which ffmpeg || echo "✗ ffmpeg not found (run: brew install ffmpeg)"
	@which whisper-cli || echo "✗ whisper-cli not found (run: brew install whisper.cpp)"
	@which swiftc || echo "✗ swiftc not found"

clean:
	@rm -rf $(APP_NAME).app $(APP_NAME) .build
	@echo "Cleaned build artifacts."
