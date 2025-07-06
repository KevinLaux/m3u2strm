# M3U to STRM Converter for Docker Container
# Enhanced version with improved parsing and quality control
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

# Function to check if content is low quality (should be skipped)
function Test-IsLowQuality {
    param([string]$title)
    
    $lowQualityPatterns = @(
        'hdcam', 'HDCAM', 'cam', 'CAM', 'ts', 'TS', 'tc', 'TC', 'dvdscr', 'DVDSCR', 'screener', 'SCREENER'
    )
    
    foreach ($pattern in $lowQualityPatterns) {
        if ($title -match $pattern) {
            return $true
        }
    }
    return $false
}

# Function to check if content is non-English (should be skipped)
function Test-IsNonEnglish {
    param([string]$title)
    
    $nonEnglishPatterns = @(
        '^FR\s*-', '^DE\s*-', '^ES\s*-', '^IT\s*-', '^PT\s*-', '^RU\s*-', '^AR\s*-', '^HI\s*-', '^TR\s*-'
    )
    
    foreach ($pattern in $nonEnglishPatterns) {
        if ($title -match $pattern) {
            return $true
        }
    }
    return $false
}

# Function to clean and normalize title
function Get-NormalizedTitle {
    param([string]$title)
    
    # Remove "EN -" prefix
    $cleanTitle = $title -replace '^EN\s*-\s*', ''
    
    # Remove "4K -" prefix and note for later
    $is4K = $false
    if ($cleanTitle -match '^4K\s*-\s*(.+)$') {
        $cleanTitle = $matches[1]
        $is4K = $true
    }
    
    # Clean up any remaining prefixes/suffixes
    $cleanTitle = $cleanTitle.Trim()
    
    return @{
        Title = $cleanTitle
        Is4K = $is4K
    }
}

# Function to detect VOD content type
function Test-IsVODContent {
    param([string]$groupTitle, [string]$title)
    
    # Check for VOD group patterns
    $vodPatterns = @(
        'VOD\s*-', 'MOVIES?', 'SERIES?', 'FILMS?', 'SRS\s*-'
    )
    
    foreach ($pattern in $vodPatterns) {
        if ($groupTitle -match $pattern) {
            return $true
        }
    }
    
    # Check for individual movie/series patterns in title
    if ($title -match '\(\d{4}\)' -or $title -match 'S\d{2}E\d{2}') {
        return $true
    }
    
    return $false
}

