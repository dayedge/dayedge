#!/bin/bash
# The frameworks each Packages/DayEdge target may import — what Package.swift's
# target dependencies can't say. `make lint` runs it; prints each offending
# import and fails if there is one.
set -euo pipefail
cd "$(dirname "$0")/../Packages/DayEdge/Sources"

status=0

# allow <target> <allowed module>... : any other import in the target fails.
allow() {
    local target=$1; shift
    local pattern
    pattern=":[0-9]+:(@testable )?import ($(IFS='|'; echo "$*"))$"
    while IFS= read -r line; do
        echo "$target may not: $line"
        status=1
    done < <(grep -rnE '^(@testable )?import ' "$target" --include='*.swift' | grep -vE "$pattern" || true)
}

# Shared values and contracts: no UI, no EventKit, no index.
allow Domain Foundation Observation
# The system and the index behind Domain's contracts: no UI.
allow Platform Foundation Observation AppKit EventKit CoreLocation CalendarIndex CalendarIndexEventKit Domain
# What every feature draws with: no EventKit, no index, never Platform.
allow UI Foundation Observation SwiftUI AppKit CoreGraphics CoreText CoreImage QuartzCore Domain
# Features: Domain and UI only — no Platform, no other feature.
allow Agenda Foundation Observation SwiftUI AppKit CoreGraphics Domain UI
allow Tasks Foundation Observation SwiftUI AppKit CoreGraphics Domain UI
allow Intelligence Foundation Observation SwiftUI AppKit CoreGraphics JavaScriptCore FoundationModels Tachikoma Domain UI

exit $status
