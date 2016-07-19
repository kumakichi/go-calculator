%{

package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"regexp"
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

var rulesReg map[*regexp.Regexp]int

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
	var mLen int
	var leftStr string

	leftStr = string(x.line[x.pos:])

	for k, v := range rulesReg {
		mResult := k.FindStringSubmatchIndex(leftStr)
		mLen = len(mResult)
		if mLen < 2 || mResult[0] != 0 { // [start end ...]
			continue
		}

		okstr := string(x.line[x.pos : x.pos+mResult[1]])
		x.pos += mResult[1]

		switch v {
		case WHITESPACE: /* ignore whitespace */
		case '+', '-', '*', '/', '(', ')', EXP:
			return v
		case NUM:
			yylval.num, _ = strconv.ParseFloat(okstr, 64)
			return NUM
		case QUIT:
			fmt.Println("Quit now ~")
			os.Exit(0)
		default:
			fmt.Println("You should not see this info")
			break
		}
	}

	if x.pos < x.length {
		fmt.Printf("Mystery character %c\n", x.line[x.pos])
	}

	return eof
}

func main() {
	rulesReg = map[*regexp.Regexp]int{
		regexp.MustCompile(`\+`):                                   '+',
		regexp.MustCompile(`-`):                                    '-',
		regexp.MustCompile(`\*\*|\^`):                              EXP,
		regexp.MustCompile(`\*`):                                   '*',
		regexp.MustCompile(`/`):                                    '/',
		regexp.MustCompile(`\(`):                                   '(',
		regexp.MustCompile(`\)`):                                   ')',
		regexp.MustCompile(`\s`):                                   WHITESPACE,
		regexp.MustCompile(`([1-9])([\d]*\.?[\d]*)?|(0\.)([\d]+)`): NUM,
		regexp.MustCompile(`(?i)quit|exit`):                        QUIT,
	}

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
