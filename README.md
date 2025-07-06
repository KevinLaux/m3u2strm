# M3U to STRM Converter

This project provides a Docker container that converts IPTV VOD content from an M3U playlist into `.strm` files, which can be imported into media servers like Plex, Emby, or Jellyfin. The container runs continuously, updating content every hour.

## Features

- **Continuous Operation**: Runs indefinitely, checking for new content every hour
- **Automatic Cleanup**: Removes `.strm` files for content no longer in the playlist
- **Smart Parsing**: Handles M3U files with proper EXTINF parsing
- **Media Server Compatible**: Creates `.strm` files compatible with Plex, Emby, and Jellyfin
- **Organized Structure**: 
  - Movies: `/media/movies/Movie Name/Movie Name.strm`
  - TV Shows: `/media/tv shows/Series Name/Season 01/Series Name S01E01.strm`
- **Error Handling**: Robust error handling with logging and retry mechanisms
- **Health Monitoring**: Built-in health checks for container monitoring

## Requirements

- Docker installed on your system
- An M3U playlist URL containing IPTV VOD content
- Writable storage for the media volume

## Quick Start

1. **Build the Docker image:**
   ```bash
   docker build -t m3u2strm .
   ```

2. **Run the container:**
   ```bash
   docker run -d \
     --name m3u2strm \
     -e urlm3u="YOUR_M3U_PLAYLIST_URL" \
     -v /path/to/your/media:/media \
     --restart unless-stopped \
     m3u2strm
   ```

3. **Check the logs:**
   ```bash
   docker logs m3u2strm
   ```

## Configuration

### Environment Variables

- `urlm3u` (required): The URL of your M3U playlist

### Volume Mounts

- `/media`: Mount point for your media files
  - `/media/movies`: Contains movie `.strm` files
  - `/media/tv shows`: Contains TV show `.strm` files

## Usage Examples

### Basic Usage
```bash
docker run -d \
  --name m3u2strm \
  -e urlm3u="http://example.com/playlist.m3u" \
  -v /home/user/media:/media \
  m3u2strm
```

### With Docker Compose
```yaml
version: '3.8'
services:
  m3u2strm:
    build: .
    container_name: m3u2strm
    environment:
      - urlm3u=http://example.com/playlist.m3u
    volumes:
      - /home/user/media:/media
    restart: unless-stopped
```

### Integration with Media Servers

#### Plex
1. Add `/path/to/your/media/movies` as a Movie library
2. Add `/path/to/your/media/tv shows` as a TV Show library
3. Ensure Plex has read access to the mounted volume

#### Jellyfin/Emby
1. Add the media folders in your server settings
2. Configure the libraries to scan for new content automatically

## File Structure

The container creates the following structure:

```
/media/
├── movies/
│   └── Movie Name/
│       └── Movie Name.strm
└── tv shows/
    └── Series Name/
        └── Season 01/
            └── Series Name S01E01.strm
```

## How It Works

1. **Download**: Downloads the M3U playlist from the provided URL
2. **Parse**: Parses EXTINF entries to extract metadata (title, group, season/episode info)
3. **Filter**: Filters for video files (mp4, mkv, avi, m4v)
4. **Categorize**: Determines if content is a movie or TV show based on URL patterns and metadata
5. **Create**: Creates appropriate directory structure and `.strm` files
6. **Cleanup**: Removes orphaned files that are no longer in the playlist
7. **Repeat**: Waits 1 hour and repeats the process

## M3U Format Support

The parser handles standard M3U format with EXTINF entries:

```
#EXTINF:-1 tvg-name="Movie Name" group-title="Movies",Movie Name
http://example.com/movies/movie.mp4

#EXTINF:-1 tvg-name="Series Name S01E01" group-title="TV Series",Series Name S01E01
http://example.com/series/episode.mkv
```

## Logging

Logs are written to `/app/logs/process.log` inside the container. To access logs:

```bash
# View live logs
docker logs -f m3u2strm

# Access log file directly
docker exec m3u2strm cat /app/logs/process.log
```

## Troubleshooting

### Common Issues

1. **Container stops immediately**: Check that the `urlm3u` environment variable is set
2. **No files created**: Verify the M3U URL is accessible and contains VOD content
3. **Permission denied**: Ensure the mounted volume has write permissions
4. **Files not showing in media server**: Check that the media server has read access to the volume

### Health Check

The container includes a health check that verifies the log file exists:

```bash
docker health m3u2strm
```

### Debug Mode

To run the container interactively for debugging:

```bash
docker run -it \
  -e urlm3u="YOUR_M3U_PLAYLIST_URL" \
  -v /path/to/your/media:/media \
  m3u2strm
```

## Performance Considerations

- **Update Frequency**: The container checks for updates every hour by default
- **Storage**: Each `.strm` file is very small (just contains a URL)
- **Network**: Downloads the M3U file once per hour
- **CPU**: Minimal CPU usage during processing

## Security Notes

- The container runs as root by default for directory creation
- URLs in `.strm` files are stored in plain text
- Consider using a reverse proxy if your M3U URL contains sensitive information

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:
1. Check the logs for error messages
2. Verify your M3U URL is accessible
3. Ensure proper volume permissions
4. Create an issue with relevant logs and configuration
