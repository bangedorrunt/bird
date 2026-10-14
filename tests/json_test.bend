import Base
import ../src/json.bend as J

# End-to-end check of the JSON module. Bend ships no test framework, so the test
# is a program: it prints one line per case and dies with a nonzero exit code on
# the first failure.
#
#   bend tests/json_test.bend
#
# The document is deliberately awkward: nested containers, an escaped quote and
# backslash, a newline escape, a number in exponent form, and empty containers.
# Defs are written callee first, because Bend has no forward declarations: a
# call to a def written below its caller is an error.

def ok_on(passed: Bool,+name: String) -> IO(Unit):
  match passed:
    case True{}:
      IO.print("ok   " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

# A `match` may head a def body but may not sit as a statement in a `do` block,
# so the branch is its own def.
def ok(name: String, passed: Bool) -> IO(Unit):
  ok_on(passed, name)

def is_err(p: J.Parsed) -> Bool:
  match p:
    case J.ParsedErr{message}:
      True{}
    case J.ParsedOk{value}:
      False{}

def is_ok(p: J.Parsed) -> Bool:
  match p:
    case J.ParsedErr{message}:
      False{}
    case J.ParsedOk{value}:
      True{}

def doc() -> String:
  "{\"id\":\"1234567890123456789\",\"nested\":{\"a\":[1,2,{}],\"b\":[[true],null]},\"n\":-1.5e3,\"s\":\"q\\\"b\\\\c\\nd\",\"empty\":{},\"arr\":[]}"

def check_errors() -> IO(Unit):
  do IO<Unit>:
    ok("rejects a dangling value", is_err(J.parse("{\"a\":}")))
    ok("rejects an unterminated array", is_err(J.parse("[1,2")))
    ok("rejects trailing junk", is_err(J.parse("{} {}")))
    ok("rejects an unterminated string", is_err(J.parse("\"abc")))
    ok("rejects an empty document", is_err(J.parse("")))
    ok("accepts leading whitespace", is_ok(J.parse("  \n {\"a\": 1}  ")))
    ok("accepts a bare scalar", is_ok(J.parse("42")))
    ok("accepts a bare string", is_ok(J.parse("\"hi\"")))

def check_fields(+body: J.Json) -> IO(Unit):
  do IO<Unit>:
    +nested : J.Json = J.get_or_null(body, "nested")
    +arr : J.Json = J.get_or_null(nested, "a")
    +b : J.Json = J.get_or_null(nested, "b")
    id : String = J.text(J.get_or_null(body, "id"))
    ok("a 19 digit id survives", String.eq(id, "1234567890123456789"))
    ok("array element by index", U32.is_eq(J.u32(J.at_index(arr, 0n)), 1))
    ok("out of range index is null", J.is_null(J.at_index(arr, 9n)))
    ok("bool inside a nested array", J.bool(J.at_index(J.at_index(b, 0n), 0n)))
    ok("array of three", U32.is_eq(J.count(arr), 3))
    ok("empty array", U32.is_eq(J.count(J.get_or_null(body, "arr")), 0))
    ok("deep path read", J.has_path(body, "nested" <> ("b" <> Nil{})))
    ok("missing key is absent", Bool.not(J.has_path(body, "nope" <> Nil{})))
    ok("missing key reads as null", J.is_null(J.get_or_null(body, "nope")))
    ok("escape is decoded", String.eq(J.text(J.get_or_null(body, "s")), "q\"b\\c\nd"))
    ok("number text is kept verbatim", String.eq(J.text(J.get_or_null(body, "n")), "-1.5e3"))

def pretty_of(p: J.Parsed) -> IO(String):
  match p:
    case J.ParsedErr{message}:
      IO.die(String, 2, "parse failed: " ++ message)
    case J.ParsedOk{value}:
      IO.pure(String, J.pretty(value))

def pretty_doc() -> String:
  "{\"nested\":{\"a\":[1,2]},\"empty\":{},\"arr\":[],\"s\":\"hi\"}"

def pretty_wanted() -> String:
  "{\n"
  ++ "  \"nested\": {\n"
  ++ "    \"a\": [\n"
  ++ "      1,\n"
  ++ "      2\n"
  ++ "    ]\n"
  ++ "  },\n"
  ++ "  \"empty\": {},\n"
  ++ "  \"arr\": [],\n"
  ++ "  \"s\": \"hi\"\n"
  ++ "}"

# The pretty printer is checked against the whole rendering rather than a
# property, because the way it can be wrong is the shape of the output: an
# indent one level off, or a closing bracket at the wrong depth, is still valid
# JSON that no round-trip test would notice.
def check_pretty() -> IO(Unit):
  do IO<Unit>:
    rendered : String <- pretty_of(J.parse(pretty_doc()))
    ok("pretty prints the whole shape", String.eq(rendered, pretty_wanted()))
    ok("a scalar is itself", String.eq(J.pretty(J.of_u32(3)), "3"))
    ok("an empty object stays on one line", String.eq(J.pretty(J.obj_of(Nil{})), "{}"))
    nested : String <- pretty_of(J.parse("[[1]]"))
    ok("an array inside an array nests", String.eq(nested, "[\n  [\n    1\n  ]\n]"))
    table : String <- pretty_of(J.parse("[{\"a\":1},{\"b\":2}]"))
    ok("a list of objects separates its entries", String.eq(table,
      "[\n  {\n    \"a\": 1\n  },\n  {\n    \"b\": 2\n  }\n]"))

def body_of(p: J.Parsed) -> IO(J.Json):
  match p:
    case J.ParsedErr{message}:
      IO.die(J.Json, 2, "parse failed: " ++ message)
    case J.ParsedOk{value}:
      IO.pure(J.Json, value)

def roundtrip(p: J.Parsed) -> IO(String):
  match p:
    case J.ParsedErr{message}:
      IO.die(String, 2, "parse failed: " ++ message)
    case J.ParsedOk{value}:
      IO.pure(String, J.show(value))

# Regression: escape once recursed per character and overflowed the machine stack
# near 100 KB. Only a long input exposes that, so the test uses 200 KB.
def repeated(n: Nat, +acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      repeated(p, SCon{'a', acc})

def length_of(s: String, acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      length_of(t, 1n+acc)

def check_long_escape() -> IO(Unit):
  do IO<Unit>:
    ok("escapes a 200 KB string without overflowing the stack",
      Nat.is_eq(length_of(J.escape(repeated(200000n, SNil{})), 0n), 200000n))

# Regression: arr_of once recursed per element, so a long array overflowed the
# stack when the parser closed it. 100,000 elements is well past the limit.
def digits_csv(n: Nat, +acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      digits_csv(p, SCon{'1', SCon{',', acc}})

def check_long_array() -> IO(Unit):
  do IO<Unit>:
    body : J.Json <- body_of(J.parse("[" ++ digits_csv(100000n, SNil{}) ++ "1]"))
    ok("parses a 100,000 element array without overflowing the stack",
      U32.is_eq(J.count(body), 100001))
    again : J.Json <- body_of(J.parse("[" ++ digits_csv(100000n, SNil{}) ++ "1]"))
    ok("reads the last element of a 100,000 element array",
      String.eq(J.show(J.at_index(again, 100000n)), "1"))

# Regression: fields() once recursed per key, so a 100,000-key object overflowed.
# Keys repeat on purpose: the check is about length and order, not key uniqueness.
def keys_csv_obj(n: Nat, +acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      keys_csv_obj(p, "\"k\":1," ++ acc)

def field_count(xs: List<&2, J.JField>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case +h <> t:
      field_count(t, U32.add(1, acc))

def last_key(xs: List<&2, J.JField>,+last: String) -> String:
  match xs:
    case Nil{}:
      last
    case +h <> t:
      match h:
        case J.JField{key, value}:
          last_key(t, key)

def check_long_object() -> IO(Unit):
  do IO<Unit>:
    obj : J.Json <- body_of(J.parse("{" ++ keys_csv_obj(100000n, SNil{}) ++ "\"z\":1}"))
    ok("lists all 100,001 fields of a large object",
      U32.is_eq(field_count(J.fields(obj), 0), 100001))
    again : J.Json <- body_of(J.parse("{" ++ keys_csv_obj(100000n, SNil{}) ++ "\"z\":1}"))
    ok("keeps the last field last in a large object",
      String.eq(last_key(J.fields(again), ""), "z"))

def main() -> IO(Unit):
  do IO<Unit>:
    check_long_array()
    check_long_object()
    +parsed : J.Parsed = J.parse(doc())
    text : String <- roundtrip(parsed)
    ok("round trip is byte identical", String.eq(text, doc()))
    body : J.Json <- body_of(parsed)
    check_fields(body)
    check_errors()
    check_pretty()
    check_long_escape()
