# ---- Base build stage ----
FROM node:20-bookworm-slim AS base

LABEL maintainer="Eero Ruohola <eero.ruohola@shuup.com>"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        python3 \
        python3-pip \
        python3-dev \
        libpangocairo-1.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Set workdir
WORKDIR /app

# Copy only requirements first (better Docker caching)
COPY requirements-tests.txt setup.py /app/

# Editable flag (default 0 = use pip install shuup, 1 = install from source)
ARG editable=0

# Install dependencies based on mode
RUN if [ "$editable" -eq 1 ]; then \
        pip3 install --no-cache-dir -r requirements-tests.txt && \
        python3 setup.py build_resources; \
    else \
        pip3 install --no-cache-dir shuup; \
    fi

# Copy rest of the source
COPY . /app

# Initialize Shuup DB + admin user
RUN python3 -m shuup_workbench migrate && \
    python3 -m shuup_workbench shuup_init && \
    echo '\
from django.contrib.auth import get_user_model\n\
from django.db import IntegrityError\n\
try:\n\
    get_user_model().objects.create_superuser("admin", "admin@admin.com", "admin")\n\
except IntegrityError:\n\
    pass\n' | python3 -m shuup_workbench shell


# ---- Production image ----
FROM python:3.11-slim-bookworm AS runtime

# Install only required system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpangocairo-1.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed Python packages from builder
COPY --from=base /usr/local/lib/python3.11 /usr/local/lib/python3.11
COPY --from=base /usr/local/bin /usr/local/bin

# Copy app source
COPY --from=base /app /app

# Expose Shuup port
EXPOSE 8000

CMD ["python3", "-m", "shuup_workbench", "runserver", "0.0.0.0:8000"]
