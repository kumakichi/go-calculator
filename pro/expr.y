%{

package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"os"
	"regexp"
	"strconv"
)

%}

%union {
	a   *astNode
	num float64
	s   *symbol
	sl  *symlist
	fn  int /* built-in functions and compare */
}

%token <num> NUMBER
%token <s> SYMBOL
%token <fn> BUILTINFN
%nonassoc <fn> CMPFN

%token IF ELSE WHILE DEFUN EOL QUIT WHITESPACE

%right '='
%left '+' '-'
%left '*' '/'
%nonassoc UMINUS EXP

%type <a> expr stmt explist stmtlist block
%type <sl> slist

%%

calclist:
    | calclist stmt EOL {
        fmt.Printf(" = %4.4g\n", eval($2));
    }
    | calclist DEFUN SYMBOL '(' slist ')' block EOL {
        dodef($3, $5, $7);
        fmt.Printf("definded %s\n> ", $3.name);
    }
    | calclist error EOL {
        fmt.Printf("> ");
    }

stmt: IF expr block {$$ = newflow(IF, $2, $3, nil);}
    | IF expr block ELSE block {$$ = newflow(IF, $2, $3, $5);}
    | WHILE expr block {$$ = newflow(WHILE, $2, $3, nil);}
    | expr

block: '{' stmtlist '}' { $$ = $2; };

stmtlist: stmt ';' stmtlist {$$ = newast(LISTTYPE, $1, $3); }
    | stmt ';'
    | stmt

expr: expr CMPFN expr {$$ = newcmp($2, $1, $3);}
    | expr '+' expr {$$ = newast('+', $1, $3);}
    | expr '-' expr {$$ = newast('-', $1, $3);}
    | expr '*' expr {$$ = newast('*', $1, $3);}
    | expr '/' expr {$$ = newast('/', $1, $3);}
    | expr EXP expr {$$ = newast(EXP, $1, $3);}
    | '(' expr ')' {$$ = $2;}
    | '-' expr %prec UMINUS {$$ = newast(UMINUS, $2, nil);}
    | NUMBER {$$ = num2ast($1);}
    | SYMBOL {$$ = newref($1);}
    | SYMBOL '=' expr {$$ = newasgn($1, $3);}
    | BUILTINFN '(' explist ')' {$$ = newfunc($1, $3);}
    | SYMBOL '(' explist ')' {$$ = newcall($1, $3);}

explist: expr
    | expr ',' explist {$$ = newast(LISTTYPE, $1, $3);}

slist: SYMBOL {$$ = newsymlist($1, nil);}
    | SYMBOL ',' slist {$$ = newsymlist($1, $3);}

%%

type Rule struct {
	r *regexp.Regexp
	v int
}

var rulesArray []Rule

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

ss:
	if x.pos >= x.length {
		return eof
	}

	leftStr = string(x.line[x.pos:])

	for _, rule := range rulesArray {
		k := rule.r
		v := rule.v
		mResult := k.FindStringSubmatchIndex(leftStr)
		mLen = len(mResult)
		//if mLen == 2 {
		//    fmt.Printf("<%s,%d,%v>\n",leftStr, v, mResult)
		//}
		if mLen < 2 || mResult[0] != 0 { // [start end ...]
			continue
		}

		var okstr string
		if x.pos+mResult[1] <= x.length {
			okstr = string(x.line[x.pos : x.pos+mResult[1]])
		}
		x.pos += mResult[1]

		switch v {
		case WHITESPACE: /* ignore whitespace */
			goto ss
		case '+', '-', '*', '/', '(', ',', ')', '=', EXP, '{', '}', IF, ELSE, WHILE, DEFUN, EOL, ';':
			return v
		case NUMBER:
			yylval.num, _ = strconv.ParseFloat(okstr, 64)
			return NUMBER
		case BUILTINFN:
			yylval.fn = str2FnType(okstr)
			return BUILTINFN
		case CMPFN:
			yylval.fn = str2FnType(okstr)
			return CMPFN
		case SYMBOL:
			yylval.s = lookup(okstr) /* find or create */
			return SYMBOL
		case QUIT:
			fmt.Println("Quit now ~")
			os.Exit(0)
		default:
			fmt.Printf("You should not see this info:%d\n", v)
			break
		}
	}

	if x.pos < x.length {
		fmt.Printf("Mystery character %c\n", x.line[x.pos])
	}

	return eof
}

func main() {
	rulesArray = []Rule{
		Rule{r: regexp.MustCompile(`\+`), v: '+'},
		Rule{r: regexp.MustCompile(`-`), v: '-'},
		Rule{r: regexp.MustCompile(`\*\*|\^`), v: EXP},
		Rule{r: regexp.MustCompile(`\*`), v: '*'},
		Rule{r: regexp.MustCompile(`/`), v: '/'},
		Rule{r: regexp.MustCompile(`\(`), v: '('},
		Rule{r: regexp.MustCompile(`,`), v: ','},
		Rule{r: regexp.MustCompile(`\)`), v: ')'},
		Rule{r: regexp.MustCompile(`{`), v: '{'},
		Rule{r: regexp.MustCompile(`}`), v: '}'},
		Rule{r: regexp.MustCompile(`\n`), v: EOL},
		Rule{r: regexp.MustCompile(`\r|\t| `), v: WHITESPACE},
		Rule{r: regexp.MustCompile(`([1-9])([\d]*\.?[\d]*)?|(0\.)([\d]+)`), v: NUMBER},
		Rule{r: regexp.MustCompile(`(?i)quit|exit`), v: QUIT},
		Rule{r: regexp.MustCompile(`if`), v: IF},
		Rule{r: regexp.MustCompile(`else`), v: ELSE},
		Rule{r: regexp.MustCompile(`while`), v: WHILE},
		Rule{r: regexp.MustCompile(`defun`), v: DEFUN},
		Rule{r: regexp.MustCompile(`sqrt|exp|log|print`), v: BUILTINFN},
		Rule{r: regexp.MustCompile(`<|>|<=|>=|\!=|==`), v: CMPFN},
		Rule{r: regexp.MustCompile(`=`), v: '='},
		Rule{r: regexp.MustCompile(`;`), v: ';'},
		Rule{r: regexp.MustCompile(`[a-zA-Z]\w*`), v: SYMBOL},
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
