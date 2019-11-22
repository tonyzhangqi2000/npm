version=5.4.0

docker:
	cp Dockerfile.in Dockerfile
	sed -i "s/@VERSION@/$(version)/g" Dockerfile
	docker build -t nizq/grafana:$(version) .
	rm Dockerfile
