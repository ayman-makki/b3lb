.PHONY: help start stop restart status logs shell db-shell redis-shell migrate makemigrations createsuperuser test clean reset build

# Docker Compose file
COMPOSE_FILE := docker-compose.local.yml
COMPOSE := docker compose -f $(COMPOSE_FILE)

# Service names
FRONTEND := frontend
POSTGRES := postgres
REDIS := redis
CELERY_BEAT := celery-beat
CELERY_WORKER := celery-worker

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

##@ Help

help: ## Display this help message
	@echo "B3LB Local Development Makefile"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(GREEN)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Docker Compose Management

start: ## Start all services
	@echo "$(GREEN)Starting B3LB services...$(NC)"
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)Warning: .env file not found. Copying from .env.local...$(NC)"; \
		cp .env.local .env; \
	fi
	$(COMPOSE) up -d
	@echo "$(GREEN)Services started! Waiting for health checks...$(NC)"
	@sleep 5
	@$(COMPOSE) ps
	@echo ""
	@echo "$(GREEN)Access the application:$(NC)"
	@echo "  Django Admin:  http://localhost:8000/admin/"
	@echo "  API Health:    http://localhost:8000/b3lb/ping"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  make migrate         # Run database migrations"
	@echo "  make createsuperuser # Create admin user"
	@echo "  make logs            # View logs"

stop: ## Stop all services
	@echo "$(YELLOW)Stopping B3LB services...$(NC)"
	$(COMPOSE) stop
	@echo "$(GREEN)Services stopped!$(NC)"

down: ## Stop and remove all containers
	@echo "$(YELLOW)Stopping and removing B3LB containers...$(NC)"
	$(COMPOSE) down
	@echo "$(GREEN)Containers removed!$(NC)"

restart: ## Restart all services
	@echo "$(YELLOW)Restarting B3LB services...$(NC)"
	$(COMPOSE) restart
	@echo "$(GREEN)Services restarted!$(NC)"

status: ## Show service status
	@$(COMPOSE) ps

logs: ## Show logs for all services (use 'make logs-frontend', 'make logs-celery', etc. for specific services)
	$(COMPOSE) logs -f

logs-frontend: ## Show frontend logs
	$(COMPOSE) logs -f $(FRONTEND)

logs-celery: ## Show Celery worker logs
	$(COMPOSE) logs -f $(CELERY_WORKER)

logs-beat: ## Show Celery beat logs
	$(COMPOSE) logs -f $(CELERY_BEAT)

logs-postgres: ## Show PostgreSQL logs
	$(COMPOSE) logs -f $(POSTGRES)

logs-redis: ## Show Redis logs
	$(COMPOSE) logs -f $(REDIS)

##@ Django Management

shell: ## Open Django shell
	@echo "$(GREEN)Opening Django shell...$(NC)"
	$(COMPOSE) exec $(FRONTEND) ./manage.py shell

shell-plus: ## Open Django shell_plus (if available)
	@echo "$(GREEN)Opening Django shell_plus...$(NC)"
	$(COMPOSE) exec $(FRONTEND) ./manage.py shell_plus

bash: ## Open bash shell in frontend container
	@echo "$(GREEN)Opening bash shell in frontend container...$(NC)"
	$(COMPOSE) exec $(FRONTEND) /bin/bash

makemigrations: ## Create new Django migrations
	@echo "$(GREEN)Creating Django migrations...$(NC)"
	$(COMPOSE) exec -u root $(FRONTEND) ./manage.py makemigrations
	@echo "$(YELLOW)Fixing permissions on new migration files...$(NC)"
	@sudo chown -R $(shell id -u):$(shell id -g) rest/migrations/ 2>/dev/null || true
	@echo "$(GREEN)Migrations created!$(NC)"

migrate: ## Apply Django migrations
	@echo "$(GREEN)Applying Django migrations...$(NC)"
	$(COMPOSE) exec $(FRONTEND) ./manage.py migrate
	@echo "$(GREEN)Migrations applied!$(NC)"

showmigrations: ## Show migration status
	@echo "$(GREEN)Migration status:$(NC)"
	$(COMPOSE) exec $(FRONTEND) ./manage.py showmigrations

