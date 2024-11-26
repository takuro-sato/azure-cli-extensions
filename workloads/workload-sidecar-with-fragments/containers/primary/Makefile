ALL: .image_build .image_push primary_policy

clean:
	rm -f .image_build .image_push

.image_build: Dockerfile primary_startup.sh
	make clean
	docker buildx build -t $(IMAGE) .
	touch .image_build

.image_push: .image_build
	docker push $(IMAGE)
	touch .image_push
