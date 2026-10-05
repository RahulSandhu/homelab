SCHEMAS := $(wildcard docs/schemas/*.dot)

.PHONY: help all schemas clean

help:
	@echo "Available targets:"
	@echo "  make help     - Show available targets"
	@echo "  make all      - Compile schema diagrams"
	@echo "  make schemas  - Compile docs/schemas/*.dot to tmp/*.png"
	@echo "  make clean    - Remove generated tmp/ folder"

all: schemas

schemas:
	@echo "Compiling schema diagrams to PNG..."
	@mkdir -p tmp
	@for file in $(SCHEMAS); do \
		name=$$(basename $$file .dot); \
		echo "  $$file -> tmp/$$name.png"; \
		dot -Tpng $$file -o tmp/$$name.png; \
	done

clean:
	@echo "Cleaning tmp/ folder..."
	@rm -rf tmp/
