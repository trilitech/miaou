#!/usr/bin/env bash
#
# Capture initial frames from all MIAOU demos using the built-in frame capture
#
# This script uses MIAOU's native frame capture to grab the initial render
# of each demo, then converts it to a text file that can be displayed.
#
# Usage:
#   ./tools/capture_demo_frames.sh [--demo NAME] [--output-dir DIR]
#
# The captured frames are plain text with ANSI codes, suitable for:
#   - Viewing in terminal: cat screenshot.txt
#   - Converting to HTML: ansi2html < screenshot.txt > screenshot.html
#   - Converting to SVG: using tools like ansi-to-svg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMOS_DIR="$PROJECT_ROOT/example/demos"

SPECIFIC_DEMO=""
OUTPUT_DIR=""
TIMEOUT_SEC=3

usage() {
    cat <<'EOF'
Usage: capture_demo_frames.sh [OPTIONS]

Capture initial frames from MIAOU demos.

Options:
    --demo NAME         Only capture specific demo
    --output-dir DIR    Output directory (default: each demo's directory)
    --timeout SEC       Timeout in seconds (default: 3)
    --list              List available demos
    -h, --help          Show this help

Output:
    Creates screenshot.txt (ANSI text) in each demo directory.

Examples:
    ./tools/capture_demo_frames.sh
    ./tools/capture_demo_frames.sh --demo button
    ./tools/capture_demo_frames.sh --output-dir screenshots/
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --demo)
            SPECIFIC_DEMO="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT_SEC="$2"
            shift 2
            ;;
        --list)
            find "$DEMOS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

get_demos() {
    if [[ -n "$SPECIFIC_DEMO" ]]; then
        echo "$SPECIFIC_DEMO"
    else
        find "$DEMOS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
    fi
}

capture_demo() {
    local demo_name="$1"
    local demo_dir="$DEMOS_DIR/$demo_name"
    local exe="$PROJECT_ROOT/_build/default/example/demos/${demo_name}/main.exe"

    if [[ ! -x "$exe" ]]; then
        echo "  Skip: $demo_name (not built)" >&2
        return 1
    fi

    local output_path
    if [[ -n "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
        output_path="$OUTPUT_DIR/${demo_name}.txt"
    else
        output_path="$demo_dir/screenshot.txt"
    fi

    local frames_file
    frames_file=$(mktemp --suffix=.jsonl)

    echo "Capturing: $demo_name"

    # Run demo with frame capture enabled, auto-quit after timeout
    export MIAOU_DEBUG_FRAME_CAPTURE=1
    export MIAOU_DEBUG_FRAME_CAPTURE_PATH="$frames_file"
    export TERM=xterm-256color

    # Run in background and kill after timeout
    timeout "${TIMEOUT_SEC}s" "$exe" </dev/null >/dev/null 2>&1 || true

    # Extract first frame from JSONL
    if [[ -s "$frames_file" ]]; then
        # Parse JSON and extract frame content
        # Format: {"timestamp": ..., "size": {...}, "frame": "..."}
        local frame
        frame=$(head -1 "$frames_file" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('frame', ''))
except:
    pass
" 2>/dev/null || true)

        if [[ -n "$frame" ]]; then
            # Unescape the frame content
            echo -e "$frame" > "$output_path"
            echo "  -> $output_path"
            rm -f "$frames_file"
            return 0
        fi
    fi

    echo "  Warning: no frame captured for $demo_name" >&2
    rm -f "$frames_file"
    return 1
}

main() {
    if [[ ! -d "$PROJECT_ROOT/_build" ]]; then
        echo "Error: Project not built. Run 'dune build' first." >&2
        exit 1
    fi

    local success=0
    local failed=0

    echo "Capturing demo frames..."
    echo ""

    while read -r demo; do
        if capture_demo "$demo"; then
            ((success++))
        else
            ((failed++))
        fi
    done < <(get_demos)

    echo ""
    echo "Done: $success captured, $failed failed"
}

main