createsuperuser: ## Create Django superuser
	@echo "$(GREEN)Creating Django superuser...$(NC)"
	$(COMPOSE) exec $(FRONTEND) ./manage.py createsuperuser

collectstatic: ## Collect static files
	@echo "$(GREEN)Collecting static files...$(NC)"
	$(COMPOSE) exec $(FRONTEND) ./manage.py collectstatic --noinput

##@ Database Management

db-shell: ## Open PostgreSQL shell
	@echo "$(GREEN)Opening PostgreSQL shell...$(NC)"
	$(COMPOSE) exec $(POSTGRES) psql -U b3lb_dev -d b3lb_dev

db-backup: ## Backup database to ./backups/
	@echo "$(GREEN)Backing up database...$(NC)"
	@mkdir -p backups
	$(COMPOSE) exec -T $(POSTGRES) pg_dump -U b3lb_dev b3lb_dev > backups/b3lb_dev_$$(date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)Database backed up to backups/$(NC)"

db-restore: ## Restore database from backup (use: make db-restore FILE=backups/filename.sql)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: Please specify FILE=backups/filename.sql$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Restoring database from $(FILE)...$(NC)"
	$(COMPOSE) exec -T $(POSTGRES) psql -U b3lb_dev -d b3lb_dev < $(FILE)
	@echo "$(GREEN)Database restored!$(NC)"

##@ Redis Management

redis-shell: ## Open Redis CLI
	@echo "$(GREEN)Opening Redis CLI...$(NC)"
	$(COMPOSE) exec $(REDIS) redis-cli -a dev_redis_password

redis-flush: ## Flush all Redis databases (WARNING: Deletes all cache data)
	@echo "$(RED)WARNING: This will delete all Redis data!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(YELLOW)Flushing Redis...$(NC)"; \
		$(COMPOSE) exec $(REDIS) redis-cli -a dev_redis_password FLUSHALL; \
		echo "$(GREEN)Redis flushed!$(NC)"; \
	else \
		echo "$(GREEN)Cancelled.$(NC)"; \
	fi

##@ Testing

test: ## Run Django tests
	@echo "$(GREEN)Running Django tests...$(NC)"
	$(COMPOSE) exec $(FRONTEND) ./manage.py test

test-coverage: ## Run tests with coverage report
	@echo "$(GREEN)Running tests with coverage...$(NC)"
	$(COMPOSE) exec $(FRONTEND) coverage run --source='.' ./manage.py test
	$(COMPOSE) exec $(FRONTEND) coverage report
	$(COMPOSE) exec $(FRONTEND) coverage html
	@echo "$(GREEN)Coverage report generated in htmlcov/$(NC)"

##@ Celery Management

celery-status: ## Show Celery worker status
	@echo "$(GREEN)Celery worker status:$(NC)"
	$(COMPOSE) exec $(FRONTEND) celery -A b3lb inspect active
	@echo ""
	$(COMPOSE) exec $(FRONTEND) celery -A b3lb inspect stats

celery-purge: ## Purge all Celery tasks from queue
	@echo "$(RED)WARNING: This will delete all pending tasks!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(YELLOW)Purging Celery queue...$(NC)"; \
		$(COMPOSE) exec $(FRONTEND) celery -A b3lb purge -f; \
		echo "$(GREEN)Queue purged!$(NC)"; \
	else \
		echo "$(GREEN)Cancelled.$(NC)"; \
	fi

##@ Cleanup

clean: ## Remove all containers, keep volumes
	@echo "$(YELLOW)Removing containers...$(NC)"
	$(COMPOSE) down
	@echo "$(GREEN)Cleanup complete! (Volumes preserved)$(NC)"

