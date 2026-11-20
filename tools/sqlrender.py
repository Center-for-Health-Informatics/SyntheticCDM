#!/usr/bin/env python3
"""Render the subset of OHDSI SqlRender syntax used by the vendored SQL.

    sqlrender.py [--split] name=value [name=value ...] < template.sql > rendered.sql

Supports:
  * @parameter substitution (whole identifiers only; unknown parameters are
    left untouched so comments like `@targetDialect` survive)
  * {condition} ? {then} : {else}   and   {condition} ? {then}
    with ==, !=, |, &, !, parentheses, quoted strings, TRUE/FALSE

This is *rendering* only, not SqlRender's dialect *translation*. The source
dialect is already SQL Server, so translation is (nearly) the identity; the
few constructs it would have rewritten are fixed by patches in etl-patches/.
"""
import re
import sys

PARAM = re.compile(r"@([A-Za-z_][A-Za-z0-9_]*)")


def substitute(sql, params):
    return PARAM.sub(lambda m: params.get(m.group(1), m.group(0)), sql)


def match_brace(s, i):
    """s[i] == '{'; return index of the matching '}'."""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return j
    raise ValueError(f"unbalanced brace at offset {i}")


def evaluate(cond):
    tokens = re.findall(r"'[^']*'|\"[^\"]*\"|==|!=|[|&!()]|[^\s|&!()=]+", cond)
    out = []
    for t in tokens:
        if t == "|":
            out.append(" or ")
        elif t == "&":
            out.append(" and ")
        elif t == "!":
            out.append(" not ")
        elif t in ("==", "!=", "(", ")"):
            out.append(f" {t} ")
        elif t[0] in "'\"":
            out.append(repr(t[1:-1]))
        elif t.upper() in ("TRUE", "1"):
            out.append(" True ")
        elif t.upper() in ("FALSE", "0"):
            out.append(" False ")
        else:
            out.append(repr(t))  # bare word, compared as a string
    return bool(eval("".join(out), {"__builtins__": {}}, {}))


def render_conditionals(s):
    out, i = [], 0
    while i < len(s):
        if s[i] != "{":
            out.append(s[i])
            i += 1
            continue
        end = match_brace(s, i)
        m = re.compile(r"\s*\?\s*\{").match(s, end + 1)
        if not m:  # a literal brace block, not a conditional
            out.append(s[i])
            i += 1
            continue
        cond = s[i + 1:end]
        t_open = m.end() - 1
        t_close = match_brace(s, t_open)
        then_part, else_part, nxt = s[t_open + 1:t_close], "", t_close + 1
        m2 = re.compile(r"\s*:\s*\{").match(s, t_close + 1)
        if m2:
            e_open = m2.end() - 1
            e_close = match_brace(s, e_open)
            else_part, nxt = s[e_open + 1:e_close], e_close + 1
        out.append(render_conditionals(then_part if evaluate(cond) else else_part))
        i = nxt
    return "".join(out)


WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def split_batches(sql):
    """Put each top-level statement in its own sqlcmd batch (append GO).

    DatabaseConnector::executeSql (how ETL-Synthea runs these files) splits on
    ';' and executes statements one at a time; sqlcmd would otherwise run a
    whole file as one batch, which changes semantics (e.g. re-creating #temp
    tables). Like SqlRender::splitSql, ';' inside strings, quoted identifiers,
    comments, and BEGIN/CASE ... END blocks does not split.
    """
    out, i, n, depth, stmt_start = [], 0, len(sql), 0, 0
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j < 0 else j
        elif sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif c in "'\"[":
            close = "]" if c == "[" else c
            j = i + 1
            while j < n:
                if sql[j] == close:
                    if j + 1 < n and sql[j + 1] == close:  # doubled = escaped
                        j += 2
                        continue
                    break
                j += 1
            i = j + 1
        elif c.isalpha() or c == "_":
            m = WORD.match(sql, i)
            w = m.group(0).upper()
            if w in ("BEGIN", "CASE"):
                depth += 1
            elif w == "END" and depth > 0:
                depth -= 1
            i = m.end()
        elif c == ";" and depth == 0:
            out.append(sql[stmt_start:i + 1] + "\nGO\n")
            i += 1
            stmt_start = i
        else:
            i += 1
    out.append(sql[stmt_start:])
    return "".join(out)


def main():
    args = sys.argv[1:]
    split = "--split" in args
    params = dict(a.split("=", 1) for a in args if a != "--split")
    sql = render_conditionals(substitute(sys.stdin.read(), params))
    sys.stdout.write(split_batches(sql) if split else sql)


if __name__ == "__main__":
    main()
