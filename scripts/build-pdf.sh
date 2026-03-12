#!/usr/bin/env bash
set -euo pipefail

BOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${BOOK_DIR}/src"
OUT_DIR="${BOOK_DIR}/out"
PDF_FILE="${OUT_DIR}/the-autonomous-stack.pdf"

mkdir -p "${OUT_DIR}"

# Check dependencies
if ! command -v pandoc &>/dev/null; then
    echo "ERROR: pandoc not found. Install with:"
    echo "  sudo pacman -S pandoc"
    exit 1
fi

if ! command -v xelatex &>/dev/null; then
    echo "ERROR: xelatex not found. Install with:"
    echo "  sudo pacman -S texlive-xetex texlive-fontsextra"
    exit 1
fi

# Ordered chapter list
CHAPTERS=(
    "${SRC_DIR}/part-1-philosophy/ch01-the-dossier-principle.md"
    "${SRC_DIR}/part-1-philosophy/ch02-screaming-architecture.md"
    "${SRC_DIR}/part-1-philosophy/ch03-vertical-slicing.md"
    "${SRC_DIR}/part-1-philosophy/ch04-events-as-facts.md"
    "${SRC_DIR}/part-2-infrastructure/ch05-a-masterless-mesh.md"
    "${SRC_DIR}/part-2-infrastructure/ch06-the-event-store.md"
    "${SRC_DIR}/part-2-infrastructure/ch07-cqrs-without-the-ceremony.md"
    "${SRC_DIR}/part-2-infrastructure/ch08-bit-flags-and-status-machines.md"
    "${SRC_DIR}/part-3-intelligence/ch09-neuroevolution.md"
    "${SRC_DIR}/part-3-intelligence/ch10-tweann-on-the-beam.md"
    "${SRC_DIR}/part-3-intelligence/ch11-llm-orchestration.md"
    "${SRC_DIR}/part-3-intelligence/ch12-the-human-gate.md"
    "${SRC_DIR}/part-3-intelligence/ch13-the-hybrid-mind.md"
    "${SRC_DIR}/part-4-platform/ch14-the-venture-lifecycle.md"
    "${SRC_DIR}/part-4-platform/ch15-plugin-architecture.md"
    "${SRC_DIR}/part-4-platform/ch16-martha-studio.md"
    "${SRC_DIR}/part-4-platform/ch17-the-agent-relay.md"
    "${SRC_DIR}/part-5-synthesis/ch18-decentralized-development.md"
    "${SRC_DIR}/part-5-synthesis/ch19-the-autonomous-stack.md"
    "${SRC_DIR}/part-5-synthesis/ch20-what-comes-next.md"
    "${SRC_DIR}/about-the-author.md"
)

# Verify all chapters exist
for ch in "${CHAPTERS[@]}"; do
    if [[ ! -f "${ch}" ]]; then
        echo "ERROR: Missing chapter: ${ch}"
        exit 1
    fi
done

echo "Building PDF from ${#CHAPTERS[@]} chapters..."

# Build with pandoc + xelatex
pandoc \
    --pdf-engine=xelatex \
    --from=markdown+yaml_metadata_block \
    --toc \
    --toc-depth=2 \
    --number-sections \
    --resource-path="${SRC_DIR}:${SRC_DIR}/assets:${SRC_DIR}/part-1-philosophy:${SRC_DIR}/part-2-infrastructure:${SRC_DIR}/part-3-intelligence:${SRC_DIR}/part-4-platform:${SRC_DIR}/part-5-synthesis" \
    --metadata-file="${BOOK_DIR}/metadata.yaml" \
    -V documentclass=report \
    -V geometry:margin=1in \
    -V fontsize=11pt \
    -V mainfont="DejaVu Serif" \
    -V sansfont="DejaVu Sans" \
    -V monofont="DejaVu Sans Mono" \
    -V monofontoptions="Scale=0.85" \
    -V linkcolor=NavyBlue \
    -V urlcolor=NavyBlue \
    -V toccolor=NavyBlue \
    -V header-includes='\usepackage{fvextra}\DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,commandchars=\\\{\}}' \
    -o "${PDF_FILE}" \
    "${CHAPTERS[@]}"

echo "PDF generated: ${PDF_FILE}"
echo "Size: $(du -h "${PDF_FILE}" | cut -f1)"
