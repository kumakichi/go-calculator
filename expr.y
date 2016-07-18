%{

package main

import (
	"bufio"
	"fmt"
	"math"
	"io"
	"log"
	"regexp"
	"strconv"
	"os"
)

%}

%union {
	num float64
}

%type	<num>	expr

%token '(' ')' QUIT EXP EOL
%token	<num>	NUM

%left '+' '-'
%left '*' '/'
%nonassoc UMINUS EXP

%%

top: expr EOL
	{
			fmt.Printf("%f\n", $1)
	}

expr: expr '+' expr { $$ = $1 + $3;}
    | expr '-' expr { $$ = $1 - $3;}
    | expr '*' expr { $$ = $1 * $3;}
    | expr '/' expr { $$ = $1 / $3;}
    | expr EXP expr { $$ = math.Pow($1, $3);}
    | '-' expr %prec UMINUS { $$ = -$2;}
    | '(' expr ')'  { $$ = $2;}
    | NUM

%%

var rulesReg map[*regexp.Regexp]int

const eof = 0

// <prefix>Lex
type yyLex struct {
	line   []byte // fill data in func main
	length int
	pos    int
}

// method1: Error(string)
func (x *yyLex) Error(s string) {
	log.Printf("parse error: %s", s)
}

// method2: Lex(*<prefix>SymType) int
func (x *yyLex) Lex(yylval *yySymType) int {
	var mLen int

	for {
		for k, v := range rulesReg {
			target := string(x.line[x.pos:])
			mResult := k.FindStringSubmatchIndex(target)
			mLen = len(mResult)
			if mLen < 2 || mResult[0] != 0 { // [start end ...]
				continue
			}

			okstr := string(x.line[x.pos : x.pos+mResult[1]])
			x.pos += mResult[1]

			switch v {
			case '+', '-', '*', '/', '(', ')', EXP, EOL:
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

		return eof
	}
}

func main() {
	rulesReg = map[*regexp.Regexp]int{
		regexp.MustCompile(`\+`): '+',
		regexp.MustCompile(`-`):  '-',
		regexp.MustCompile(`\*\*`): EXP,
		regexp.MustCompile(`\*`): '*',
		regexp.MustCompile(`/`):  '/',
		regexp.MustCompile(`\(`): '(',
		regexp.MustCompile(`\)`): ')',
		regexp.MustCompile(`\n`): EOL,
		regexp.MustCompile(`([1-9])([\d]*\.?[\d]*)?|(0\.)([\d]+)`): NUM,
		regexp.MustCompile(`(?i)quit|exit`):                             QUIT,
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
