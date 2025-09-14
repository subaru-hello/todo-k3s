# Load .env file first
-include .env
export

# ==== config ====
REG?=docker.io
DOCKER_USER?=subaru88
APP=home-kube
TAG?=0.1.0
IMAGE=$(REG)/$(DOCKER_USER)/$(APP):$(TAG)

# ==== infra ====
up:
	@echo "Starting infrastructure..."
	@docker-compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 5
	@echo "Infrastructure is ready!"
down:
	@docker-compose down
	@echo "Infrastructure stopped."
logs:
	docker-compose logs -f
reset:
	@echo "Resetting infrastructure..."
	@docker-compose down -v
	@docker-compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 5
	@echo "Infrastructure reset complete!"

# ==== node local ====
install:
	npm ci
dev:
	npx tsx watch src/index.ts
db-migrate:
	npx typeorm-ts-node-esm migration:run -d src/db/dataSource.ts
db-migration-generate:
	npx typeorm-ts-node-esm migration:generate -d src/db/dataSource.ts src/db/migrations/$(name)
build:
	npm run build
start:
	node dist/index.js

# ==== docker ====
docker-build:
	docker build -t $(IMAGE) .
docker-run:
	docker run --rm -p 3000:3000 \
	  -e DB_HOST=host.docker.internal \
	  -e DB_USER=myuser -e DB_PASSWORD=mypassword -e DB_NAME=mydb \
	  $(IMAGE)
docker-push:
	docker push $(IMAGE)
docker-tag-latest:
	docker tag $(IMAGE) $(REG)/$(DOCKER_USER)/$(APP):latest
	docker push $(REG)/$(DOCKER_USER)/$(APP):latest

# ==== release ====
docker-login:
	@echo "Logging in to Docker Hub..."
	@echo $(DOCKER_TOKEN) | docker login -u $(DOCKER_USERNAME) --password-stdin
	@echo "Successfully logged in to Docker Hub"

deploy: build docker-build docker-login
	@echo "Building and pushing Docker image..."
	@echo "Image: $(IMAGE)"
	docker push $(IMAGE)
	@echo "Tagging as latest..."
	docker tag $(IMAGE) $(REG)/$(DOCKER_USER)/$(APP):latest
	docker push $(REG)/$(DOCKER_USER)/$(APP):latest
	@echo "Successfully pushed $(IMAGE) and :latest"
