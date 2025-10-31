# --- watcher/Dockerfile ---
FROM python:3.11-slim

WORKDIR /app

# Copy dependencies and install them
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the watcher script
COPY watcher.py .

# Make sure script is executable
RUN chmod +x watcher.py

# Ensure unbuffered output for real-time logging
# "-u" forces unbuffered stdout/stderr so docker logs -f works live
CMD ["python", "-u", "watcher.py"]
