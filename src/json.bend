import Base

# JSON, in both directions. Base ships none, so `bird` carries its own.
#
# Four rules shaped this file. They are properties of Bend, not preferences, and
# every module here obeys them, so they are stated once:
#
# 1. A def must be written *before* the def that calls it. There are no forward
#    declarations, and calling a later name is reported as an unfilled law.
#    The order of this file is therefore a dependency order, not a topic order.
#
# 2. Mutual recursion does not typecheck, and a recursive call must be on a
#    syntactically smaller part of one parameter. A recursive datatype whose
#    children sit in a *list* cannot be walked: `show` would need `show_items`,
#    which needs `show`. So an array or object here is a cons chain of `Json`
#    nodes (`JsonArr{head, tail}` ends in `JsonArrEnd{}`), never a `List<Json>`.
#    Every recursion is then on a field, which the checker accepts, and the
#    nesting depth is unbounded.
#
# 3. A `match` may only scrutinize a parameter or a field bound by a pattern.
#    A test on a computed value moves into either `Bool.pick` (both arms already
#    computed, fine for cheap values) or a small def that matches on its Bool
#    parameter (needed when an arm recurses).
#
# 4. Values are affine. A def that needs a value twice takes it `+`. `is Data`
#    means copyable, and a field of a `Data` type must be `Data` too, which is
#    why lists inside these types are written `List<&2, X>`.
#
# Numbers keep the text they were read as: a tweet id is 19 digits, and a
# Succ-chain Nat that long is not a number, it is a hang.

type Json is Data:
  JsonNull{}
  JsonBool{value: Bool}
  JsonNum{text: String}
  JsonStr{value: String}
  JsonArr{head: Json, tail: Json}
  JsonArrEnd{}
  JsonObj{key: String, value: Json, tail: Json}
  JsonObjEnd{}

type JField is Data:
  JField{key: String, value: Json}

type Parsed is Data:
  ParsedOk{value: Json}
  ParsedErr{message: String}

# ── character classes ───────────────────────────────────────────────────

def is_digit(+code: U32) -> Bool:
  Bool.and(U32.is_ge(code, 48), U32.is_le(code, 57))

def is_lower(+code: U32) -> Bool:
  Bool.and(U32.is_ge(code, 97), U32.is_le(code, 122))

def is_upper(+code: U32) -> Bool:
  Bool.and(U32.is_ge(code, 65), U32.is_le(code, 90))

def is_alpha(+code: U32) -> Bool:
  Bool.or(is_lower(code), is_upper(code))

def is_num_punct(code: U32) -> Bool:
  match code:
    case 45:
      True{}
    case 43:
      True{}
    case 46:
      True{}
    case 101:
      True{}
    case 69:
      True{}
    case _:
      False{}

def is_num_char(+code: U32) -> Bool:
  Bool.or(is_digit(code), is_num_punct(code))

def is_num_start(+code: U32) -> Bool:
  Bool.or(is_digit(code), U32.is_eq(code, 45))

def char_str(code: U32) -> String:
  Char.show(Char.from_u32(code))

# buf holds characters reversed: prepending is cheap, and the emit points
# reverse once.
def push_char(buf: String, code: U32) -> String:
  SCon{Char.from_u32(code), buf}

# ── writing ─────────────────────────────────────────────────────────────

def hex_digit(+n: U32) -> Char:
  Bool.pick(Char, U32.is_lt(n, 10), Char.from_u32(U32.add(48, n)), Char.from_u32(U32.add(87, n)))

def hex2(+n: U32) -> String:
  Char.show(hex_digit(U32.div(n, 16))) ++ Char.show(hex_digit(U32.mod(n, 16)))

def hex4(+n: U32) -> String:
  hex2(U32.div(n, 256)) ++ hex2(U32.mod(n, 256))

# A raw control byte must not reach the wire unescaped, and JSON has no short
# form for the rest of them, so they become \u00XX.
def escape_ctrl(+code: U32, c: Char) -> String:
  Bool.pick(String, U32.is_lt(code, 32), "\\u00" ++ hex2(code), Char.show(c))

def escape_code(+code: U32, c: Char) -> String:
  match code:
    case 34:
      "\\\""
    case 92:
      "\\\\"
    case 10:
      "\\n"
    case 13:
      "\\r"
    case 9:
      "\\t"
    case 8:
      "\\b"
    case 12:
      "\\f"
    case _:
      escape_ctrl(code, c)

def escape_ch(+c: Char) -> String:
  escape_code(Char.to_u32(c), c)