# Enhanced function to parse M3U entries with better handling
function Parse-M3UEntry {
    param([string]$extinf, [string]$url)
    
    $result = @{
        Title = ""
        CleanTitle = ""
        Group = ""
        TvgName = ""
        Url = $url
        IsMovie = $false
        IsTvShow = $false
        Season = ""
        Episode = ""
        SeriesName = ""
        Is4K = $false
        IsVOD = $false
        Quality = ""
        Year = ""
    }
    
    # Extract tvg-name using .NET regex for better performance
    $tvgNameMatch = [System.Text.RegularExpressions.Regex]::Match($extinf, 'tvg-name="([^"]*)"')
    if ($tvgNameMatch.Success) {
        $result.TvgName = $tvgNameMatch.Groups[1].Value
    }
    
    # Extract group-title
    $groupMatch = [System.Text.RegularExpressions.Regex]::Match($extinf, 'group-title="([^"]*)"')
    if ($groupMatch.Success) {
        $result.Group = $groupMatch.Groups[1].Value
    }
    
    # Extract title (after last comma) - handle malformed entries
    $titleMatch = [System.Text.RegularExpressions.Regex]::Match($extinf, ',([^,]+)$')
    if ($titleMatch.Success) {
        $result.Title = $titleMatch.Groups[1].Value.Trim()
    } elseif ($result.TvgName) {
        # Fallback to tvg-name if title extraction fails
        $result.Title = $result.TvgName
    } else {
        # Last resort: extract anything after EXTINF
        $fallbackMatch = [System.Text.RegularExpressions.Regex]::Match($extinf, '#EXTINF[^,]*,\s*(.+)')
        if ($fallbackMatch.Success) {
            $result.Title = $fallbackMatch.Groups[1].Value.Trim()
        }
    }
    
    # Check if this is VOD content
    $result.IsVOD = Test-IsVODContent -groupTitle $result.Group -title $result.Title
    
    if (-not $result.IsVOD) {
        return $result
    }
    
    # Skip low quality content
    if (Test-IsLowQuality -title $result.Title) {
        Write-Log "Skipping low quality content: $($result.Title)" "INFO"
        return $result
    }
    
    # Skip non-English content
    if (Test-IsNonEnglish -title $result.Title) {
        Write-Log "Skipping non-English content: $($result.Title)" "INFO"
        return $result
    }
    
    # Normalize title
    $normalizedResult = Get-NormalizedTitle -title $result.Title
    $result.CleanTitle = $normalizedResult.Title
    $result.Is4K = $normalizedResult.Is4K
    
    # Extract year
    $yearMatch = [System.Text.RegularExpressions.Regex]::Match($result.CleanTitle, '\((\d{4})\)')
    if ($yearMatch.Success) {
        $result.Year = $yearMatch.Groups[1].Value
    }
    
    # Detect quality from title
    $qualityPatterns = @{
        'WEBRIP' = 'WEBRip'
        'WEB-DL' = 'WEB-DL'
        'BLURAY' = 'BluRay'
        'BDRIP' = 'BDRip'
        'DVDRIP' = 'DVDRip'
        'HDTV' = 'HDTV'
        'UHD' = 'UHD'
        'FHD' = 'FHD'
        '4K' = '4K'
    }
    
    foreach ($pattern in $qualityPatterns.Keys) {
        if ($result.CleanTitle -match $pattern) {
            $result.Quality = $qualityPatterns[$pattern]
            break
        }
    }
    
    if ($result.Is4K -and -not $result.Quality) {
        $result.Quality = '4K'
    }
    
    # Check if it's a TV show (Season/Episode pattern)
    $seasonEpisodeMatch = [System.Text.RegularExpressions.Regex]::Match($result.CleanTitle, '(.+?)\s+S(\d+)E(\d+)')
    if ($seasonEpisodeMatch.Success) {
        $result.IsTvShow = $true
        $result.SeriesName = $seasonEpisodeMatch.Groups[1].Value.Trim()
        $result.Season = $seasonEpisodeMatch.Groups[2].Value
        $result.Episode = $seasonEpisodeMatch.Groups[3].Value
    } else {
        # Alternative pattern: Series name followed by season/episode
        $altMatch = [System.Text.RegularExpressions.Regex]::Match($result.CleanTitle, '(.+?)\s+S(\d+)\s+E(\d+)')
        if ($altMatch.Success) {
            $result.IsTvShow = $true
            $result.SeriesName = $altMatch.Groups[1].Value.Trim()
            $result.Season = $altMatch.Groups[2].Value
            $result.Episode = $altMatch.Groups[3].Value
        } else {
            # Check for series in group title patterns
            if ($result.Group -match 'SRS\s*-' -or $result.Group -match 'SERIES') {
                $result.IsTvShow = $true
                # Try to extract series name from group or title
                if ($result.Title -match '^(.+?)\s+S\d+\s+E\d+') {
                    $result.SeriesName = $matches[1].Trim()
                    $seasonEpMatch = [System.Text.RegularExpressions.Regex]::Match($result.Title, 'S(\d+)\s+E(\d+)')
                    if ($seasonEpMatch.Success) {
                        $result.Season = $seasonEpMatch.Groups[1].Value
                        $result.Episode = $seasonEpMatch.Groups[2].Value
                    }
                }
            } else {
                # It's a movie
                $result.IsMovie = $true
            }
        }
    }
    
    return $result
}

