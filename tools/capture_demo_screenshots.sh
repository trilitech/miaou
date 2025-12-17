#!/usr/bin/env bash
#
# Capture screenshots for all MIAOU demos
#
# This script captures a single frame from each demo and converts it to SVG/PNG
# for inclusion in documentation.
#
# Prerequisites:
#   - asciinema (for recording)
#   - svg-term-cli (npm install -g svg-term-cli) OR agg (for PNG)
#   - The project must be built: dune build
#
# Usage:
#   ./tools/capture_demo_screenshots.sh [--format svg|png] [--output-dir DIR]
#
# The script will:
#   1. Launch each demo
#   2. Capture the initial frame after a short delay
#   3. Send 'q' or 'Esc' to quit
#   4. Convert the recording to SVG or PNG
#   5. Place the image in the demo's directory as screenshot.svg/png

set -euo pipefail

# Configuration
FORMAT="svg"
OUTPUT_DIR=""
DELAY_MS=1500  # Time to wait for demo to render (ms)
TERM_COLS=100
TERM_ROWS=30

usage() {
    cat <<'EOF'
Usage: capture_demo_screenshots.sh [OPTIONS]

Capture screenshots for all MIAOU demos.

Options:
    --format FORMAT     Output format: svg (default) or png
    --output-dir DIR    Output directory (default: each demo's directory)
    --delay MS          Delay before capture in ms (default: 1500)
    --cols N            Terminal columns (default: 100)
    --rows N            Terminal rows (default: 30)
    --demo NAME         Only capture specific demo (e.g., "button")
    --list              List available demos and exit
    -h, --help          Show this help

Prerequisites:
    - dune build (project must be built)
    - asciinema
    - For SVG: svg-term-cli (npm install -g svg-term-cli)
    - For PNG: agg (cargo install agg) or asciinema-agg

Examples:
    # Capture all demos as SVG
    ./tools/capture_demo_screenshots.sh

    # Capture specific demo as PNG
    ./tools/capture_demo_screenshots.sh --format png --demo button

    # List available demos
    ./tools/capture_demo_screenshots.sh --list
EOF
}

# Parse arguments
SPECIFIC_DEMO=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --delay)
            DELAY_MS="$2"
            shift 2
            ;;
        --cols)
            TERM_COLS="$2"
            shift 2
            ;;
        --rows)
            TERM_ROWS="$2"
            shift 2
            ;;
        --demo)
            SPECIFIC_DEMO="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate format
if [[ "$FORMAT" != "svg" && "$FORMAT" != "png" ]]; then
    echo "Error: format must be 'svg' or 'png'" >&2
    exit 1
fi

# Find project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMOS_DIR="$PROJECT_ROOT/example/demos"

# Get list of demos
get_demos() {
    find "$DEMOS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
}

# List demos if requested
if $LIST_ONLY; then
    echo "Available demos:"
    get_demos | while read -r demo; do
        echo "  - $demo"
    done
    exit 0
fi

# Check prerequisites
check_prereqs() {
    local missing=()

    if ! command -v asciinema &>/dev/null; then
        missing+=("asciinema")
    fi

    if [[ "$FORMAT" == "svg" ]]; then
        if ! command -v svg-term &>/dev/null; then
            missing+=("svg-term-cli (npm install -g svg-term-cli)")
        fi
    elif [[ "$FORMAT" == "png" ]]; then
        if ! command -v agg &>/dev/null; then
            missing+=("agg (cargo install agg)")
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing prerequisites:" >&2
        for dep in "${missing[@]}"; do
            echo "  - $dep" >&2
        done
        exit 1
    fi

    # Check if project is built
    if [[ ! -d "$PROJECT_ROOT/_build" ]]; then
        echo "Error: Project not built. Run 'dune build' first." >&2
        exit 1
    fi
}

# Capture a single demo
capture_demo() {
    local demo_name="$1"
    local demo_dir="$DEMOS_DIR/$demo_name"
    local output_path

    if [[ -n "$OUTPUT_DIR" ]]; then
        output_path="$OUTPUT_DIR/${demo_name}.${FORMAT}"
    else
        output_path="$demo_dir/screenshot.${FORMAT}"
    fi

    local cast_file
    cast_file=$(mktemp --suffix=.cast)

    echo "Capturing: $demo_name"

    # Find the executable
    local exe="$PROJECT_ROOT/_build/default/example/demos/${demo_name}/main.exe"
    if [[ ! -x "$exe" ]]; then
        echo "  Warning: executable not found: $exe (skipping)" >&2
        return 1
    fi

    # Record with asciinema using expect-like automation
    # We use a timeout and send quit key after delay
    local script_file
    script_file=$(mktemp --suffix=.sh)

    cat > "$script_file" <<SCRIPT
#!/usr/bin/env bash
export TERM=xterm-256color
"$exe" &
PID=\$!
sleep ${DELAY_MS}e-3
# Send Escape key to quit
echo -ne '\x1b' > /proc/\$PID/fd/0 2>/dev/null || true
sleep 0.2
kill \$PID 2>/dev/null || true
wait \$PID 2>/dev/null || true
SCRIPT
    chmod +x "$script_file"

    # Use script command to capture with proper TTY
    # asciinema needs a real TTY, so we use a timeout-based approach
    timeout 5s asciinema rec \
        --cols "$TERM_COLS" \
        --rows "$TERM_ROWS" \
        --overwrite \
        --command "timeout 3s '$exe' || true" \
        "$cast_file" 2>/dev/null || true

    rm -f "$script_file"

    # Check if recording was created
    if [[ ! -s "$cast_file" ]]; then
        echo "  Warning: failed to capture $demo_name" >&2
        rm -f "$cast_file"
        return 1
    fi

    # Convert to output format
    if [[ "$FORMAT" == "svg" ]]; then
        svg-term --in "$cast_file" --out "$output_path" \
            --window \
            --no-cursor \
            --at 1000 \
            --width "$TERM_COLS" \
            --height "$TERM_ROWS" 2>/dev/null
    elif [[ "$FORMAT" == "png" ]]; then
        agg "$cast_file" "$output_path" \
            --cols "$TERM_COLS" \
            --rows "$TERM_ROWS" \
            --last-frame 2>/dev/null
    fi

    rm -f "$cast_file"

    if [[ -f "$output_path" ]]; then
        echo "  -> $output_path"
        return 0
    else
        echo "  Warning: conversion failed for $demo_name" >&2
        return 1
    fi
}

# Main
main() {
    check_prereqs

    # Create output directory if specified
    if [[ -n "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
    fi

    local demos
    if [[ -n "$SPECIFIC_DEMO" ]]; then
        if [[ ! -d "$DEMOS_DIR/$SPECIFIC_DEMO" ]]; then
            echo "Error: demo '$SPECIFIC_DEMO' not found" >&2
            echo "Use --list to see available demos" >&2
            exit 1
        fi
        demos="$SPECIFIC_DEMO"
    else
        demos=$(get_demos)
    fi

    local success=0
    local failed=0

    echo "Capturing demo screenshots (format: $FORMAT)"
    echo "Terminal size: ${TERM_COLS}x${TERM_ROWS}"
    echo ""

    while read -r demo; do
        if capture_demo "$demo"; then
            ((success++))
        else
            ((failed++))
        fi
    done <<< "$demos"

    echo ""
    echo "Done: $success captured, $failed failed"
}

main
