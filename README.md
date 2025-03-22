# Git Auto-Commit for Windows

This script automatically watches a directory for changes and commits them to git with descriptive commit messages.

## Requirements

- Git for Windows
- PowerShell 5.0+
- Windows Terminal (recommended)

## Installation

1. Save the script as `git-autocommit.ps1`
2. Make sure you're in a git repository

## Usage

1. Open PowerShell in your git repository
2. Run the script with the directory you want to watch:

```powershell
.\git-autocommit.ps1 -WatchDir "C:\path\to\your\project"
```

3. The script will watch for file changes and automatically commit them with descriptive messages + Your reason which will be prompted from you!
4. Press Ctrl+C to stop watching

## Features

- Automatically commits file changes as they happen
- Creates descriptive commit messages that include:
  - Line numbers of changes
  - Sample of inserted content
  - Sample of removed content
  - Type of change (Insertion, Deletion, Replacement)
- Handles new files and deleted files
- Skips hidden files and directories

## How It Works

The script uses PowerShell's `FileSystemWatcher` class to monitor file system events in real-time. When a file change is detected:

1. The script extracts the line numbers and content that changed using `git diff`
2. It creates a descriptive commit message with details about the changes
3. The changed file is added to git staging
4. The changes are committed with the generated message

## Troubleshooting

- Make sure you're running the script from within a git repository
- If files aren't being detected, check that they're not in your `.gitignore`
- If you get permission errors, try running PowerShell as administrator

-------------------------------------------------------------------------------
# Git Auto-Commit for macOS

This script automatically watches a directory for changes and commits them to Git with descriptive commit messages.

## Requirements

- Git
- fswatch (`brew install fswatch`)
- Bash or Zsh shell

## Installation

1. Save the script as `git-autocommit.sh`
2. Make the script executable:

```bash
chmod +x git-autocommit.sh
```

## Usage

1. Open Terminal in your git repository
2. Run the script with the directory you want to watch:

```bash
./git-autocommit.sh /path/to/your/project
```

3. The script will watch for file changes and automatically commit them with descriptive messages + Your reason which will be prompted from you!
4. Press Ctrl+C to stop watching

## Features

- Automatically commits file changes as they happen
- Creates descriptive commit messages that include:
  - Line numbers of changes
  - Sample of inserted content
  - Sample of removed content
  - Type of change (Insertion, Deletion, Replacement)
- Skips hidden files and directories
- Compatible with macOS file system events

## How It Works

The script uses `fswatch` to monitor file system events in real-time. When a file change is detected:

1. The script extracts the line numbers and content that changed using `git diff`
2. It creates a descriptive commit message with details about the changes
3. The changed file is added to git staging
4. The changes are committed with the generated message

## Troubleshooting

- If you see `fswatch not found`, install it with Homebrew: `brew install fswatch`
- Make sure you're running the script from within a git repository
- If files aren't being detected, check that they're not in your `.gitignore`
