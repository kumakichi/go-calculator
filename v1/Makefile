.PHONY:all

all: expr

expr: expr.go
	go build -o $@

expr.go: expr.y
	goyacc -o $@ $^

clean:
	@-rm y.output expr.go expr
