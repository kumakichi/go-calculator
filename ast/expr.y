%{

package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"strconv"
	"unsafe"
)

type AST struct {
	typ int
	l   *AST
	r   *AST
}

type NUMVAL struct {
	typ int
	val float64
}

func newast(typ int, l, r *AST) *AST {
	a := &AST{}
	a.typ = typ
	a.l = l
	a.r = r
	return a
}

func eval(a *AST) float64 {
	var ret float64 = 0

	switch a.typ {
	case '+':
		ret = eval(a.l) + eval(a.r)
	case '-':
		ret = eval(a.l) - eval(a.r)
	case '*':
		ret = eval(a.l) * eval(a.r)
	case '/':
		ret = eval(a.l) / eval(a.r)
	case UMINUS:
		ret = -eval(a.l)
	case EXP:
		ret = math.Pow(eval(a.l), eval(a.r))
	case NUM:
		ret = ((*NUMVAL)(unsafe.Pointer(a))).val
	}

	return ret
}

func num2ast(f float64) *AST {
	num := &NUMVAL{}
	num.typ = NUM
	num.val = f
	return (*AST)(unsafe.Pointer(num))
}

%}

%union {
    a *AST
	num float64
}

%type	<a>	expr

%token '(' ')' QUIT EXP WHITESPACE
%token	<num>	NUM

%left '+' '-'
%left '*' '/'
%nonassoc UMINUS EXP

%%

top: expr {
        fmt.Printf("%f\n", eval($1));
    }

expr: expr '+' expr { $$ = newast('+', $1, $3); }
    | expr '-' expr { $$ = newast('-', $1, $3); }
    | expr '*' expr { $$ = newast('*', $1, $3); }
    | expr '/' expr { $$ = newast('/', $1, $3); }
    | expr EXP expr { $$ = newast(EXP, $1, $3);}
    | '-' expr %prec UMINUS { $$ = newast(UMINUS, $2, nil);}
    | '(' expr ')'  { $$ = $2;}
    | NUM { $$ = num2ast($1); }

%%

const eof = 0

// step 0, define struct : <prefix>Lex
type yyLex struct {
	line   []byte // fill data in func 'main'
	length int
	pos    int
}

// step 1, <prefix>Lex method: Error(string)
func (x *yyLex) Error(s string) {
	log.Printf("parse error: %s", s)
}

// step 2, <prefix>Lex method: Lex(*<prefix>SymType) int
func (x *yyLex) Lex(yylval *yySymType) int {
	val := int(x.line[x.pos])
	switch x.line[x.pos] {
	case '+', '-', '/', '(', ')':
		x.pos += 1
		return val
	case '*':
		if x.line[x.pos+1] == '*' {
			x.pos += 2
			return EXP
		} else {
			x.pos += 1
			return val
		}
	case '^':
		x.pos += 1
		return EXP
	case ' ', '\t', '\r', '\n': // ignore WHITESPACE
		x.pos += 1
	case 'q', 'Q':
		if readQuit(x) {
			fmt.Println("Quit now ~")
			os.Exit(0)
		}
	case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
		numStr, ok := readNum(x)
		x.pos += len(numStr)
		if ok {
			yylval.num, _ = strconv.ParseFloat(string(numStr), 64)
			return NUM
		}
	}

	if x.pos < x.length {
		fmt.Printf("Mystery character %d/%d, %c,%x\n", x.pos, x.length, x.line[x.pos], x.line[x.pos])
	}

	return eof
}

func main() {
	in := bufio.NewReader(os.Stdin)
	for {
		if _, err := os.Stdout.WriteString("> "); err != nil {
			log.Fatalf("WriteString: %s", err)
		}
		line, err := in.ReadBytes('\n')
		if err == io.EOF {
			return
		}
		if err != nil {
			log.Fatalf("ReadBytes: %s", err)
		}

		yyParse(&yyLex{line: line, length: len(line), pos: 0})
	}
}

func readQuit(x *yyLex) (ok bool) {
	if x.pos+4 > x.length {
		return
	}

	if x.line[x.pos] == 'q' &&
		x.line[x.pos+1] == 'u' &&
		x.line[x.pos+2] == 'i' &&
		x.line[x.pos+3] == 't' {
		ok = true
		return
	}

	if x.line[x.pos] == 'Q' &&
		x.line[x.pos+1] == 'U' &&
		x.line[x.pos+2] == 'I' &&
		x.line[x.pos+3] == 'T' {
		ok = true
		return
	}

	return
}

func readNum(x *yyLex) (numStr []byte, ok bool) {
	usedDot := false
	if x.line[x.pos] == '0' && x.line[x.pos+1] != '.' {
		return
	}

	for i := x.pos; i < x.length; i++ {
		if x.line[i] <= '9' && x.line[i] >= '0' {
			numStr = append(numStr, x.line[i])
		} else if x.line[i] == '.' {
			if usedDot == false {
				usedDot = true
				numStr = append(numStr, x.line[i])
			} else {
				return
			}
		} else {
			ok = true
			return
		}
	}
	return
}
