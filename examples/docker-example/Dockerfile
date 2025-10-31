FROM python:3.11-slim

# Serve from /www (no /app anywhere)
WORKDIR /www

# Copy site content into the working dir
COPY www/ .

# Put server.py at /
COPY server.py /server.py

EXPOSE 8080
CMD ["python", "/server.py"]
