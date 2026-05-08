.PHONY: build install test clean

build:
	go build -o mdp ./cmd/mdp

install:
	go install ./cmd/mdp

test:
	go test ./...

clean:
	rm -f mdp
	rm -rf dist
