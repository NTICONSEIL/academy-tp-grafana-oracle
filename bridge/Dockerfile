FROM python:3.12-slim

WORKDIR /app

# Dépendances système pour cx_Oracle / oracledb
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libaio1 curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["python", "app.py"]
