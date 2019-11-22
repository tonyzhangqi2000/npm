tag=jessie

docker:
	cp Dockerfile.in Dockerfile
	sed -i "s/@TAG@/$(tag)/g" Dockerfile
	docker build -t nizq/openresty:$(tag) .
	rm Dockerfile
