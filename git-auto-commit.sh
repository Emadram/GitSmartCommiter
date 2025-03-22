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

    # Check if file is new
    if ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
        echo "$(basename "$file") | Type: New File"
        return
    fi

    # Get the diff output with line numbers
    diff_output=$(git diff -U0 -- "$file")
    
    # Extract line numbers of modified lines
    local line_nums=$(echo "$diff_output" | grep -E "^@@" | sed -E 's/^@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*/\1-\3/')
    
    # Build commit message
    commit_msg="$(basename "$file")"
    
    # Add line numbers
    if [ -n "$line_nums" ]; then
        commit_msg+=" lines: $line_nums"
    else
        commit_msg+=" lines: Unknown"
    fi
    
    # Check change type
    if echo "$diff_output" | grep -q "^+" && echo "$diff_output" | grep -q "^-"; then
        commit_msg+=" | Type: Replacement"
    elif echo "$diff_output" | grep -q "^+"; then
        commit_msg+=" | Type: Insertion"
    elif echo "$diff_output" | grep -q "^-"; then
        commit_msg+=" | Type: Deletion"
    else
        commit_msg+=" | Type: Unknown Change"
    fi
    
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
    
    # Get absolute path
    full_path=$(realpath "$file_event")
    echo "Detected change in: $file_event"
    
    # Skip hidden files and directories
    if [[ "$file_event" == .* ]] || [[ -d "$file_event" ]]; then
        echo "Skipping hidden file or directory"
        continue
    fi
    
    # Skip if no actual changes
    if git diff --quiet -- "$file_event"; then
        echo "No changes to commit for $file_event"
        continue
    fi
    
    # Get commit message
    commit_message=$(get_diff_info "$file_event")
    
    # Prompt user for commit reason
    echo "Enter the reason for the commit (press Enter twice to finish):"
    commit_reason=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        commit_reason+="$line"$'\n'
    done
    
    # Append user reason to commit message
    commit_message+=" | Reason: $commit_reason"
    
    # Add the file to git staging
    git add "$file_event"
    
    # Commit changes
    git commit -m "$commit_message"
    echo "Committed changes in $file_event"

done