def escape(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      escape_ch(h) ++ escape(t)

def show_str(s: String) -> String:
  "\"" ++ escape(s) ++ "\""

def bool_text(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

# One def, because `show` and any helper that walks a container tail would be
# mutually recursive, and Bend rejects that. The "where am I in the document"
# question is answered by the `ctx` parameter and the "is this the last one?"
# question by the shape of the node, so every call is `show_ctx` calling itself
# on a field.
#
# The context is what keeps a chain from nesting: a tail node is a sibling
# continuation, not a child, so `[1,2]` prints `[1,2]` and never `[1,[2]]`.
#
# `a ++ b` copies `a` and leaves `b` alone, so this stays linear in the size of
# the document rather than quadratic.
type SCtx is Data:
  SCtxValue{}
  SCtxArrTail{}
  SCtxObjTail{}

def show_ctx(j: Json, ctx: SCtx) -> String:
  match j:
    case JsonNull{}:
      "null"
    case JsonBool{value}:
      bool_text(value)
    case JsonNum{text}:
      text
    case JsonStr{value}:
      show_str(value)
    case JsonArrEnd{}:
      match ctx:
        case SCtxArrTail{}:
          SNil{}
        case _:
          "[]"
    case JsonObjEnd{}:
      match ctx:
        case SCtxObjTail{}:
          SNil{}
        case _:
          "{}"
    case JsonArr{head, tail}:
      match ctx:
        case SCtxArrTail{}:
          "," ++ show_ctx(head, SCtxValue{}) ++ show_ctx(tail, SCtxArrTail{})
        case _:
          "[" ++ show_ctx(head, SCtxValue{}) ++ show_ctx(tail, SCtxArrTail{}) ++ "]"
    case JsonObj{key, value, tail}:
      match ctx:
        case SCtxObjTail{}:
          "," ++ show_str(key) ++ ":" ++ show_ctx(value, SCtxValue{}) ++ show_ctx(tail, SCtxObjTail{})
        case _:
          "{" ++ show_str(key) ++ ":" ++ show_ctx(value, SCtxValue{}) ++ show_ctx(tail, SCtxObjTail{}) ++ "}"

def show(j: Json) -> String:
  show_ctx(j, SCtxValue{})

# ── pretty ──────────────────────────────────────────────────────────────
#
# The same walk as `show`, with the depth carried in the context. A terminal is
# not a pipe: X's answer for one tweet is kilobytes on one line, and the human
# path is the one place the reader matters more than the bytes. `--json` still
# gets `show`, because an agent wants one line it can parse.
#
# The context says where the node sits, which is what decides its first
# characters. `PVal{depth}` is a value standing at that indent, printed inline.
# `PArrTail{parent, first}` and `PObjTail{parent, first}` are the slots of a
# container whose entries are at `parent + 1`, where `first` says whether this
# one starts its line or follows a comma. A slot holds the chain of what is left:
# for an array the node's own head is the element in that slot, so it is printed
# as a value and the tail carries on. The closing bracket is emitted by the end
# node of the chain, back at `parent`.
type PCtx is Data:
  PVal{depth: Nat}
  PArrTail{depth: Nat, first: Bool}
  PObjTail{depth: Nat, first: Bool}

def pad(n: Nat, +acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      pad(p, "  " ++ acc)

def ctx_depth(+ctx: PCtx) -> Nat:
  match ctx:
    case PVal{depth}:
      depth
    case PArrTail{depth, first}:
      depth
    case PObjTail{depth, first}:
      depth

# The indent of the node's own line: a value sits where it was put, a slot sits
# one level inside the container it belongs to.
def own(+ctx: PCtx) -> Nat:
  match ctx:
    case PVal{depth}:
      depth
    case PArrTail{depth, first}:
      Nat.add(depth, 1n)
    case PObjTail{depth, first}:
      Nat.add(depth, 1n)

# The newline before an entry, and the comma that separates it from the one
# before, except for a container's first.
def entry_lead(first: Bool, parent: Nat) -> String:
  match first:
    case True{}:
      "\n" ++ pad(Nat.add(parent, 1n), SNil{})
    case False{}:
      ",\n" ++ pad(Nat.add(parent, 1n), SNil{})

def lead(+ctx: PCtx) -> String:
  match ctx:
    case PVal{depth}:
      SNil{}
    case PArrTail{depth, first}:
      entry_lead(first, depth)
    case PObjTail{depth, first}:
      entry_lead(first, depth)

def closing(parent: Nat, +bracket: String) -> String:
  "\n" ++ pad(parent, SNil{}) ++ bracket

def pretty_ctx(j: Json, +ctx: PCtx) -> String:
  match j:
    case JsonNull{}:
      lead(ctx) ++ "null"
    case JsonBool{value}:
      lead(ctx) ++ bool_text(value)
    case JsonNum{text}:
      lead(ctx) ++ text
    case JsonStr{value}:
      lead(ctx) ++ show_str(value)
    case JsonArrEnd{}:
      match ctx:
        case PArrTail{depth, first}:
          closing(depth, "]")
        case _:
          "[]"
    case JsonObjEnd{}:
      match ctx:
        case PObjTail{depth, first}:
          closing(depth, "}")
        case _:
          "{}"
    case JsonArr{head, tail}:
      match ctx:
        case PArrTail{depth, first}:
          lead(ctx) ++ pretty_ctx(head, PVal{own(ctx)})
          ++ pretty_ctx(tail, PArrTail{depth, False{}})
        case _:
          "[" ++ entry_lead(True{}, own(ctx))
          ++ pretty_ctx(head, PVal{Nat.add(own(ctx), 1n)})
          ++ pretty_ctx(tail, PArrTail{own(ctx), False{}})
    case JsonObj{key, value, tail}:
      match ctx:
        case PObjTail{depth, first}:
          lead(ctx) ++ show_str(key) ++ ": " ++ pretty_ctx(value, PVal{own(ctx)})
          ++ pretty_ctx(tail, PObjTail{depth, False{}})
        case _:
          "{" ++ entry_lead(True{}, own(ctx)) ++ show_str(key) ++ ": "
          ++ pretty_ctx(value, PVal{Nat.add(own(ctx), 1n)})
          ++ pretty_ctx(tail, PObjTail{own(ctx), False{}})

def pretty(j: Json) -> String:
  pretty_ctx(j, PVal{0n})

# ── builders ────────────────────────────────────────────────────────────

def of_str(s: String) -> Json:
  JsonStr{s}

def of_u32(n: U32) -> Json:
  JsonNum{U32.show(n)}

def of_bool(b: Bool) -> Json:
  JsonBool{b}

def null() -> Json:
  JsonNull{}

# A missing string becomes JSON `null`, so an absent field reads as absent
# instead of as an empty string an agent could mistake for a real value.
def of_maybe_str(m: Maybe<&2, String>) -> Json:
  match m:
    case None{}:
      JsonNull{}
    case Some{s}:
      JsonStr{s}

def pair(key: String, value: Json) -> JField:
  JField{key, value}

def pairs1(a: JField) -> List<&2, JField>:
  a <> Nil{}

def pairs2(a: JField, b: JField) -> List<&2, JField>:
  a <> (b <> Nil{})

def pairs3(a: JField, b: JField, c: JField) -> List<&2, JField>:
  a <> (b <> (c <> Nil{}))

def pairs4(a: JField, b: JField, c: JField, d: JField) -> List<&2, JField>:
  a <> (b <> (c <> (d <> Nil{})))

def pairs5(a: JField, b: JField, c: JField, d: JField, e: JField) -> List<&2, JField>:
  a <> (b <> (c <> (d <> (e <> Nil{}))))

def pairs6(a: JField, b: JField, c: JField, d: JField, e: JField, f: JField) -> List<&2, JField>:
  a <> (b <> (c <> (d <> (e <> (f <> Nil{})))))

def pairs7(a: JField, b: JField, c: JField, d: JField, e: JField, f: JField, g: JField) -> List<&2, JField>:
  a <> (b <> (c <> (d <> (e <> (f <> (g <> Nil{}))))))

def pairs8(a: JField, b: JField, c: JField, d: JField, e: JField, f: JField, g: JField, h: JField) -> List<&2, JField>:
  a <> (b <> (c <> (d <> (e <> (f <> (g <> (h <> Nil{})))))))

def arr_of(xs: List<&2, Json>) -> Json:
  match xs:
    case Nil{}:
      JsonArrEnd{}
    case +h <> t:
      JsonArr{h, arr_of(t)}

def obj_push(f: JField, acc: Json) -> Json:
  match f:
    case JField{key, value}:
      JsonObj{key, value, acc}

# The fold prepends, so the list is reversed first to keep field order.
def obj_acc(fs: List<&2, JField>,+acc: Json) -> Json:
  match fs:
    case Nil{}:
      acc
    case +f <> t:
      obj_acc(t, obj_push(f, acc))

def obj_of(fs: List<&2, JField>) -> Json:
  obj_acc(List.reverse(&2, JField, fs), JsonObjEnd{})

def obj1(a: JField) -> Json:
  obj_of(pairs1(a))

def obj2(a: JField, b: JField) -> Json:
  obj_of(pairs2(a, b))

def obj3(a: JField, b: JField, c: JField) -> Json:
  obj_of(pairs3(a, b, c))

def obj4(a: JField, b: JField, c: JField, d: JField) -> Json:
  obj_of(pairs4(a, b, c, d))

def obj5(a: JField, b: JField, c: JField, d: JField, e: JField) -> Json:
  obj_of(pairs5(a, b, c, d, e))

def obj6(a: JField, b: JField, c: JField, d: JField, e: JField, f: JField) -> Json:
  obj_of(pairs6(a, b, c, d, e, f))

def obj7(a: JField, b: JField, c: JField, d: JField, e: JField, f: JField, g: JField) -> Json:
  obj_of(pairs7(a, b, c, d, e, f, g))

def obj8(a: JField, b: JField, c: JField, d: JField, e: JField, f: JField, g: JField, h: JField) -> Json:
  obj_of(pairs8(a, b, c, d, e, f, g, h))

# ── reading ─────────────────────────────────────────────────────────────

def prefer_new(same: Bool, v: Json) -> Maybe<&2, Json>:
  match same:
    case True{}:
      Some{v}
    case False{}:
      None{}

# A lookup that stopped early would need a branch that tests the key and calls
# back into the lookup: mutual recursion, which Bend rejects. So the walk is
# unconditional and carries the answer, and the key test is a leaf. The first
# key wins, which is how every JSON reader resolves a duplicated field.
def prefer_found(same: Bool, v: Json, found: Maybe<&2, Json>) -> Maybe<&2, Json>:
  match found:
    case Some{f}:
      Some{f}
    case None{}:
      prefer_new(same, v)

def get_go(chain: Json,+key: String,+found: Maybe<&2, Json>) -> Maybe<&2, Json>:
  match chain:
    case JsonObj{k, v, rest}:
      get_go(rest, key, prefer_found(String.eq(k, key), v, found))
    case _:
      found

def get(j: Json, key: String) -> Maybe<&2, Json>:
  get_go(j, key, None{})

def or_null(m: Maybe<&2, Json>) -> Json:
  match m:
    case None{}:
      JsonNull{}
    case Some{v}:
      v

def get_or_null(j: Json, key: String) -> Json:
  or_null(get(j, key))

def text_of(j: Json) -> Maybe<&2, String>:
  match j:
    case JsonStr{value}:
      Some{value}
    case JsonNum{text}:
      Some{text}
    case _:
      None{}

def text_got(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      SNil{}
    case Some{s}:
      s

def text(j: Json) -> String:
  text_got(text_of(j))

# GraphQL is inconsistent about a scalar field and `{"rest_id": "..."}`, so a
# text read falls back to the wrapper X uses for ids.
def rest_got(m: Maybe<&2, String>, j: Json) -> String:
  match m:
    case Some{s}:
      s
    case None{}:
      text(get_or_null(j, "rest_id"))

def rest_text(+j: Json) -> String:
  rest_got(text_of(j), j)

def text_found(m: Maybe<&2, Json>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{v}:
      text_of(v)

def any_got(m: Maybe<&2, Json>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{v}:
      True{}

def u32_read(r: Maybe<&2, U32>) -> U32:
  match r:
    case None{}:
      0
    case Some{n}:
      n

def u32_got(m: Maybe<&2, String>) -> U32:
  match m:
    case None{}:
      0
    case Some{s}:
      u32_read(U32.read(s))

def u32(j: Json) -> U32:
  u32_got(text_of(j))

def bool(j: Json) -> Bool:
  match j:
    case JsonBool{value}:
      value
    case _:
      False{}

def is_null(j: Json) -> Bool:
  match j:
    case JsonNull{}:
      True{}
    case _:
      False{}

# A config file has to be an object; `fields` of anything else is empty, which
# would silently mean "no settings" rather than "the file is the wrong shape".
def is_obj(j: Json) -> Bool:
  match j:
    case JsonObj{key, value, tail}:
      True{}
    case JsonObjEnd{}:
      True{}
    case _:
      False{}

# An array, empty or not. `is_arr_end` is also true of anything that is not an
# array -- that is how a missing path reads as an empty list -- so a caller that
# has to tell `[]` from `null` needs this rather than that.
def is_arr(j: Json) -> Bool:
  match j:
    case JsonArr{head, tail}:
      True{}
    case JsonArrEnd{}:
      True{}
    case _:
      False{}

# `JsonArrEnd{}` is also the answer for "not an array at all", which keeps a
# missing path and an empty array distinguishable by length.
def arr_tail(j: Json) -> Json:
  match j:
    case JsonArr{head, tail}:
      tail
    case _:
      JsonArrEnd{}

def is_arr_end(j: Json) -> Bool:
  match j:
    case JsonArrEnd{}:
      True{}
    case _:
      False{}

def items(j: Json) -> List<&2, Json>:
  match j:
    case JsonArr{head, tail}:
      head <> items(tail)
    case _:
      Nil{}

# Array element by position, as JSON `null` when out of range, so a caller can
# read a timeline slot without unwrapping a Maybe.
def at_index(j: Json, n: Nat) -> Json:
  or_null(List.get(&2, Json, items(j), n))

def fields(j: Json) -> List<&2, JField>:
  match j:
    case JsonObj{key, value, tail}:
      JField{key, value} <> fields(tail)
    case _:
      Nil{}

# The keys alone, for callers that only need to check names: a walk over strings
# needs no destructuring step, so it stays one self-recursive def.
def keys(j: Json) -> List<&2, String>:
  match j:
    case JsonObj{key, value, tail}:
      key <> keys(tail)
    case _:
      Nil{}

def count(j: Json) -> U32:
  match j:
    case JsonArr{head, tail}:
      U32.add(1, count(tail))
    case _:
      0

def present(j: Json, key: String) -> Bool:
  any_got(get(j, key))

def at_end(ok: Bool, cur: Json) -> Maybe<&2, Json>:
  match ok:
    case True{}:
      Some{cur}
    case False{}:
      None{}

# Same reason as `get_go`: `ok` carries "a step already missed", so a
# missing key stops the answer without a recursive branch. The shrinking
# argument comes first: the checker reads arguments left to right and needs one
# to be a smaller part of a parameter before anything is transformed.
def at_go(path: List<&2, String>, +cur: Json, ok: Bool) -> Maybe<&2, Json>:
  match path:
    case Nil{}:
      at_end(ok, cur)
    case +k <> rest:
      at_go(rest, get_or_null(cur, k), Bool.and(ok, present(cur, k)))

def at(j: Json, path: List<&2, String>) -> Maybe<&2, Json>:
  at_go(path, j, True{})

def at1(j: Json, a: String) -> Maybe<&2, Json>:
  at(j, a <> Nil{})

def at2(j: Json, a: String, b: String) -> Maybe<&2, Json>:
  at(j, a <> (b <> Nil{}))

def at3(j: Json, a: String, b: String, c: String) -> Maybe<&2, Json>:
  at(j, a <> (b <> (c <> Nil{})))

def at4(j: Json, a: String, b: String, c: String, d: String) -> Maybe<&2, Json>:
  at(j, a <> (b <> (c <> (d <> Nil{}))))

def at5(j: Json, a: String, b: String, c: String, d: String, e: String) -> Maybe<&2, Json>:
  at(j, a <> (b <> (c <> (d <> (e <> Nil{})))))

def at6(j: Json, a: String, b: String, c: String, d: String, e: String, f: String) -> Maybe<&2, Json>:
  at(j, a <> (b <> (c <> (d <> (e <> (f <> Nil{}))))))

def at7(j: Json, a: String, b: String, c: String, d: String, e: String, f: String, g: String) -> Maybe<&2, Json>:
  at(j, a <> (b <> (c <> (d <> (e <> (f <> (g <> Nil{})))))))

def str_at(j: Json, path: List<&2, String>) -> Maybe<&2, String>:
  text_found(at(j, path))

def items_got(m: Maybe<&2, Json>) -> List<&2, Json>:
  match m:
    case None{}:
      Nil{}
    case Some{v}:
      items(v)

def items_at(j: Json, path: List<&2, String>) -> List<&2, Json>:
  items_got(at(j, path))

def items_at3(j: Json, a: String, b: String, c: String) -> List<&2, Json>:
  items_at(j, a <> (b <> (c <> Nil{})))

def items_at4(j: Json, a: String, b: String, c: String, d: String) -> List<&2, Json>:
  items_at(j, a <> (b <> (c <> (d <> Nil{}))))

def items_at5(j: Json, a: String, b: String, c: String, d: String, e: String) -> List<&2, Json>:
  items_at(j, a <> (b <> (c <> (d <> (e <> Nil{})))))

def items_at6(j: Json, a: String, b: String, c: String, d: String, e: String, f: String) -> List<&2, Json>:
  items_at(j, a <> (b <> (c <> (d <> (e <> (f <> Nil{}))))))

def items_at7(j: Json, a: String, b: String, c: String, d: String, e: String, f: String, g: String) -> List<&2, Json>:
  items_at(j, a <> (b <> (c <> (d <> (e <> (f <> (g <> Nil{})))))))

def u32_at_got(m: Maybe<&2, Json>, fallback: U32) -> U32:
  match m:
    case None{}:
      fallback
    case Some{v}:
      u32(v)

def u32_at(j: Json, path: List<&2, String>, fallback: U32) -> U32:
  u32_at_got(at(j, path), fallback)

def u32_at1(j: Json, a: String, fallback: U32) -> U32:
  u32_at(j, a <> Nil{}, fallback)

def u32_at4(j: Json, a: String, b: String, c: String, d: String, fallback: U32) -> U32:
  u32_at(j, a <> (b <> (c <> (d <> Nil{}))), fallback)

def has_path(j: Json, path: List<&2, String>) -> Bool:
  any_got(at(j, path))

def has2(j: Json, a: String, b: String) -> Bool:
  has_path(j, a <> (b <> Nil{}))

# ── the parser ──────────────────────────────────────────────────────────
#
# A character machine with an explicit container stack. One recursive def
# (`scan`) consumes one character per step and only ever recurses on the
# tail of the input, which is the shape the checker accepts.

type PMode is Data:
  PMIdle{}
  PMStr{esc: Bool}
  PMHex{left: U32, acc: U32}
  PMNum{}
  PMWord{}

type Frame is Data:
  FrameArr{items: List<&2, Json>}
  FrameObj{fields: List<&2, JField>, key: String}

# "Where does this value go": into the container on top of the stack, or out as
# the finished document, or nowhere because the input is malformed.
type Attached is Data:
  AttachMore{stack: List<&2, Frame>}
  AttachTop{value: Json}
  AttachErr{message: String}

type PSt is Data:
  PSt{
    mode: PMode,
    stack: List<&2, Frame>,
    value: Maybe<&2, Json>,
    buf: String,
    err: String,
  }

def fail(message: String, err: String) -> PSt:
  PSt{PMIdle{}, Nil{}, None{}, SNil{}, message}

def attach_key_on(nameless: Bool, j: Json, fields: List<&2, JField>,+key: String, rest: List<&2, Frame>) -> Attached:
  match nameless:
    case True{}:
      AttachErr{"object value with no key"}
    case False{}:
      AttachMore{FrameObj{JField{key, j} <> fields, SNil{}} <> rest}

def attach_obj_field(j: Json, fields: List<&2, JField>,+key: String, rest: List<&2, Frame>) -> Attached:
  attach_key_on(String.is_empty(key), j, fields, key, rest)

def attach_frame(+j: Json, f: Frame,+rest: List<&2, Frame>) -> Attached:
  match f:
    case FrameArr{items}:
      AttachMore{FrameArr{j <> items} <> rest}
    case FrameObj{fields, key}:
      attach_obj_field(j, fields, key, rest)

def attach(+j: Json, stack: List<&2, Frame>) -> Attached:
  match stack:
    case Nil{}:
      AttachTop{j}
    case +f <> rest:
      attach_frame(j, f, rest)

def attached(a: Attached, value: Maybe<&2, Json>,+err: String) -> PSt:
  match a:
    case AttachMore{stack}:
      PSt{PMIdle{}, stack, value, SNil{}, err}
    case AttachTop{j}:
      PSt{PMIdle{}, Nil{}, Some{j}, SNil{}, err}
    case AttachErr{message}:
      fail(message, err)

# A finished document needs no more input.
def has_value(+v: Maybe<&2, Json>) -> Bool:
  match v:
    case None{}:
      False{}
    case Some{j}:
      True{}

def done_on(taken: Bool, stack: List<&2, Frame>) -> Bool:
  match taken:
    case True{}:
      List.is_empty(&2, Frame, stack)
    case False{}:
      False{}

def done(stack: List<&2, Frame>, value: Maybe<&2, Json>) -> Bool:
  done_on(has_value(value), stack)

def blank(stack: List<&2, Frame>, value: Maybe<&2, Json>, err: String) -> PSt:
  PSt{PMIdle{}, stack, value, SNil{}, err}

def open_obj_on(finished: Bool, stack: List<&2, Frame>,+value: Maybe<&2, Json>,+err: String) -> PSt:
  match finished:
    case True{}:
      fail("trailing data after the top-level value", err)
    case False{}:
      PSt{PMIdle{}, FrameObj{Nil{}, SNil{}} <> stack, value, SNil{}, err}

def open_obj(+stack: List<&2, Frame>,+value: Maybe<&2, Json>, err: String) -> PSt:
  open_obj_on(done(stack, value), stack, value, err)

def open_arr_on(finished: Bool, stack: List<&2, Frame>,+value: Maybe<&2, Json>,+err: String) -> PSt:
  match finished:
    case True{}:
      fail("trailing data after the top-level value", err)
    case False{}:
      PSt{PMIdle{}, FrameArr{Nil{}} <> stack, value, SNil{}, err}

def open_arr(+stack: List<&2, Frame>,+value: Maybe<&2, Json>, err: String) -> PSt:
  open_arr_on(done(stack, value), stack, value, err)

def open_str_on(finished: Bool, stack: List<&2, Frame>,+value: Maybe<&2, Json>,+err: String) -> PSt:
  match finished:
    case True{}:
      fail("trailing data after the top-level value", err)
    case False{}:
      PSt{PMStr{False{}}, stack, value, SNil{}, err}

def open_str(+stack: List<&2, Frame>,+value: Maybe<&2, Json>, err: String) -> PSt:
  open_str_on(done(stack, value), stack, value, err)

def scalar_word_on(word: Bool, code: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>,+err: String) -> PSt:
  match word:
    case True{}:
      PSt{PMWord{}, stack, value, char_str(code), err}
    case False{}:
      fail("unexpected character", err)

def scalar_word(+code: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, err: String) -> PSt:
  scalar_word_on(is_alpha(code), code, stack, value, err)

def scalar_mode_on(num: Bool,+code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+err: String) -> PSt:
  match num:
    case True{}:
      PSt{PMNum{}, stack, value, char_str(code), err}
    case False{}:
      scalar_word(code, stack, value, err)

def scalar_mode(+code: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, err: String) -> PSt:
  scalar_mode_on(is_num_start(code), code, stack, value, err)

def start_scalar_on(finished: Bool, code: U32, stack: List<&2, Frame>,+value: Maybe<&2, Json>,+err: String) -> PSt:
  match finished:
    case True{}:
      fail("trailing data after the top-level value", err)
    case False{}:
      scalar_mode(code, stack, value, err)

# A number or a keyword starts with a character that is neither whitespace nor
# a structural byte.
def start_scalar(code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>, err: String) -> PSt:
  start_scalar_on(done(stack, value), code, stack, value, err)

def close_arr(stack: List<&2, Frame>, value: Maybe<&2, Json>,+err: String) -> PSt:
  match stack:
    case Nil{}:
      fail("unexpected ]", err)
    case FrameArr{items} <> rest:
      attached(attach(arr_of(List.reverse(&2, Json, items)), rest), value, err)
    case _:
      fail("] closes an object", err)

# A key that never got a value is a malformed object: `{"a":}` must be rejected
# rather than silently closed. (Separators are otherwise read leniently, so a
# trailing comma passes.)
def close_obj_key(key: String, fields: List<&2, JField>, rest: List<&2, Frame>, value: Maybe<&2, Json>, err: String) -> PSt:
  match key:
    case "":
      attached(attach(obj_of(List.reverse(&2, JField, fields)), rest), value, err)
    case _:
      fail("object value missing for a key", err)

def close_obj(stack: List<&2, Frame>, value: Maybe<&2, Json>, err: String) -> PSt:
  match stack:
    case Nil{}:
      fail("unexpected }", err)
    case FrameObj{fields, key} <> rest:
      close_obj_key(key, fields, rest, value, err)
    case _:
      fail("} closes an array", err)

def idle(+code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+err: String) -> PSt:
  match code:
    case 32:
      blank(stack, value, err)
    case 9:
      blank(stack, value, err)
    case 10:
      blank(stack, value, err)
    case 13:
      blank(stack, value, err)
    case 123:
      open_obj(stack, value, err)
    case 91:
      open_arr(stack, value, err)
    case 125:
      close_obj(stack, value, err)
    case 93:
      close_arr(stack, value, err)
    case 58:
      blank(stack, value, err)
    case 44:
      blank(stack, value, err)
    case 34:
      open_str(stack, value, err)
    case _:
      start_scalar(code, stack, value, err)

# ── inside a string ─────────────────────────────────────────────────────

def esc_plain(code: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, buf: String, err: String) -> PSt:
  PSt{PMStr{False{}}, stack, value, push_char(buf, code), err}

def hex_step2(+left: U32,+acc: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  Bool.pick(
    PSt,
    U32.is_zero(left),
    PSt{PMStr{False{}}, stack, value, push_char(buf, acc), err},
    PSt{PMHex{left, acc}, stack, value, buf, err}
  )

def after_escape(code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  match code:
    case 110:
      esc_plain(10, stack, value, buf, err)
    case 116:
      esc_plain(9, stack, value, buf, err)
    case 114:
      esc_plain(13, stack, value, buf, err)
    case 98:
      esc_plain(8, stack, value, buf, err)
    case 102:
      esc_plain(12, stack, value, buf, err)
    case 34:
      esc_plain(34, stack, value, buf, err)
    case 92:
      esc_plain(92, stack, value, buf, err)
    case 47:
      esc_plain(47, stack, value, buf, err)
    case 117:
      PSt{PMHex{4, 0}, stack, value, buf, err}
    case _:
      fail("invalid escape in string", err)

# A closed string is either an object key or a value, and which one it is
# depends on the container on top of the stack: an object waiting for a key has
# none yet. Getting this wrong attaches every key as if it were a field value.
def emit_obj_str(key: String, s: String, fields: List<&2, JField>, rest: List<&2, Frame>, value: Maybe<&2, Json>, err: String) -> PSt:
  match key:
    case "":
      PSt{PMIdle{}, FrameObj{fields, s} <> rest, value, SNil{}, err}
    case _:
      attached(attach(JsonStr{s}, FrameObj{fields, key} <> rest), value, err)

def emit_str_on(s: String, stack: List<&2, Frame>, value: Maybe<&2, Json>, err: String) -> PSt:
  match stack:
    case FrameObj{fields, key} <> rest:
      emit_obj_str(key, s, fields, rest, value, err)
    case _:
      attached(attach(JsonStr{s}, stack), value, err)

def emit_str(stack: List<&2, Frame>, value: Maybe<&2, Json>, buf: String, err: String) -> PSt:
  emit_str_on(String.reverse(buf), stack, value, err)

def in_str_plain(+code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  match code:
    case 34:
      emit_str(stack, value, buf, err)
    case 92:
      PSt{PMStr{True{}}, stack, value, buf, err}
    case _:
      PSt{PMStr{False{}}, stack, value, push_char(buf, code), err}

def in_str(+code: U32, esc: Bool,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  match esc:
    case True{}:
      after_escape(code, stack, value, buf, err)
    case False{}:
      in_str_plain(code, stack, value, buf, err)

# \uXXXX: four hex digits, one per step, assembled into a code point. A
# surrogate half is emitted as-is; pairing the halves would need lookahead this
# machine does not have, and X does not escape non-BMP characters in practice.
# The ceiling is documented rather than paid for.
def hex_val_on(digit: Bool, lower: Bool,+code: U32) -> U32:
  match digit:
    case True{}:
      U32.sub(code, 48)
    case False{}:
      Bool.pick(U32, lower, U32.sub(code, 87), U32.sub(code, 55))

def hex_val(+code: U32) -> U32:
  hex_val_on(is_digit(code), is_lower(code), code)

def is_hex(code: U32) -> Bool:
  U32.is_lt(hex_val(code), 16)

def hex_step(nibble: U32, left: U32, acc: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, buf: String, err: String) -> PSt:
  hex_step2(U32.sub(left, 1), U32.add(U32.mul(acc, 16), nibble), stack, value, buf, err)

def in_hex_on(ok: Bool, code: U32, left: U32, acc: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, buf: String,+err: String) -> PSt:
  match ok:
    case True{}:
      hex_step(hex_val(code), left, acc, stack, value, buf, err)
    case False{}:
      fail("bad hex digit in \\u escape", err)

def in_hex(+code: U32, left: U32, acc: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, buf: String, err: String) -> PSt:
  in_hex_on(is_hex(code), code, left, acc, stack, value, buf, err)

# ── numbers and keywords ────────────────────────────────────────────────

def num_value(buf: String) -> Json:
  JsonNum{String.reverse(buf)}

def word_of(w: String) -> Json:
  match w:
    case "true":
      JsonBool{True{}}
    case "false":
      JsonBool{False{}}
    case "null":
      JsonNull{}
    case _:
      JsonNull{}

def word_value(buf: String) -> Json:
  word_of(String.reverse(buf))

def idle_after_on(ok: Bool, code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+err: String) -> PSt:
  match ok:
    case True{}:
      idle(code, stack, value, err)
    case False{}:
      PSt{PMIdle{}, stack, value, SNil{}, err}

def idle_after(code: U32, st: PSt) -> PSt:
  match st:
    case PSt{mode, stack, value, buf, +err}:
      idle_after_on(String.is_empty(err), code, stack, value, err)

# The character that ends a number or a keyword is not part of it, so it is
# re-examined in the idle state once the pending token has been attached. That
# is the only reason `idle_after` exists.
def in_num_on(part: Bool,+code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  match part:
    case True{}:
      PSt{PMNum{}, stack, value, push_char(buf, code), err}
    case False{}:
      idle_after(code, attached(attach(num_value(buf), stack), value, err))

def in_num(+code: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, buf: String, err: String) -> PSt:
  in_num_on(is_num_char(code), code, stack, value, buf, err)

def in_word_on(part: Bool,+code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  match part:
    case True{}:
      PSt{PMWord{}, stack, value, push_char(buf, code), err}
    case False{}:
      idle_after(code, attached(attach(word_value(buf), stack), value, err))

def in_word(+code: U32, stack: List<&2, Frame>, value: Maybe<&2, Json>, buf: String, err: String) -> PSt:
  in_word_on(is_alpha(code), code, stack, value, buf, err)

# ── one step ────────────────────────────────────────────────────────────

def step_mode(mode: PMode,+code: U32,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  match mode:
    case PMIdle{}:
      idle(code, stack, value, err)
    case PMStr{esc}:
      in_str(code, esc, stack, value, buf, err)
    case PMHex{left, acc}:
      in_hex(code, left, acc, stack, value, buf, err)
    case PMNum{}:
      in_num(code, stack, value, buf, err)
    case PMWord{}:
      in_word(code, stack, value, buf, err)

def step(code: U32, st: PSt) -> PSt:
  match st:
    case PSt{mode, stack, value, buf, err}:
      step_mode(mode, code, stack, value, buf, err)

# ── end of input ────────────────────────────────────────────────────────

def finish_mode(mode: PMode,+stack: List<&2, Frame>,+value: Maybe<&2, Json>,+buf: String,+err: String) -> PSt:
  match mode:
    case PMIdle{}:
      PSt{PMIdle{}, stack, value, SNil{}, err}
    case PMNum{}:
      attached(attach(num_value(buf), stack), value, err)
    case PMWord{}:
      attached(attach(word_value(buf), stack), value, err)
    case PMStr{esc}:
      fail("unterminated string", err)
    case PMHex{left, acc}:
      fail("unterminated \\u escape", err)

def finish(st: PSt) -> PSt:
  match st:
    case PSt{mode, stack, value, buf, err}:
      finish_mode(mode, stack, value, buf, err)

def finalize_value(v: Maybe<&2, Json>) -> Parsed:
  match v:
    case None{}:
      ParsedErr{"no JSON value"}
    case Some{j}:
      ParsedOk{j}

def finalize_on(clean: Bool, err: String, value: Maybe<&2, Json>) -> Parsed:
  match clean:
    case False{}:
      ParsedErr{err}
    case True{}:
      finalize_value(value)

def finalize(st: PSt) -> Parsed:
  match st:
    case PSt{mode, stack, value, buf, +err}:
      finalize_on(String.is_empty(err), err, value)

def init_state() -> PSt:
  PSt{PMIdle{}, Nil{}, None{}, SNil{}, SNil{}}

# The machine keeps reading while no error has been recorded.
def live(st: PSt) -> Bool:
  match st:
    case PSt{mode, stack, value, buf, err}:
      String.is_empty(err)

# The one recursive def: every call is on the tail of the input. The "any error
# yet?" test is inlined rather than factored into a helper, because any helper
# between this def and its own recursive call would make the two mutually
# recursive. `st` is destructured for the test and rebuilt on the way out.
def scan(s: String,+st: PSt) -> PSt:
  match s:
    case SNil{}:
      finish(st)
    case SCon{h, t}:
      match st:
        case PSt{mode, stack, value, buf, err}:
          match err:
            case "":
              scan(t, step(Char.to_u32(h), PSt{mode, stack, value, buf, err}))
            case _:
              PSt{PMIdle{}, stack, value, SNil{}, err}

def parse(s: String) -> Parsed:
  finalize(scan(s, init_state()))
