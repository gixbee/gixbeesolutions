# Gixbee — Docker commands
# Usage: make <command>
# Switch backend: make backend-rust  or  make backend-nest

BACKEND_IMPL ?= rust
export COMPOSE_PROFILES := $(BACKEND_IMPL)
COMPOSE := docker compose -f docker-compose.yml

.PHONY: help dev dev-bg prod down logs ps shell-backend shell-db migrate clean backend-nest backend-rust logs-backend

help:
	@echo ""
	@echo "  Gixbee Docker Commands"
	@echo "  ─────────────────────────────────────────"
	@echo "  BACKEND_IMPL=nest|rust  (current: $(BACKEND_IMPL))"
	@echo "  make dev          Start in development mode (hot reload)"
	@echo "  make prod         Start in production mode"
	@echo "  make backend-nest Flip to NestJS backend"
	@echo "  make backend-rust Flip to Rust backend"
	@echo "  make down         Stop all containers"
	@echo "  make logs         Tail logs from all containers"
	@echo "  make ps           Show running containers"
	@echo "  make shell-backend  Open shell inside active backend container"
	@echo "  make shell-db       Open psql inside postgres container"
	@echo "  make migrate      Run TypeORM migrations manually (nest only)"
	@echo "  make clean        Remove containers, volumes, images"
	@echo ""

dev:
	$(COMPOSE) -f docker-compose.dev.yml up --build

dev-bg:
	$(COMPOSE) -f docker-compose.dev.yml up --build -d

prod:
	$(COMPOSE) up --build -d

backend-nest:
	@echo "BACKEND_IMPL=nest" > .env.backend
	$(COMPOSE) -f docker-compose.dev.yml --profile nest up --build -d backend api_balancer admin

backend-rust:
	@echo "BACKEND_IMPL=rust" > .env.backend
	$(COMPOSE) -f docker-compose.dev.yml --profile rust up --build -d backend_rust api_balancer admin

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

logs-backend:
ifeq ($(BACKEND_IMPL),rust)
	$(COMPOSE) logs -f backend_rust
else
	$(COMPOSE) logs -f backend
endif

logs-db:
	$(COMPOSE) logs -f postgres

ps:
	$(COMPOSE) ps

shell-backend:
ifeq ($(BACKEND_IMPL),rust)
	docker exec -it $$(docker ps -qf "name=backend_rust") sh
else
	docker exec -it $$(docker ps -qf "name=backend") sh
endif

shell-db:
	docker exec -it gixbee_postgres psql -U postgres -d gixbee_db

shell-redis:
	docker exec -it gixbee_redis redis-cli

migrate:
	docker exec $$(docker ps -qf "name=backend") node dist/node_modules/typeorm/cli migration:run

clean:
	$(COMPOSE) down -v --rmi local
	@echo "Removed containers, volumes, and local images"
