
.PHONY: format
format:
	npx prettier@3.1.1 --write .

.PHONY: lint
lint:
	npx prettier@3.1.1 . --check
