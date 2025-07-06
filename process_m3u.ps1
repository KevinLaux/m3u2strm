# M3U to STRM Converter for Docker Container
# Runs indefinitely, processing IPTV VOD content every hour

# Get environment variable for M3U URL
$urlm3u = $env:urlm3u

# Validate required environment variable
if (-not $urlm3u) {
    Write-Host "ERROR: Environment variable 'urlm3u' is required but not set."
    exit 1
}

# Define the media volume paths
$moviesPath = "/media/movies"
$tvShowsPath = "/media/tv shows"
$logPath = "/app/logs"
$processedFilesPath = "/app/processed_files.txt"

# Ensure the directories exist
@($moviesPath, $tvShowsPath, $logPath) | ForEach-Object {
    if (-not (Test-Path -Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Host "Created directory: $_"
    }
}

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path "$logPath/process.log" -Value $logMessage
}

# Function to sanitize filename
function Get-SafeFilename {
    param([string]$filename)
    $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
    $sanitized = $filename -replace "[$invalidChars]", ''
    return $sanitized.Trim()
}

# Function to parse M3U entries
function Parse-M3UEntry {
    param([string]$extinf, [string]$url)
    
    $result = @{
        Title = ""
        Group = ""
        TvgName = ""
        Url = $url
        IsMovie = $false
        IsTvShow = $false
        Season = ""
        Episode = ""
        SeriesName = ""
    }
    
    # Extract tvg-name
    if ($extinf -match 'tvg-name="([^"]*)"') {
        $result.TvgName = $matches[1]
    }
    
    # Extract group-title
    if ($extinf -match 'group-title="([^"]*)"') {
        $result.Group = $matches[1]
    }
    
    # Extract title (after last comma)
    if ($extinf -match ',(.+)$') {
        $result.Title = $matches[1].Trim()
    }
    
    # Check if it's a movie or TV show based on URL patterns
    if ($url -match '/movie[s]?/' -or $result.Group -match 'movie' -or $result.Title -match 'movie') {
        $result.IsMovie = $true
    } elseif ($url -match '/series/' -or $result.Group -match 'series' -or $result.Title -match 'S\d+E\d+') {
        $result.IsTvShow = $true
        
        # Extract season and episode information
        if ($result.Title -match 'S(\d+)E(\d+)') {
            $result.Season = $matches[1]
            $result.Episode = $matches[2]
            $result.SeriesName = ($result.Title -replace 'S\d+E\d+.*$', '').Trim()
        }
    }
    
    return $result
}

