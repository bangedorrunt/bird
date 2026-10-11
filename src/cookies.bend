import Base
import ./scan.bend as S

# The session cookies, read out of a browser's own cookie store.
#
# There is no SQLite in the language and no AES either, so both are reached the
# way every other effect here is: a program run with an argv list, no shell, and
# nothing of the caller's on a command line that could become syntax. What this
# module owns is the *shape* of those calls and the reading of what they answer,
# which is pure, so all of it is testable without a browser.
#
# Firefox is the easy one: `cookies.sqlite` keeps the values in plain text, so one
# `sqlite3` call answers both cookies and no cipher is involved.
#
# Chrome encrypts them. On macOS the key is a password in the login keychain
# ("Chrome Safe Storage") and the value is `v10` followed by AES-128-CBC over the
# cookie with a fixed IV; the key is PBKDF2-HMAC-SHA1 of that password with the
# salt `saltysalt` and 1003 rounds. That is the whole recipe, and it is why the
# Chrome path costs more calls than the Firefox one:
#
#   sqlite3   write both encrypted blobs to two files (they are binary, and a
#             binary value must not travel through a string here)
#   security  the keychain password, unless `--chrome-key` supplied it
#   openssl   derive the key (PBKDF2)
#   openssl   decrypt each blob, which answers text
#   rm        take the blobs away again
#
# The temp files are the one place this leaves the encrypted cookies on disk, and
# they are written into the per-user temp directory the OS already made private
# for this process. `--chrome-key` exists so the recipe is testable without a
# keychain, which is also what makes it usable on a machine that keeps its key
# somewhere else.

# ── what is read, and from where ────────────────────────────────────────

def Cookies.at_name() -> String:
  "auth_token"

def Cookies.ct0_name() -> String:
  "ct0"

# `.x.com` is what the browser stores for a cookie set on the whole domain, and
# `%x.com` also catches the `x.com` and `twitter.com` spellings, because a session
# written under any of them is the same session.
def Cookies.host_like() -> String:
  "%x.com"

def Cookies.sep() -> Char:
  '|'

def Cookies.newline() -> Char:
  '\n'

def Cookies.cookie_names() -> String:
  "('" ++ Cookies.at_name() ++ "','" ++ Cookies.ct0_name() ++ "')"

def Cookies.host_clause() -> String:
  "host like '" ++ Cookies.host_like() ++ "' and name in " ++ Cookies.cookie_names()

def Cookies.firefox_sql() -> String:
  "select name, value from moz_cookies where " ++ Cookies.host_clause() ++ ";"

def Cookies.path(+dir: String, +name: String) -> String:
  dir ++ "/" ++ name

def Cookies.write_one(+dir: String, +name: String) -> String:
  "select writefile('" ++ Cookies.path(dir, name) ++ "', encrypted_value) from cookies where host_key like '"
  ++ Cookies.host_like() ++ "' and name='" ++ name ++ "';"

# Two statements, because `writefile` writes one file per row and the values are
# blobs: a blob must not be read into a string here, so it goes straight to a file
# that `openssl` can read. The counted bytes are printed, which is how a run can
# tell that a cookie was missing rather than empty.
def Cookies.chrome_sql(+dir: String) -> String:
  Cookies.write_one(dir, Cookies.at_name()) ++ " " ++ Cookies.write_one(dir, Cookies.ct0_name())

# ── the commands ────────────────────────────────────────────────────────

def Cookies.sqlite3() -> String:
  "sqlite3"

def Cookies.sqlite_args(+db: String, +sql: String) -> List<&2, String>:
  "-readonly" <> ("-noheader" <> (db <> (sql <> Nil{})))

def Cookies.security() -> String:
  "security"

def Cookies.security_args() -> List<&2, String>:
  "find-generic-password" <> ("-w" <> ("-s" <> ("Chrome Safe Storage" <> Nil{})))

def Cookies.openssl() -> String:
  "openssl"

def Cookies.salt_hex() -> String:
  "73616c747973616c74"

def Cookies.iv_hex() -> String:
  "20202020202020202020202020202020"

def Cookies.iterations() -> String:
  "1003"

