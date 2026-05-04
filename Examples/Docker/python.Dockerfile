# 🐍 Python Production Dockerfile (Modern)

FROM python:3.11-slim

# GÜVENLİK: Python için optimizasyonlar
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# GÜVENLİK: Root olmayan kullanıcı
RUN addgroup --system appgroup && adduser --system appuser --ingroup appgroup
USER appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["python", "app.py"]
