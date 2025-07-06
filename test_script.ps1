# Test script to validate the enhanced M3U processing
param([string]$TestUrl = "")

# Set test environment
$env:urlm3u = "http://test.com/test.m3u"

# Load the main processing script functions
. ./process_m3u.ps1

# Test the parsing functions
Write-Host "Testing M3U parsing functions..."

# Test cases based on the actual M3U content
$testCases = @(
    @{
        extinf = '#EXTINF:-1 tvg-id="" tvg-name="EN - To Kill a War Machine (2025)" tvg-logo="https://image.tmdb.org/t/p/w600_and_h900_bestv2/likjAbXCgtuYP42SlwwacIlpF3l.jpg" group-title="VOD - NEW ADDED [EN]",EN - To Kill a War Machine (2025)'
        url = 'http://example.com/movie.mp4'
        expected = 'Movie'
    },
    @{
        extinf = '#EXTINF:-1 tvg-id="" tvg-name="4K - Thunderbolts* (2025)" tvg-logo="https://image.tmdb.org/t/p/w600_and_h900_bestv2/hBH50Mkcrc4m8x73CovLmY7vBx1.jpg" group-title="VOD - ENGLISH 4K",4K - Thunderbolts* (2025)'
        url = 'http://example.com/movie.mp4'
        expected = 'Movie with 4K'
    },
    @{
        extinf = '#EXTINF:-1 tvg-id="" tvg-name="D+ - Star Wars: Visions S01 E01" tvg-logo="https://image.tmdb.org/t/p/w185/2cio9Ojjzp0m8mqckhRYyvG7E7R.jpg" group-title="SRS - DISNEY+ KIDS",D+ - Star Wars: Visions S01 E01'
        url = 'http://example.com/series.mp4'
        expected = 'TV Series'
    },
    @{
        extinf = '#EXTINF:-1 tvg-id="" tvg-name="UK - BBC 1 UHD" tvg-logo="http://103.176.90.118/picons/logos/UK/BBC-1.png" group-title="|UK| GENERAL",UK - BBC 1 UHD'
        url = 'http://example.com/live.ts'
        expected = 'Live TV (should be skipped)'
    }
)

Write-Host "Running test cases..."
foreach ($testCase in $testCases) {
    Write-Host "`nTesting: $($testCase.expected)"
    Write-Host "Input: $($testCase.extinf)"
    
    $result = Parse-M3UEntry -extinf $testCase.extinf -url $testCase.url
    
    Write-Host "Results:"
    Write-Host "  Title: $($result.Title)"
    Write-Host "  Clean Title: $($result.CleanTitle)"
    Write-Host "  Group: $($result.Group)"
    Write-Host "  Is VOD: $($result.IsVOD)"
    Write-Host "  Is Movie: $($result.IsMovie)"
    Write-Host "  Is TV Show: $($result.IsTvShow)"
    Write-Host "  Is 4K: $($result.Is4K)"
    Write-Host "  Quality: $($result.Quality)"
    Write-Host "  Year: $($result.Year)"
    if ($result.IsTvShow) {
        Write-Host "  Series: $($result.SeriesName)"
        Write-Host "  Season: $($result.Season)"
        Write-Host "  Episode: $($result.Episode)"
    }
}

Write-Host "`nTesting quality filtering..."
$lowQualityTests = @(
    "Movie HDCAM Quality",
    "Series CAM Rip",
    "4K - Good Movie (2025)",
    "EN - Another Movie (2024)"
)

foreach ($testTitle in $lowQualityTests) {
    $isLowQuality = Test-IsLowQuality -title $testTitle
    Write-Host "$testTitle : $(if ($isLowQuality) { 'SKIP (Low Quality)' } else { 'PROCESS' })"
}

Write-Host "`nTesting language filtering..."
$languageTests = @(
    "EN - English Movie (2025)",
    "FR - French Movie (2025)",
    "DE - German Movie (2025)",
    "Regular Movie Title (2025)"
)

foreach ($testTitle in $languageTests) {
    $isNonEnglish = Test-IsNonEnglish -title $testTitle
    Write-Host "$testTitle : $(if ($isNonEnglish) { 'SKIP (Non-English)' } else { 'PROCESS' })"
}

Write-Host "`nTest completed!"
