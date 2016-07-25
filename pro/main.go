//go:generate -command yacc go tool yacc
//go:generate yacc -o expr.go expr.y

package main

import (
	"fmt"
	"math"
	"unsafe"
)

const (
	LISTTYPE      = iota
	NHASH         = 8192
	USERCUSFNTYPE = 'c'
	REFTYPE       = 'r'
	ASSIGNTYPE    = 'a'
)

const (
	b_sqrt = iota
	b_exp
	b_log
	b_print
	c_gt
	c_lt
	c_le
	c_ge
	c_ne
	c_eq
)

var symtab [NHASH]symbol

var knownFns map[string]int = map[string]int{
	"sqrt":  b_sqrt,
	"exp":   b_exp,
	"log":   b_log,
	"print": b_print,
	">":     c_gt,
	"<":     c_lt,
	"<=":    c_le,
	">=":    c_ge,
	"!=":    c_ne,
	"==":    c_eq,
}

func str2FnType(s string) int {
	return knownFns[s]
}

type symbol struct {
	name  string
	value float64
	fun   *astNode
	syms  *symlist
}

type symlist struct {
	sym  *symbol
	next *symlist
}

type astNode struct {
	typ int
	l   *astNode
	r   *astNode
}

type numval struct {
	typ int
	val float64
}

type fncall struct { /*built-in function*/
	nodetype int
	args     *astNode
	functype int
}

type ufncall struct { /*user defined func*/
	nodetype int
	args     *astNode
	s        *symbol
}

type flow struct {
	nodetype int
	cond     *astNode
	tl       *astNode
	el       *astNode
}

type symref struct {
	nodetype int
	s        *symbol
}

type symasgn struct {
	nodetype int
	s        *symbol
	v        *astNode
}

func newast(typ int, l, r *astNode) *astNode {
	a := &astNode{}
	a.typ = typ
	a.l = l
	a.r = r
	return a
}

func eval(a *astNode) float64 {
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
	case NUMBER:
		ret = ((*numval)(unsafe.Pointer(a))).val
	case REFTYPE:
		ret = ((*symref)(unsafe.Pointer(a))).s.value
	case ASSIGNTYPE:
		((*symasgn)(unsafe.Pointer(a))).s.value = eval(((*symasgn)(unsafe.Pointer(a))).v)
		ret = ((*symasgn)(unsafe.Pointer(a))).s.value
	case IF:
		ret = 0.0
		ff := (*flow)(unsafe.Pointer(a))
		if eval(ff.cond) != 0 { // OK
			if ff.tl != nil {
				ret = eval(ff.tl)
			}
		} else {
			if ff.el != nil {
				ret = eval(ff.el)
			}
		}
	case WHILE:
		ret = 0.0
		ff := (*flow)(unsafe.Pointer(a))
		if ff.tl != nil {
			for eval(ff.cond) != 0 {
				ret = eval(ff.tl)
			}
		}
	case LISTTYPE:
		eval(a.l)
		ret = eval(a.r)
	case BUILTINFN:
		ret = callbuiltin((*fncall)(unsafe.Pointer(a)))
	case USERCUSFNTYPE:
		ret = calluser((*ufncall)(unsafe.Pointer(a)))
    case c_gt,c_lt,c_le,c_ge,c_ne,c_eq:
        ret = calccmp(a)
	}

	return ret
}

func num2ast(f float64) *astNode {
	num := &numval{}
	num.typ = NUMBER
	num.val = f
	return (*astNode)(unsafe.Pointer(num))
}

func symhash(name string) int {
	hash := 0
	for i := 0; i < len(name); i++ {
		hash = hash*9 ^ int(name[i])
	}
	return hash
}

