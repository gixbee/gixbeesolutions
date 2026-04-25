# Gixbee — Docker commands
# Usage: make <command>

.PHONY: help dev prod down logs ps shell-backend shell-db migrate seed clean

help:
	@echo ""
	@echo "  Gixbee Docker Commands"
	@echo "  ─────────────────────────────────────────"
	@echo "  make dev          Start in development mode (hot reload)"
	@echo "  make prod         Start in production mode"
	@echo "  make down         Stop all containers"
	@echo "  make logs         Tail logs from all containers"
	@echo "  make ps           Show running containers"
	@echo "  make shell-backend  Open shell inside backend container"
	@echo "  make shell-db       Open psql inside postgres container"
	@echo "  make migrate      Run TypeORM migrations manually"
	@echo "  make clean        Remove containers, volumes, images"
	@echo ""

# ── Development ──────────────────────────────────────────────────────────────
dev:
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build

dev-bg:
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d

# ── Production ───────────────────────────────────────────────────────────────
prod:
	docker-compose up --build -d

# ── Stop ─────────────────────────────────────────────────────────────────────
down:
	docker-compose down

# ── Logs ─────────────────────────────────────────────────────────────────────
logs:
	docker-compose logs -f

logs-backend:
	docker-compose logs -f backend

logs-db:
	docker-compose logs -f postgres

# ── Status ───────────────────────────────────────────────────────────────────
ps:
	docker-compose ps

# ── Shells ───────────────────────────────────────────────────────────────────
shell-backend:
	docker exec -it gixbee_backend sh

shell-db:
	docker exec -it gixbee_postgres psql -U postgres -d gixbee

shell-redis:
	docker exec -it gixbee_redis redis-cli -a $$(grep REDIS_PASSWORD .env | cut -d '=' -f2)

# ── Database ─────────────────────────────────────────────────────────────────
migrate:
	docker exec gixbee_backend node dist/node_modules/typeorm/cli migration:run

# ── Clean ─────────────────────────────────────────────────────────────────────
clean:
	docker-compose down -v --rmi local
	@echo "Removed containers, volumes, and local images"
