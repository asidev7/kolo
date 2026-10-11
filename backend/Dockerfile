# Image de production de l'API KOLO.
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY manage.py ./
COPY kolo ./kolo
COPY apps ./apps
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && useradd --system --uid 10001 --no-create-home kolo
USER kolo

EXPOSE 8000
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "kolo.wsgi:application", "--bind", "0.0.0.0:8000", \
     "--workers", "3", "--timeout", "30", "--max-requests", "2000", \
     "--max-requests-jitter", "200", "--no-control-socket"]