clean-volumes: ## Remove containers and volumes (WARNING: Deletes all data)
	@echo "$(RED)WARNING: This will delete all data including database!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(YELLOW)Removing containers and volumes...$(NC)"; \
		$(COMPOSE) down -v; \
		rm -rf media/* recordings/*; \
		echo "$(GREEN)Complete cleanup done!$(NC)"; \
	else \
		echo "$(GREEN)Cancelled.$(NC)"; \
	fi

reset: clean-volumes start migrate createsuperuser ## Complete reset: remove all data and start fresh

##@ Development

build: ## Build/rebuild Docker images
	@echo "$(GREEN)Building Docker images...$(NC)"
	$(COMPOSE) build
	@echo "$(GREEN)Build complete!$(NC)"

pull: ## Pull latest Docker images
	@echo "$(GREEN)Pulling latest Docker images...$(NC)"
	$(COMPOSE) pull
	@echo "$(GREEN)Images updated!$(NC)"

setup: ## Initial setup (creates .env, starts services, runs migrations)
	@echo "$(GREEN)Setting up B3LB local development environment...$(NC)"
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)Creating .env file...$(NC)"; \
		cp .env.local .env; \
	fi
	@$(MAKE) start
	@echo "$(YELLOW)Waiting for services to be healthy...$(NC)"
	@sleep 10
	@$(MAKE) migrate
	@echo ""
	@echo "$(GREEN)Setup complete!$(NC)"
	@echo ""
	@echo "$(YELLOW)Next step: Create superuser$(NC)"
	@echo "  make createsuperuser"

restart-frontend: ## Restart only the frontend service
	@echo "$(YELLOW)Restarting frontend...$(NC)"
	$(COMPOSE) restart $(FRONTEND)
	@echo "$(GREEN)Frontend restarted!$(NC)"

restart-celery: ## Restart Celery worker
	@echo "$(YELLOW)Restarting Celery worker...$(NC)"
	$(COMPOSE) restart $(CELERY_WORKER)
	@echo "$(GREEN)Celery worker restarted!$(NC)"

##@ Utilities

ps: status ## Alias for 'status'

fix-permissions: ## Fix file permissions (fixes Docker permission issues)
	@echo "$(GREEN)Fixing file permissions...$(NC)"
	@echo "$(YELLOW)This will change ownership of project files to your user$(NC)"
	sudo chown -R $(shell id -u):$(shell id -g) . || \
		echo "$(RED)Note: If sudo fails, run manually: sudo chown -R $$(id -u):$$(id -g) .$(NC)"
	@echo "$(GREEN)Permissions fixed!$(NC)"
	@echo "$(YELLOW)You can now run: make makemigrations$(NC)"

fix-permissions-docker: ## Fix permissions from inside Docker container
	@echo "$(GREEN)Fixing permissions from inside container...$(NC)"
	$(COMPOSE) exec -u root $(FRONTEND) chown -R 1000:1000 /usr/src/app
	@echo "$(GREEN)Permissions fixed!$(NC)"

exec: ## Execute command in frontend container (use: make exec CMD="command")
	@if [ -z "$(CMD)" ]; then \
		echo "$(RED)Error: Please specify CMD=\"your command\"$(NC)"; \
		exit 1; \
	fi
	$(COMPOSE) exec $(FRONTEND) $(CMD)

health: ## Check health of all services
	@echo "$(GREEN)Checking service health...$(NC)"
	@echo ""
	@echo "Frontend:"
	@curl -s http://localhost:8000/b3lb/ping || echo "$(RED)Frontend not responding$(NC)"
	@echo ""
	@echo "PostgreSQL:"
	@$(COMPOSE) exec -T $(POSTGRES) pg_isready -U b3lb_dev || echo "$(RED)PostgreSQL not ready$(NC)"
	@echo ""
	@echo "Redis:"
	@$(COMPOSE) exec -T $(REDIS) redis-cli -a dev_redis_password ping || echo "$(RED)Redis not responding$(NC)"
	@echo ""

info: ## Show environment information
	@echo "$(GREEN)B3LB Local Development Environment$(NC)"
	@echo ""
	@echo "Docker Compose file: $(COMPOSE_FILE)"
	@echo "Services:"
	@$(COMPOSE) config --services
	@echo ""
	@echo "Ports:"
	@echo "  Frontend:   http://localhost:8000"
	@echo "  PostgreSQL: localhost:5432"
	@echo "  Redis:      localhost:6379"
	@echo ""
	@echo "Volumes:"
	@$(COMPOSE) config --volumes
	@echo ""
	@if [ -f .env ]; then \
		echo "Environment: .env file exists"; \
	else \
		echo "$(YELLOW)Environment: .env file NOT found$(NC)"; \
	fi
