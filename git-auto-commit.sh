#!/bin/bash
# Exit if no directory provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <directory_to_watch>"
    exit 1
fi
# Directory to watch
WATCH_DIR=$(cd "$1" && pwd)
# Function to get diff and extract changed/deleted lines
get_diff_info() {
    local file="$1"
    local diff_output
    
    # Get the diff output with line numbers
    diff_output=$(git diff -U0 -- "$file")
    
    # Extract line numbers of modified lines
    local line_nums=$(echo "$diff_output" | grep -E "^@@" | sed -E 's/^@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*/\1-\3/')
    
    # Extract actual content changes (added, removed, and modified lines)
    local added_lines=$(echo "$diff_output" | grep "^+" | grep -v "^+++" | sed 's/^+//' | head -3)
    local removed_lines=$(echo "$diff_output" | grep "^-" | grep -v "^---" | sed 's/^-//' | head -3)
    
    # Build commit message
    commit_msg="$(basename "$file")"
    
    # Add line numbers
    if [ -n "$line_nums" ]; then
        commit_msg+=" lines: $line_nums"
    else
        commit_msg+=" lines: Unknown"
    fi
    
    # Add inserted content
    if [ -n "$added_lines" ]; then
        # Clean up and limit length
        added_content=$(echo "$added_lines" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ ${#added_content} -gt 50 ]; then
            added_content="${added_content:0:47}..."
        fi
        commit_msg+=" | Inserted: $added_content"
    else
        commit_msg+=" | Inserted: None"
    fi
    
    # Add removed content
    if [ -n "$removed_lines" ]; then
        # Clean up and limit length
        removed_content=$(echo "$removed_lines" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ ${#removed_content} -gt 50 ]; then
            removed_content="${removed_content:0:47}..."
        fi
        commit_msg+=" | Removed: $removed_content"
    else
        commit_msg+=" | Removed: None"
    fi
    
    # Check if this is a replacement (both additions and removals)
    if [ -n "$added_lines" ] && [ -n "$removed_lines" ]; then
        commit_msg+=" | Type: Replacement"
    elif [ -n "$added_lines" ]; then
        commit_msg+=" | Type: Insertion"
    elif [ -n "$removed_lines" ]; then
        commit_msg+=" | Type: Deletion"
    else
        commit_msg+=" | Type: Unknown Change"
    fi
    
    echo "$commit_msg"
    
    echo "$commit_msg"
}
# Check if fswatch is installed
if ! command -v fswatch > /dev/null; then
    echo "fswatch not found. Please install it with: brew install fswatch"
    exit 1
fi
# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Not in a git repository. Please run this script from within a git repo."
    exit 1
fi
echo "Watching $WATCH_DIR for changes. Press Ctrl+C to stop."
# Change to the directory we want to watch
cd "$WATCH_DIR" || exit 1
# Watch for file changes using fswatch (macOS compatible)
fswatch -0 -e "\.git/" -e ".*~$" -e "4913" . | while read -d "" -r file_event; do
    # Get full path
    full_path="$WATCH_DIR/$file_event"
    echo "Detected change in: $file_event"
    
    # Skip . files and directories
    if [[ "$file_event" == .* ]] || [[ -d "$file_event" ]]; then
        echo "Skipping hidden file or directory"
        continue
    fi
    
    # Add any file that exists
    if [ -f "$file_event" ]; then
        # Get commit message based on changes before adding
        commit_message=$(get_diff_info "$file_event")
        
        # Add the file to git staging
        git add "$file_event"
        
        # Commit only if there are changes to commit
        if git diff --staged --quiet; then
            echo "No changes to commit for $file_event"
        else
            git commit -m "$commit_message"
            echo "Committed changes in $file_event"
        fi
    else
        echo "File not found: $file_event"
    fi
done
