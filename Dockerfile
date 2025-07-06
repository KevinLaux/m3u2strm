# Use the PowerShell image as the base image
FROM mcr.microsoft.com/powershell:latest

# Install necessary packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/logs /media/movies "/media/tv shows"

# Copy the script into the container
COPY process_m3u.ps1 /app/process_m3u.ps1

# Make the script executable
RUN chmod +x /app/process_m3u.ps1

# Create a volume for media files
VOLUME ["/media"]

# Set environment variables with defaults
ENV urlm3u=""

# Health check to ensure the container is running properly
HEALTHCHECK --interval=30m --timeout=10s --start-period=5s --retries=3 \
    CMD test -f /app/logs/process.log || exit 1

# Set the entrypoint to PowerShell and the script
ENTRYPOINT ["pwsh", "-File", "/app/process_m3u.ps1"]
