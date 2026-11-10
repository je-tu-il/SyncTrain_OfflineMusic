FROM python:3.11-slim
WORKDIR /app
COPY . /app
EXPOSE 8094
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8094/health')" || exit 1
CMD ["python", "server.py"]