func lookup(name string) *symbol {
	sp := &symtab[symhash(name)%NHASH]

	for scount := NHASH - 1; scount >= 0; scount-- {
		if sp.name == name {
			return sp
		}

		if sp.name == "" {
			sp.name = name
			sp.value = 0
			return sp
		}

		//if (++sp >= symtab + NHASH)
		//	sp = symtab;
	}

	//yyerror("symbol table overflow\n");
	//abort();		/*尝试完所有条目，符号表已满 */
	return nil
}

func newcmp(cmptype int, l, r *astNode) *astNode {
	a := &astNode{}
	a.typ = cmptype
	a.l = l
	a.r = r
	return a
}

func newfunc(functype int, args *astNode) *astNode {
	a := &fncall{}
	a.nodetype = BUILTINFN
	a.args = args
	a.functype = functype
	return (*astNode)(unsafe.Pointer(a))
}

func newcall(s *symbol, args *astNode) *astNode {
	a := &ufncall{}
	a.nodetype = USERCUSFNTYPE
	a.args = args
	a.s = s
	return (*astNode)(unsafe.Pointer(a))
}

func newref(s *symbol) *astNode {
	a := &symref{}
	a.nodetype = REFTYPE
	a.s = s
	return (*astNode)(unsafe.Pointer(a))
}

func newasgn(s *symbol, v *astNode) *astNode {
	a := &symasgn{}
	a.nodetype = ASSIGNTYPE
	a.s = s
	a.v = v
	return (*astNode)(unsafe.Pointer(a))
}

func newflow(nodetype int, cond, tl, el *astNode) *astNode {
	a := &flow{}
	a.nodetype = nodetype
	a.cond = cond
	a.tl = tl
	a.el = el
	return (*astNode)(unsafe.Pointer(a))
}

func newsymlist(sym *symbol, next *symlist) *symlist {
	sl := &symlist{}
	sl.sym = sym
	sl.next = next
	return sl
}

func callbuiltin(f *fncall) float64 {
	functype := f.functype
	v := eval(f.args)
	switch functype {
	case b_sqrt:
		return math.Sqrt(v)
	case b_log:
		return math.Log(v)
	case b_exp:
		return math.Exp(v)
	case b_print:
		fmt.Printf("= %4.4g\n", v)
		return v
		//                  default:
	}
	return v
}

func dodef(s *symbol, syms *symlist, fun *astNode) {
	s.syms = syms
	s.fun = fun
}

func calluser(f *ufncall) float64 {
	fn := f.s
	args := f.args

	var v float64
	var i int
	var nargs int

	if fn.fun == nil {
		fmt.Printf("call undefined function:%s\n", fn.name)
		//yyerror("call undefined function\n", fn->name);
		return 0
	}

	sl := fn.syms
	for nargs = 0; sl != nil; sl = sl.next {
		nargs++
	}

	oldval := make([]float64, nargs)
	newval := make([]float64, nargs)

	for i = 0; i < nargs; i++ {
		if args == nil {
			//yyerror("too few args in call to %s\n", fn->name);
			fmt.Printf("too few args in call to %s\n", fn.name)
			return 0.0
		}

		if args.typ == LISTTYPE {
			newval[i] = eval(args.l)
			args = args.r
		} else {
			newval[i] = eval(args)
			args = nil
		}
	}

	sl = fn.syms
	for i = 0; i < nargs; i++ {
		s := sl.sym
		oldval[i] = s.value
		s.value = newval[i]
		sl = sl.next
	}

	v = eval(fn.fun)

	sl = fn.syms
	for i = 0; i < nargs; i++ {
		s := sl.sym
		s.value = oldval[i]
		sl = sl.next
	}

	return v
}

func calccmp(a *astNode) float64 {
b :=false
l := eval(a.l)
r := eval(a.r)

    switch a.typ {
        case c_gt:
        b = (l>r)
        case c_lt:
            b = (l<r)
        case c_le:
                b = (l<=r)
        case c_ge:
                    b = (l>=r)
        case c_ne:
                        b = (l!=r)
        case c_eq:
                            b = (l==r)
    }

    if b {
        return 1
    }

    return 0
}
