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
    
    # Build commit message
    commit_msg="$(basename "$file")"
    
    # Add line numbers
    if [ -n "$line_nums" ]; then
        commit_msg+=" lines: $line_nums"
    else
        commit_msg+=" lines: Unknown"
    fi
    
    # Check if this is a replacement (both additions and removals)
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

# Function to get user input even when in a pipe
get_commit_reason() {
    # Direct access to the terminal, bypassing the pipe's stdin
    echo "Enter the reason for the commit:" > /dev/tty
    read -r reason < /dev/tty
    echo "$reason"
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
    echo "Detected change in: $file_event"
    
    # Skip . files and directories
    if [[ "$file_event" == .* ]] || [[ -d "$file_event" ]]; then
        echo "Skipping hidden file or directory"
        continue
    fi
    
    # Make sure we have the correct path to the file
    # If file_event is a relative path, make it absolute
    if [[ "$file_event" != /* ]]; then
        file_path="$WATCH_DIR/$file_event"
    else
        file_path="$file_event"
    fi
    
    # Process the file if it exists
    if [ -f "$file_path" ]; then
        # Skip if no actual changes
        if git diff --quiet -- "$file_path"; then
            echo "No changes to commit for $file_path"
            continue
        fi
        
        # Get commit message based on changes before adding
        commit_message=$(get_diff_info "$file_path")
        
        # Get user input using our special function
        commit_reason=$(get_commit_reason)
        
        # Append user reason to commit message
        commit_message+=" | Reason: $commit_reason"
        
        # Add the file to git staging
        git add "$file_path"
        
        # Commit only if there are changes to commit
        if ! git diff --staged --quiet; then
            git commit -m "$commit_message"
            echo "Committed changes in $file_path"
            echo "Continuing to watch for changes... (Press Ctrl+C to stop)"
        else
            echo "No changes to commit for $file_path"
        fi
    else
        echo "File not found: $file_path (Maybe it was deleted?)"
    fi
done
