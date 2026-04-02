IMAGE = briankwest/workshop
TAG   = latest

.PHONY: build pull push

build:
	docker compose build

pull:
	docker compose pull

push:
	docker buildx create --name workshop-builder --use 2>/dev/null || true
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(TAG) --push .
