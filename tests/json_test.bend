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

def main() -> IO(Unit):
  do IO<Unit>:
    +parsed : J.Parsed = J.parse(doc())
    text : String <- roundtrip(parsed)
    ok("round trip is byte identical", String.eq(text, doc()))
    body : J.Json <- body_of(parsed)
    check_fields(body)
    check_errors()
    check_pretty()
