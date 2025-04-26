# QOR ADMIN MAKEFILE

# Note:
# Configs were largely parsed from hard coded values found throughout the test infra, but mostly .travis.yml

# TODO/WIP:
# Some guesswork here, need to confirm we match expected config/db settings. 
# The original QOR tests might expect specific users/passwords/db names.

# PG
POSTGRES_CONTAINER_NAME := qor_admin_test_postgres
POSTGRES_IMAGE        := postgres:13       # TODO: Tests might need older version
POSTGRES_HOST         := localhost
POSTGRES_PORT         := 5432
POSTGRES_DB           := qor_test
POSTGRES_USER         := qor
POSTGRES_PASSWORD     := qor
POSTGRES_SUPERUSER    := postgres

# MYSQL
MYSQL_CONTAINER_NAME  := qor_admin_test_mysql
MYSQL_IMAGE           := mysql:8 			# TODO: Tests might need older version
MYSQL_HOST            := 127.0.0.1
MYSQL_PORT            := 3306
MYSQL_DB              := qor_test
MYSQL_USER            := qor
MYSQL_PASSWORD        := qor
MYSQL_ROOT_PASSWORD   := rootpassword

# Go stuff
GO_TEST_TARGET        := ./...
GO_TEST_FLAGS         := -v -timeout 30m
MODVENDOR_PATTERNS    := "**/*.html **/*.js **/*.css **/*.tmpl **/*.ttf **/*.woff **/*.woff2"


.PHONY: all test test-postgres test-mysql setup setup-db-postgres setup-db-mysql clean stop-db-postgres stop-db-mysql vendor help

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  help             Show this help message"
	@echo "  setup            Start PostgreSQL and MySQL Docker containers and configure users/dbs"
	@echo "  vendor           Run go mod vendor and modvendor commands (from travis.yml)"
	@echo "  test             Setup databases, run vendoring (optional), and run Go tests against both PostgreSQL and MySQL"
	@echo "  test-postgres    Setup PostgreSQL and run Go tests against it (sets TEST_DB=postgres)"
	@echo "  test-mysql       Setup MySQL and run Go tests against it (sets TEST_DB=mysql)"
	@echo "  clean            Stop and remove testing database containers"
	@echo "  setup-db-postgres Start the PostgreSQL container and configure it"
	@echo "  setup-db-mysql    Start the MySQL container and configure it"
	@echo "  stop-db-postgres  Stop and remove the PostgreSQL container"
	@echo "  stop-db-mysql     Stop and remove the MySQL container"

all: test

# Run tests against both databases
test: setup # TODO: Tests might need vendored assets
	@$(MAKE) test-postgres
	@$(MAKE) test-mysql
	@echo "Finished running tests for PostgreSQL and MySQL."

# PG only
test-postgres: setup-db-postgres
	@echo "--- Running tests against PostgreSQL ---"
	@export TEST_DB="postgres"; \
	export DB_HOST="$(POSTGRES_HOST)"; \
	export DB_PORT="$(POSTGRES_PORT)"; \
	export DB_USER="$(POSTGRES_USER)"; \
	export DB_PASSWORD="$(POSTGRES_PASSWORD)"; \
	export DB_NAME="$(POSTGRES_DB)"; \
	go test $(GO_TEST_FLAGS) $(GO_TEST_TARGET)

# MYSQL only
test-mysql: setup-db-mysql
	@echo "--- Running tests against MySQL ---"
	@export TEST_DB="mysql"; \
	export DB_HOST="$(MYSQL_HOST)"; \
	export DB_PORT="$(MYSQL_PORT)"; \
	export DB_USER="$(MYSQL_USER)"; \
	export DB_PASSWORD="$(MYSQL_PASSWORD)"; \
	export DB_NAME="$(MYSQL_DB)"; \
	go test $(GO_TEST_FLAGS) $(GO_TEST_TARGET)

# Setup both db (via docker containers)
setup: setup-db-postgres setup-db-mysql
	@echo "Database containers should be ready and configured."

