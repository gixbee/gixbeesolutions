# ─── Stage 1: Builder ────────────────────────────────────────────────────────
FROM rust:bookworm AS builder

WORKDIR /app

# Cache dependencies
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src

COPY . .
RUN touch src/main.rs && cargo build --release

# ─── Stage 2: Runner ─────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runner

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -r -s /bin/false gixbee

WORKDIR /app

COPY --from=builder /app/target/release/gixbee-backend /app/gixbee-backend

RUN mkdir -p /app/uploads && chown -R gixbee:gixbee /app

USER gixbee

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/readyz || exit 1

CMD ["/app/gixbee-backend"]
