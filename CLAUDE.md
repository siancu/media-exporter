# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Building
```bash
# Development build
swift build

# Release build (optimized)
swift build -c release

# Run from source during development
swift run media-exporter --from-date YYYY-MM-DD --to-date YYYY-MM-DD --output-folder /path/to/output
```

### Installation
```bash
# Install release executable to home directory
mkdir -p ~/bin && cp .build/release/media-exporter ~/bin/

# Install to system path (requires sudo)
sudo cp .build/release/media-exporter /usr/local/bin/
```

## Architecture Overview

This is a single-file Swift command-line application that exports photos and videos from macOS Photos library. The architecture is intentionally simple with all logic contained in `Sources/media-exporter/main.swift`.

### Core Components

**MediaExporter (ParsableCommand)**: Main entry point using ArgumentParser for CLI interface with three required arguments: `--from-date`, `--to-date`, and `--output-folder`.

**Export Processing**: Sequential processing using DispatchSemaphore to ensure one-at-a-time export with proper progress logging. Previously used concurrent processing which caused confusing output.

**Photo Export Pipeline**: PhotoKit → CIImage → JPEG conversion → EXIF date extraction → file naming with collision handling.

**Video Export Pipeline**: PhotoKit → AVAsset → AVAssetExportSession with highest quality preset → file naming based on asset creation date.

### Key Technical Details

- **Platform**: macOS 12.0+ only (uses PhotoKit framework)
- **Dependencies**: swift-argument-parser for CLI interface
- **File Naming**: `YYYY-MM-DD HH.MM.SS.ext` format with sequential numbering for collisions
- **Photo Processing**: Prioritizes edited versions over originals, converts all to JPEG
- **Video Processing**: Exports at highest available resolution as .mov files
- **Permission Handling**: Automatic Photos library access request on first run

### Progress Logging System

The application provides detailed sequential logging showing:
- Export start/completion for each asset with index (e.g., `[1/150]`)
- Individual timing for each export
- Success/failure indicators with emojis
- Overall summary with total time

### Important Implementation Notes

- Export processing is **sequential**, not concurrent - each asset completes before the next begins
- EXIF data extraction is used for accurate photo timestamps
- File collision handling appends sequential numbers (`.01`, `.02`, etc.)
- Error handling preserves progress flow and continues with remaining assets
- String formatting uses Swift's `String(format:)` rather than printf-style formatting