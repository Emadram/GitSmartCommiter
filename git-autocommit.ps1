param(
    [Parameter(Mandatory=$true)]
    [string]$WatchDir
)

# Convert to absolute path
$WatchDir = (Resolve-Path $WatchDir).Path

# Function to get diff info
function Get-DiffInfo {
    param(
        [string]$File
    )
    
    # Get the diff output with line numbers
    $diffOutput = git diff -U0 -- $File
    
    # Extract line numbers of modified lines
    $lineNums = $diffOutput | Select-String -Pattern "^@@" | ForEach-Object {
        $_ -replace "^@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*", '$1-$3'
    } | Select-Object -First 1
    
    # Extract actual content changes (added and removed lines)
    $addedLines = $diffOutput | Select-String -Pattern "^\+" | Where-Object { $_ -notmatch "^\+\+\+" } | 
                  ForEach-Object { $_ -replace "^\+", "" } | Select-Object -First 3
    
    $removedLines = $diffOutput | Select-String -Pattern "^-" | Where-Object { $_ -notmatch "^---" } | 
                    ForEach-Object { $_ -replace "^-", "" } | Select-Object -First 3
    
    # Build commit message
    $commitMsg = (Split-Path $File -Leaf)
    
    # Add line numbers
    if ($lineNums) {
        $commitMsg += " lines: $lineNums"
    } else {
        $commitMsg += " lines: Unknown"
    }
    
    # Add inserted content
    if ($addedLines) {
        $addedContent = ($addedLines -join " ").Trim()
        if ($addedContent.Length -gt 50) {
            $addedContent = $addedContent.Substring(0, 47) + "..."
        }
        $commitMsg += " | Inserted: $addedContent"
    } else {
        $commitMsg += " | Inserted: None"
    }
    
    # Add removed content
    if ($removedLines) {
        $removedContent = ($removedLines -join " ").Trim()
        if ($removedContent.Length -gt 50) {
            $removedContent = $removedContent.Substring(0, 47) + "..."
        }
        $commitMsg += " | Removed: $removedContent"
    } else {
        $commitMsg += " | Removed: None"
    }
    
    # Check if this is a replacement (both additions and removals)
    if ($addedLines -and $removedLines) {
        $commitMsg += " | Type: Replacement"
    } elseif ($addedLines) {
        $commitMsg += " | Type: Insertion"
    } elseif ($removedLines) {
        $commitMsg += " | Type: Deletion"
    } else {
        $commitMsg += " | Type: Unknown Change"
    }
    
    return $commitMsg
}

# Check if we're in a git repository
if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
    Write-Output "Not in a git repository. Please run this script from within a git repo."
    exit 1
}

# Change to the directory we want to watch
Set-Location $WatchDir

Write-Output "Watching $WatchDir for changes. Press Ctrl+C to stop."

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchDir
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite

# Define events
$onChange = Register-ObjectEvent -InputObject $watcher -EventName Changed -Action {
    $filePath = $Event.SourceEventArgs.FullPath
    $relPath = $filePath.Substring($WatchDir.Length + 1)
    
    # Skip git files and hidden files
    if ($relPath -like ".git\*" -or $relPath -like ".*" -or (Test-Path $filePath -PathType Container)) {
        return
    }
    
    if (Test-Path $filePath -PathType Leaf) {
        Write-Output "Detected change in: $relPath"
        
        # Get commit message based on changes before adding
        $commitMessage = Get-DiffInfo $relPath
        
        # Add the file to git staging
        git add $relPath
        
        # Check if there are staged changes
        $hasChanges = -not [string]::IsNullOrEmpty((git diff --name-only --cached))
        
        if ($hasChanges) {
            git commit -m $commitMessage
            Write-Output "Committed changes in $relPath"
        } else {
            Write-Output "No changes to commit for $relPath"
        }
    } else {
        Write-Output "File not found: $relPath"
    }
}

$onCreated = Register-ObjectEvent -InputObject $watcher -EventName Created -Action {
    $filePath = $Event.SourceEventArgs.FullPath
    $relPath = $filePath.Substring($WatchDir.Length + 1)
    
    # Skip git files and hidden files
    if ($relPath -like ".git\*" -or $relPath -like ".*" -or (Test-Path $filePath -PathType Container)) {
        return
    }
    
    if (Test-Path $filePath -PathType Leaf) {
        Write-Output "Detected new file: $relPath"
        
        # Add the file to git staging
        git add $relPath
        
        # Commit
        git commit -m "$relPath | Type: New File"
        Write-Output "Committed new file $relPath"
    }
}

$onDeleted = Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action {
    $filePath = $Event.SourceEventArgs.FullPath
    $relPath = $filePath.Substring($WatchDir.Length + 1)
    
    # Skip git files and hidden files
    if ($relPath -like ".git\*" -or $relPath -like ".*") {
        return
    }
    
    Write-Output "Detected deleted file: $relPath"
    
    # Stage the deletion
    git rm $relPath
    
    # Commit the deletion
    git commit -m "$relPath | Type: Deleted File"
    Write-Output "Committed deletion of $relPath"
}

try {
    Write-Output "Watching for changes (press CTRL+C to exit)..."
    while ($true) { Start-Sleep -Seconds 1 }
} finally {
    # Clean up event registrations when script is stopped
    Unregister-Event -SourceIdentifier $onChange.Name
    Unregister-Event -SourceIdentifier $onCreated.Name
    Unregister-Event -SourceIdentifier $onDeleted.Name
}