# Function to process TV shows
function Process-TvShow {
    param([object]$entry)
    
    if (-not $entry.SeriesName -or -not $entry.Season -or -not $entry.Episode) {
        Write-Log "Skipping TV show entry due to missing season/episode info: $($entry.Title)" "WARN"
        return
    }
    
    $safeSeriesName = Get-SafeFilename $entry.SeriesName
    $seasonFormatted = "Season {0:D2}" -f [int]$entry.Season
    $episodeFormatted = "S{0:D2}E{1:D2}" -f [int]$entry.Season, [int]$entry.Episode
    
    $seriesDir = Join-Path $tvShowsPath $safeSeriesName
    $seasonDir = Join-Path $seriesDir $seasonFormatted
    $strmFile = Join-Path $seasonDir "$safeSeriesName $episodeFormatted.strm"
    
    # Create directory structure
    if (-not (Test-Path -Path $seasonDir)) {
        New-Item -ItemType Directory -Path $seasonDir -Force | Out-Null
    }
    
    # Write .strm file
    try {
        $entry.Url | Out-File -FilePath $strmFile -Encoding UTF8 -Force
        Write-Log "Created TV show STRM: $strmFile"
        return $strmFile
    } catch {
        Write-Log "Failed to create TV show STRM file: $strmFile - $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Function to process Movies
function Process-Movie {
    param([object]$entry)
    
    $safeMovieName = Get-SafeFilename $entry.Title
    if (-not $safeMovieName) {
        Write-Log "Skipping movie entry due to invalid title: $($entry.Title)" "WARN"
        return
    }
    
    $movieDir = Join-Path $moviesPath $safeMovieName
    $strmFile = Join-Path $movieDir "$safeMovieName.strm"
    
    # Create directory structure
    if (-not (Test-Path -Path $movieDir)) {
        New-Item -ItemType Directory -Path $movieDir -Force | Out-Null
    }
    
    # Write .strm file
    try {
        $entry.Url | Out-File -FilePath $strmFile -Encoding UTF8 -Force
        Write-Log "Created movie STRM: $strmFile"
        return $strmFile
    } catch {
        Write-Log "Failed to create movie STRM file: $strmFile - $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Function to download and process M3U file
function Process-M3UFile {
    Write-Log "Starting M3U processing cycle"
    
    try {
        # Download M3U file
        $m3uFilePath = "/app/playlist.m3u"
        Write-Log "Downloading M3U file from: $urlm3u"
        Invoke-WebRequest -Uri $urlm3u -OutFile $m3uFilePath -TimeoutSec 30
        
        # Read and process M3U content
        $m3uContent = Get-Content -Path $m3uFilePath
        $currentProcessedFiles = @()
        
        Write-Log "Processing M3U file with $($m3uContent.Count) lines"
        
        for ($i = 0; $i -lt $m3uContent.Count; $i++) {
            $line = $m3uContent[$i]
            
            # Look for EXTINF lines
            if ($line -match '^#EXTINF:') {
                $extinf = $line
                $url = ""
                
                # Get the next non-empty line as URL
                for ($j = $i + 1; $j -lt $m3uContent.Count; $j++) {
                    if ($m3uContent[$j] -and -not $m3uContent[$j].StartsWith('#')) {
                        $url = $m3uContent[$j].Trim()
                        break
                    }
                }
                
                        if ($url) {
                            # Only process video files
                            if ($url -match '\.(mp4|mkv|avi|m4v)$') {
                                $entry = Parse-M3UEntry -extinf $extinf -url $url
                                
                                $processedFile = $null
                                if ($entry.IsMovie) {
                                    $processedFile = Process-Movie -entry $entry
                                } elseif ($entry.IsTvShow) {
                                    $processedFile = Process-TvShow -entry $entry
                                }
                                
                                if ($processedFile) {
                                    $currentProcessedFiles += $processedFile
                                }
                            }
                        }
            }
        }
        
        # Save list of processed files
        if ($currentProcessedFiles.Count -gt 0) {
            $currentProcessedFiles | Out-File -FilePath $processedFilesPath -Encoding UTF8
        }
        
        # Clean up orphaned files
        Remove-OrphanedFiles -currentFiles $currentProcessedFiles
        
        Write-Log "M3U processing cycle completed. Processed $($currentProcessedFiles.Count) files."
        
    } catch {
        Write-Log "Error processing M3U file: $($_.Exception.Message)" "ERROR"
        Write-Log "Error details: $($_.Exception.ToString())" "ERROR"
    }
}

# Function to remove orphaned .strm files
function Remove-OrphanedFiles {
    param([array]$currentFiles)
    
    Write-Log "Checking for orphaned files to remove"
    
    # Get all existing .strm files
    $existingFiles = @()
    if (Test-Path $moviesPath) {
        $existingFiles += Get-ChildItem -Path $moviesPath -Filter "*.strm" -Recurse | ForEach-Object { $_.FullName }
    }
    if (Test-Path $tvShowsPath) {
        $existingFiles += Get-ChildItem -Path $tvShowsPath -Filter "*.strm" -Recurse | ForEach-Object { $_.FullName }
    }
    
    # Remove files that are no longer in the current M3U
    foreach ($existingFile in $existingFiles) {
        if ($existingFile -notin $currentFiles) {
            try {
                Remove-Item -Path $existingFile -Force
                Write-Log "Removed orphaned file: $existingFile"
            } catch {
                Write-Log "Failed to remove orphaned file: $existingFile - $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    # Remove empty directories
    @($moviesPath, $tvShowsPath) | ForEach-Object {
        if (Test-Path $_) {
            Get-ChildItem -Path $_ -Directory -Recurse | Where-Object { 
                (Get-ChildItem -Path $_.FullName -File).Count -eq 0 
            } | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force
                    Write-Log "Removed empty directory: $($_.FullName)"
                } catch {
                    Write-Log "Failed to remove empty directory: $($_.FullName) - $($_.Exception.Message)" "ERROR"
                }
            }
        }
    }
}

# Main execution loop
Write-Log "M3U to STRM Converter started"
Write-Log "M3U URL: $urlm3u"
Write-Log "Movies path: $moviesPath"
Write-Log "TV Shows path: $tvShowsPath"

while ($true) {
    try {
        Process-M3UFile
        Write-Log "Waiting 1 hour before next processing cycle"
        Start-Sleep -Seconds 3600  # 1 hour
    } catch {
        Write-Log "Unexpected error in main loop: $($_.Exception.Message)" "ERROR"
        Write-Log "Waiting 5 minutes before retry"
        Start-Sleep -Seconds 300   # 5 minutes
    }
}
