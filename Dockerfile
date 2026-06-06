# Dockerfile
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    socat \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Set up app directory
WORKDIR /app

# Copy requirements and install
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY run_plugin.py run_companion.py /app/
COPY akita_email /app/akita_email
COPY tests /app/tests

# Copy entrypoint script
COPY docker-entrypoint.sh /app/
RUN chmod +x /app/docker-entrypoint.sh

# Create a directory for persistent database and log files
RUN mkdir -p /app/data
VOLUME /app/data

# Default environment configurations pointing to the data volume
ENV AKITA_DB_FILE=/app/data/akita_plugin_store.db \
    AKITA_PLUGIN_LOG=/app/data/akita_plugin.log \
    AKITA_COMPANION_LOG=/app/data/akita_companion.log \
    PYTHONUNBUFFERED=1

# Use entrypoint script
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Default mode is running both processes
CMD ["both"]
