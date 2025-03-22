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
    
    # Build commit message
    $commitMsg = (Split-Path $File -Leaf)
    
    # Add line numbers
    if ($lineNums) {
        $commitMsg += " lines: $lineNums"
    } else {
        $commitMsg += " lines: Unknown"
    }
    
    # Check if this is a replacement (both additions and removals)
    if ($diffOutput -match "^\+" -and $diffOutput -match "^-") {
        $commitMsg += " | Type: Replacement"
    } elseif ($diffOutput -match "^\+") {
        $commitMsg += " | Type: Insertion"
    } elseif ($diffOutput -match "^-") {
        $commitMsg += " | Type: Deletion"
    } else {
        $commitMsg += " | Type: Unknown Change"
    }
    
    return $commitMsg
}

# Function to get user input for commit reason
function Get-CommitReason {
    Write-Host "Enter the reason for the commit:" -ForegroundColor Yellow
    $reason = Read-Host
    return $reason
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
        
        # Get user input for commit reason
        $commitReason = Get-CommitReason
        
        # Append user reason to commit message
        $commitMessage += " | Reason: $commitReason"
        
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
        
        # Get user input for commit reason
        $commitReason = Get-CommitReason
        
        # Add the file to git staging
        git add $relPath
        
        # Commit
        git commit -m "$relPath | Type: New File | Reason: $commitReason"
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
    
    # Get user input for commit reason
    $commitReason = Get-CommitReason
    
    # Stage the deletion
    git rm $relPath
    
    # Commit the deletion
    git commit -m "$relPath | Type: Deleted File | Reason: $commitReason"
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