# Setup PG container and user/db
setup-db-postgres:
	@echo "--- Setting up PostgreSQL container ($(POSTGRES_CONTAINER_NAME)) ---"
	@docker rm -f $(POSTGRES_CONTAINER_NAME) > /dev/null 2>&1 || true
	@echo "Starting PostgreSQL container..."
	@docker run -d --name $(POSTGRES_CONTAINER_NAME) \
		-p $(POSTGRES_PORT):$(POSTGRES_PORT) \
		-e POSTGRES_DB=$(POSTGRES_DB) \
		-e POSTGRES_USER=$(POSTGRES_SUPERUSER) \
		-e POSTGRES_PASSWORD=$(POSTGRES_SUPERUSER) \
		$(POSTGRES_IMAGE)
	@echo "Waiting for PostgreSQL to be ready (up to 30s)..."
	@timeout 30 bash -c 'until docker exec $(POSTGRES_CONTAINER_NAME) pg_isready -U $(POSTGRES_SUPERUSER) -d $(POSTGRES_DB) -q; do sleep 1; done' \
	 || (echo "PostgreSQL failed to start in time!" && docker logs $(POSTGRES_CONTAINER_NAME) && exit 1)
	@echo "PostgreSQL started. Configuring user and privileges..."
	@docker exec $(POSTGRES_CONTAINER_NAME) psql -U $(POSTGRES_SUPERUSER) -d $(POSTGRES_DB) -c "CREATE USER $(POSTGRES_USER) WITH ENCRYPTED PASSWORD '$(POSTGRES_PASSWORD)';"
	@docker exec $(POSTGRES_CONTAINER_NAME) psql -U $(POSTGRES_SUPERUSER) -d $(POSTGRES_DB) -c "GRANT ALL PRIVILEGES ON DATABASE $(POSTGRES_DB) TO $(POSTGRES_USER);"
	@echo "PostgreSQL setup complete."

# Setup MYSQL container and user/db
setup-db-mysql:
	@echo "--- Setting up MySQL container ($(MYSQL_CONTAINER_NAME)) ---"
	@docker rm -f $(MYSQL_CONTAINER_NAME) > /dev/null 2>&1 || true
	@echo "Starting MySQL container..."
	# Run container setting the root password and creating the database
	@docker run -d --name $(MYSQL_CONTAINER_NAME) \
		-p $(MYSQL_PORT):$(MYSQL_PORT) \
		-e MYSQL_ROOT_PASSWORD=$(MYSQL_ROOT_PASSWORD) \
		-e MYSQL_DATABASE=$(MYSQL_DB) \
		$(MYSQL_IMAGE)
	@echo "Waiting for MySQL to be ready (up to 30s)..."
	# Ping using root user credentials
	@timeout 30 bash -c 'until docker exec $(MYSQL_CONTAINER_NAME) mysqladmin ping -h $(MYSQL_HOST) -u root --password=$(MYSQL_ROOT_PASSWORD) --silent; do sleep 1; done' \
	 || (echo "MySQL failed to start in time!" && docker logs $(MYSQL_CONTAINER_NAME) && exit 1)
	@echo "MySQL started. Configuring user and privileges..."
	# Create user first (use IF NOT EXISTS for idempotency)
	@docker exec $(MYSQL_CONTAINER_NAME) mysql -u root --password=$(MYSQL_ROOT_PASSWORD) -e \
		"CREATE USER IF NOT EXISTS '$(MYSQL_USER)'@'%' IDENTIFIED BY '$(MYSQL_PASSWORD)';"
	# Grant privileges to the created user
	@docker exec $(MYSQL_CONTAINER_NAME) mysql -u root --password=$(MYSQL_ROOT_PASSWORD) -e \
		"GRANT ALL PRIVILEGES ON $(MYSQL_DB).* TO '$(MYSQL_USER)'@'%';"
	# Flush privileges
	@docker exec $(MYSQL_CONTAINER_NAME) mysql -u root --password=$(MYSQL_ROOT_PASSWORD) -e \
		"FLUSH PRIVILEGES;"
	@echo "MySQL setup complete."

# Run vendoring (might be optional? Found in travis.yml)
vendor:
	@echo "--- Running vendoring process ---"
	@go get -u github.com/goware/modvendor
	@go mod vendor
	@modvendor -copy="$(MODVENDOR_PATTERNS)" -v

# Cleans up containers
clean: stop-db-postgres stop-db-mysql
	@echo "Cleaned up database containers."

stop-db-postgres:
	@echo "--- Stopping and removing PostgreSQL container ($(POSTGRES_CONTAINER_NAME)) ---"
	@docker rm -f $(POSTGRES_CONTAINER_NAME) > /dev/null 2>&1 || true

stop-db-mysql:
	@echo "--- Stopping and removing MySQL container ($(MYSQL_CONTAINER_NAME)) ---"
	@docker rm -f $(MYSQL_CONTAINER_NAME) > /dev/null 2>&1 || true