.PHONY:all

all: expr

expr: expr.go
	go build -o $@

expr.go: expr.y
	go generate

clean:
	@-rm y.output expr.go expr