# Enhanced function to process TV shows with better naming
function Process-TvShow {
    param([object]$entry)
    
    if (-not $entry.SeriesName -or -not $entry.Season -or -not $entry.Episode) {
        Write-Log "Skipping TV show entry due to missing season/episode info: $($entry.Title)" "WARN"
        return $null
    }
    
    $safeSeriesName = Get-SafeFilename $entry.SeriesName
    if (-not $safeSeriesName) {
        Write-Log "Skipping TV show entry due to invalid series name: $($entry.SeriesName)" "WARN"
        return $null
    }
    
    # Format according to Sonarr/Radarr standards
    $seasonFormatted = "Season {0:D2}" -f [int]$entry.Season
    $episodeFormatted = "S{0:D2}E{1:D2}" -f [int]$entry.Season, [int]$entry.Episode
    
    # Create filename with quality if available
    $filename = "$safeSeriesName $episodeFormatted"
    if ($entry.Quality) {
        $filename += " $($entry.Quality)"
    }
    if ($entry.Is4K) {
        $filename += " 4K"
    }
    $filename += ".strm"
    
    $seriesDir = Join-Path $tvShowsPath $safeSeriesName
    $seasonDir = Join-Path $seriesDir $seasonFormatted
    $strmFile = Join-Path $seasonDir $filename
    
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

# Enhanced function to process Movies with better naming
function Process-Movie {
    param([object]$entry)
    
    $safeMovieName = Get-SafeFilename $entry.CleanTitle
    if (-not $safeMovieName) {
        Write-Log "Skipping movie entry due to invalid title: $($entry.CleanTitle)" "WARN"
        return $null
    }
    
    # Create filename according to Sonarr/Radarr standards
    $filename = $safeMovieName
    if ($entry.Year) {
        $filename += " ($($entry.Year))"
    }
    if ($entry.Quality) {
        $filename += " $($entry.Quality)"
    }
    if ($entry.Is4K) {
        $filename += " 4K"
    }
    $filename += ".strm"
    
    # Create folder name (just the clean title with year)
    $folderName = $safeMovieName
    if ($entry.Year) {
        $folderName += " ($($entry.Year))"
    }
    
    $movieDir = Join-Path $moviesPath $folderName
    $strmFile = Join-Path $movieDir $filename
    
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

# Enhanced function to download and process M3U file with better performance
function Process-M3UFile {
    Write-Log "Starting M3U processing cycle"
    
    try {
        # Download M3U file
        $m3uFilePath = "/app/playlist.m3u"
        Write-Log "Downloading M3U file from: $urlm3u"
        
        # Use WebClient for better performance
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($urlm3u, $m3uFilePath)
        $webClient.Dispose()
        
        # Read M3U content using .NET methods for better performance
        $m3uContent = [System.IO.File]::ReadAllLines($m3uFilePath)
        $currentProcessedFiles = [System.Collections.Generic.List[string]]::new()
        
        Write-Log "Processing M3U file with $($m3uContent.Count) lines"
        
        $vodCount = 0
        $skippedCount = 0
        $processedCount = 0
        
        for ($i = 0; $i -lt $m3uContent.Count; $i++) {
            $line = $m3uContent[$i]
            
            # Look for EXTINF lines
            if ($line.StartsWith('#EXTINF:')) {
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
                    $entry = Parse-M3UEntry -extinf $extinf -url $url
                    
                    # Only process VOD content
                    if ($entry.IsVOD) {
                        $vodCount++
                        
                        # Skip if low quality or non-English
                        if ((Test-IsLowQuality -title $entry.Title) -or (Test-IsNonEnglish -title $entry.Title)) {
                            $skippedCount++
                            continue
                        }
                        
                        $processedFile = $null
                        if ($entry.IsMovie) {
                            $processedFile = Process-Movie -entry $entry
                        } elseif ($entry.IsTvShow) {
                            $processedFile = Process-TvShow -entry $entry
                        }
                        
                        if ($processedFile) {
                            $currentProcessedFiles.Add($processedFile)
                            $processedCount++
                        }
                    }
                }
            }
        }
        
        Write-Log "VOD Content Summary: Found $vodCount VOD entries, Skipped $skippedCount (quality/language), Processed $processedCount"
        
        # Save list of processed files
        if ($currentProcessedFiles.Count -gt 0) {
            [System.IO.File]::WriteAllLines($processedFilesPath, $currentProcessedFiles)
        }
        
        # Clean up orphaned files
        Remove-OrphanedFiles -currentFiles $currentProcessedFiles
        
        Write-Log "M3U processing cycle completed. Created $($currentProcessedFiles.Count) STRM files."
        
    } catch {
        Write-Log "Error processing M3U file: $($_.Exception.Message)" "ERROR"
        Write-Log "Error details: $($_.Exception.ToString())" "ERROR"
    }
}

# Enhanced function to remove orphaned .strm files
function Remove-OrphanedFiles {
    param([System.Collections.Generic.List[string]]$currentFiles)
    
    Write-Log "Checking for orphaned files to remove"
    
    # Get all existing .strm files
    $existingFiles = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $moviesPath) {
        $movieFiles = Get-ChildItem -Path $moviesPath -Filter "*.strm" -Recurse | ForEach-Object { $_.FullName }
        $existingFiles.AddRange($movieFiles)
    }
    if (Test-Path $tvShowsPath) {
        $tvFiles = Get-ChildItem -Path $tvShowsPath -Filter "*.strm" -Recurse | ForEach-Object { $_.FullName }
        $existingFiles.AddRange($tvFiles)
    }
    
    # Remove files that are no longer in the current M3U
    $removedCount = 0
    foreach ($existingFile in $existingFiles) {
        if (-not $currentFiles.Contains($existingFile)) {
            try {
                Remove-Item -Path $existingFile -Force
                Write-Log "Removed orphaned file: $existingFile"
                $removedCount++
            } catch {
                Write-Log "Failed to remove orphaned file: $existingFile - $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    # Remove empty directories
    $emptyDirsRemoved = 0
    @($moviesPath, $tvShowsPath) | ForEach-Object {
        if (Test-Path $_) {
            Get-ChildItem -Path $_ -Directory -Recurse | Where-Object { 
                (Get-ChildItem -Path $_.FullName -File).Count -eq 0 
            } | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force
                    Write-Log "Removed empty directory: $($_.FullName)"
                    $emptyDirsRemoved++
                } catch {
                    Write-Log "Failed to remove empty directory: $($_.FullName) - $($_.Exception.Message)" "ERROR"
                }
            }
        }
    }
    
    Write-Log "Cleanup completed: Removed $removedCount orphaned files and $emptyDirsRemoved empty directories"
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
