#!/bin/bash

# ==========================================
# Docker Audit Logic - Change Tracker Engine
# ==========================================

compare_configs() {
    local container=$1
    local current_xml=$2
    local last_xml=$3
    local diff_output=""

    # 1. TRACK TOP-LEVEL TAGS (Preserving original XML casing)
    # We use perl to 'slurp' the file and handle tags that span multiple lines (like Overview)
    local tags=("WebUI" "Banner" "Icon" "ExtraParams" "PostArgs" "Overview" "Category")
    
    for tag in "${tags[@]}"; do
        curr_val=$(perl -0777 -ne "print \"\$1\" if /<$tag>(.*?)<\/$tag>/s" "$current_xml" | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g')
        prev_val=$(perl -0777 -ne "print \"\$1\" if /<$tag>(.*?)<\/$tag>/s" "$last_xml" | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g')

        if [ "$curr_val" != "$prev_val" ]; then
            # Clean up extra whitespace/newlines for the report display
            curr_clean=$(echo "$curr_val" | xargs)
            prev_clean=$(echo "$prev_val" | xargs)
            
            # The label now uses the exact tag name from the array (e.g., WebUI)
            diff_output+="< $tag: ${prev_clean:-[empty]}\n"
            diff_output+="> $tag: ${curr_clean:-[empty]}\n"
        fi
    done

    # 2. TRACK CONFIG BLOCKS (Ports, Paths, Env Vars)
    # Extract config lines, ignoring the internal 'ID' which changes automatically
    current_cfg=$(sed -n '/<Config /,/<\/Config>/p' "$current_xml" | grep -v 'Name="ID"' | sort)
    last_cfg=$(sed -n '/<Config /,/<\/Config>/p' "$last_xml" | grep -v 'Name="ID"' | sort)

    if [ "$current_cfg" != "$last_cfg" ]; then
        while read -r line; do
            # Extract Type and Name (e.g., Variable and IMAGE CACHING)
            type=$(echo "$line" | grep -oP 'Type="\K[^"]+')
            name=$(echo "$line" | grep -oP 'Name="\K[^"]+')
            value=$(echo "$line" | sed -n 's/.*>\([^<]*\)<.*/\1/p')
            
            # Labels now use original casing from the XML (e.g., Variable)
            label="$type ($name)"

            if echo "$line" | grep -q "^<"; then
                diff_output+="< $label: $value\n"
            elif echo "$line" | grep -q "^>"; then
                diff_output+="> $label: $value\n"
            fi
        done <<< "$(diff <(echo "$last_cfg") <(echo "$current_cfg") | grep -E "^[<>]")"
    fi

    # Output the final findings to the main script
    echo -e "$diff_output"
}