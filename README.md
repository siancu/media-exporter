# Media Exporter

A macOS command-line tool that exports photos and videos from your Photos library within a specified date range.

## Features

- Export photos and videos from Photos library based on date range
- Convert photos to JPEG format with highest quality
- Export videos at highest available resolution (.mov format)
- Extract creation dates from EXIF data for accurate file naming
- Handle file name collisions with sequential numbering
- Create output directories automatically
- **Progress logging with timing information for each export**

## Requirements

- macOS 12.0 or later
- Swift 5.8 or later
- Photos library access permission

## Building

### Development Build
```bash
swift build
```

### Release Build (Optimized)
```bash
swift build -c release
```

The release executable will be created at `.build/release/media-exporter`

## Installation

After building the release version, you can install the executable for easy access:

### Option 1: Install to Home Directory (Recommended)
```bash
# Create bin directory in your home folder
mkdir -p ~/bin

# Copy the executable
cp .build/release/media-exporter ~/bin/

# Add ~/bin to your PATH (add this to your ~/.zshrc or ~/.bash_profile)
export PATH="$HOME/bin:$PATH"

# Reload your shell or run:
source ~/.zshrc  # or source ~/.bash_profile
```

### Option 2: Install to System PATH
```bash
# Install to system-wide location (requires sudo)
sudo cp .build/release/media-exporter /usr/local/bin/
```

### Verify Installation
```bash
# Check if the executable is accessible
which media-exporter

# Test the installation
media-exporter --help
```

## Usage

### Running from Source
```bash
swift run media-exporter --from-date YYYY-MM-DD --to-date YYYY-MM-DD --output-folder /path/to/output
```

### Running Installed Executable
```bash
media-exporter --from-date YYYY-MM-DD --to-date YYYY-MM-DD --output-folder /path/to/output
```

### Examples

Export photos and videos from January 2024:
```bash
# From source
swift run media-exporter --from-date 2024-01-01 --to-date 2024-01-31 --output-folder ~/Desktop/January2024

# Using installed executable
media-exporter --from-date 2024-01-01 --to-date 2024-01-31 --output-folder ~/Desktop/January2024
```

Export a single day:
```bash
# From source
swift run media-exporter --from-date 2024-06-15 --to-date 2024-06-15 --output-folder ~/Desktop/TodaysPhotos

# Using installed executable
media-exporter --from-date 2024-06-15 --to-date 2024-06-15 --output-folder ~/Desktop/TodaysPhotos
```

## File Naming

Files are named using their creation date in the format: `YYYY-MM-DD HH.MM.SS.ext`

If multiple files have the same timestamp, they are numbered sequentially:
- `2024-06-15 14.30.25.jpg`
- `2024-06-15 14.30.25 01.jpg`
- `2024-06-15 14.30.25 02.mov`

## Permissions

The first time you run the application, macOS will prompt you to grant access to your Photos library. You must allow this permission for the tool to work.

## Progress Logging

The tool provides detailed progress information during export:

```
=== Media Export Started ===
Date range: 2024-01-01 to 2024-01-31
Output folder: ~/Desktop/January2024

Found 150 assets to export...
[1/150] Starting photo export...
[1/150] ✅ Photo exported: 2024-01-01 10.30.25.jpg (0.85s)
[2/150] Starting video export (copying)...
[2/150] ✅ Video exported: 2024-01-01 15.22.10.mov (0.42s)
[3/150] Starting video export (re-encoding)...
[3/150] ✅ Video exported: 2024-01-01 16.45.30.mov (8.15s)
...

=== Export Complete ===
Successfully exported 148 files to ~/Desktop/January2024
Total time: 125.30 seconds
```

## Implementation Details

- Uses PhotoKit framework for Photos library access
- Exports photos as JPEG using CoreImage
- **Smart video export**: Uses passthrough (copy) for original videos, re-encoding only for edited videos
- Extracts EXIF metadata using ImageIO framework
- Supports edited versions of photos and videos
- Individual export timing with success/failure indicators