# `openssl kdf` prints the derived key as `AA:BB:…`; the cipher wants it without
# the separators, which `Scan.uncolon` takes off.
def Cookies.kdf_args(+password: String) -> List<&2, String>:
  "kdf" <> (
    "-keylen" <> (
      "16" <> (
        "-kdfopt" <> (
          "digest:SHA1" <> (
            "-kdfopt" <> (
              ("pass:" ++ password) <> (
                "-kdfopt" <> (
                  ("hexsalt:" ++ Cookies.salt_hex()) <> (
                    "-kdfopt" <> (
                      ("iter:" ++ Cookies.iterations()) <> (
                        "PBKDF2" <> Nil{}
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )

def Cookies.decrypt_args(+key: String, +path: String) -> List<&2, String>:
  "enc" <> (
    "-aes-128-cbc" <> (
      "-d" <> (
        "-K" <> (
          key <> (
            "-iv" <> (
              Cookies.iv_hex() <> (
                "-nopad" <> ("-in" <> (path <> Nil{}))
              )
            )
          )
        )
      )
    )
  )

def Cookies.rm_args(+dir: String) -> List<&2, String>:
  "-f" <> (
    Cookies.path(dir, Cookies.at_name()) <> (
      Cookies.path(dir, Cookies.ct0_name()) <> Nil{}
    )
  )

# ── reading the answers ─────────────────────────────────────────────────

# One field of a `name<sep>value` line. Bounded, because the value is a session
# token of a few hundred characters and never a document.
def Cookies.field(+out: String, +name: String, bound: Nat) -> String:
  S.Scan.token_or_nothing(S.Scan.after(
    out,
    name ++ SCon{Cookies.sep(), SNil{}},
    Cookies.newline(),
    bound
  ))

def Cookies.firefox_at(+out: String) -> String:
  Cookies.field(out, Cookies.at_name(), 512n)

def Cookies.firefox_ct0(+out: String) -> String:
  Cookies.field(out, Cookies.ct0_name(), 512n)

def Cookies.key_of(+out: String) -> String:
  S.Scan.uncolon(String.trim(out))

# What Chrome prepends to the plaintext before it encrypts it. A value that does
# not carry it was not decrypted with the right key, which is the one way this can
# be wrong without failing outright.
def Cookies.v10_cut(prefixed: Bool, +s: String) -> String:
  match prefixed:
    case True{}:
      String.drop(s, 3n)
    case False{}:
      s

def Cookies.trim_v10(+s: String) -> String:
  Cookies.v10_cut(String.starts_with(s, "v10"), s)

# A decrypted cookie is trimmed, has Chrome's marker taken off, and is then
# checked. The check is the point: a wrong key answers bytes, not an error, so
# bytes that are not a token have to read as a refusal rather than as a cookie.
def Cookies.printable(+c: Char) -> Bool:
  Bool.and(Bool.not(Char.is_space(c)), Bool.not(Char.is_eq(c, S.Scan.quote())))

# A session token is printable and holds no space, quote or control character. A
# wrong key satisfies none of that: AES answers uniform bytes.
def Cookies.clean(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      Bool.and(Cookies.printable(h), Cookies.clean(t))

def Cookies.accept(ok: Bool, +value: String) -> String:
  match ok:
    case True{}:
      value
    case False{}:
      SNil{}

def Cookies.chrome_value(+out: String) -> String:
  +value : String = Cookies.trim_v10(String.trim(out))
  Cookies.accept(Cookies.clean(value), value)

# Both cookies or neither: a session is an account and its CSRF token, and one
# without the other is a request X refuses with a 403 that says nothing about which
# half was missing.
def Cookies.present(+at: String, +ct0: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(at)), Bool.not(String.is_empty(ct0)))

# What `openssl kdf` answers with is 16 bytes of hex once the separators are gone.
# A different length means the derivation did not happen, and every step after it
# would be decrypting with a key that is not a key.
def Cookies.key_ok(+key: String) -> Bool:
  Nat.is_eq(String.length(key), 32n)

# ── the last of it ──────────────────────────────────────────────────────

def Cookies.chmod() -> String:
  "chmod"

def Cookies.chmod_args(+path: String) -> List<&2, String>:
  "600" <> (path <> Nil{})
