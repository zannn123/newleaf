# Shared by newleaf's hooks (sourced, not run). Plain bash and POSIX tools,
# no Python. Claude Code hands paths over in native form (C:\... on Windows);
# unix_path turns them into what Git Bash's tools expect.

NEWLEAF_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# byte semantics everywhere: notes pass through untouched whatever the locale
# (Git Bash's grep, for one, cannot match a 4-byte character in UTF-8 mode)
export LC_ALL=C

unix_path() {
  if [ -n "$1" ] && command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}

# json_str KEY: the decoded value of the first "KEY": "..." in the JSON on stdin
# (\n \t \r \" \\ \/ and \uXXXX escapes undone, surrogate pairs joined).
json_str() {
  # the backslash and the quote are made with sprintf: awks differ on "\\" in
  # string literals (gawk 5.3 reads "\\u" as a \u escape)
  LC_ALL=C awk -v key="$1" '
    BEGIN { bs = sprintf("%c", 92); dq = sprintf("%c", 34) }
    function hex(h,   i, c, v) {
      v = 0; h = tolower(h)
      for (i = 1; i <= length(h); i++) {
        c = index("0123456789abcdef", substr(h, i, 1)) - 1
        if (c < 0) return -1
        v = v * 16 + c
      }
      return v
    }
    function utf8(cp) {
      if (cp < 128) return sprintf("%c", cp)
      if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
      if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
      return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
    }
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
      if (!match(buf, dq key dq "[ \t\r\n]*:[ \t\r\n]*" dq)) exit 1
      i = RSTART + RLENGTH; n = length(buf); out = ""
      while (i <= n) {
        c = substr(buf, i, 1)
        if (c == dq) break
        if (c != bs) { out = out c; i++; continue }
        e = substr(buf, i + 1, 1); i += 2
        if (e == "n") out = out "\n"
        else if (e == "t") out = out "\t"
        else if (e == "r") out = out "\r"
        else if (e == "u") {
          cp = hex(substr(buf, i, 4)); i += 4
          if (cp >= 55296 && cp < 56320 && substr(buf, i, 1) == bs && substr(buf, i + 1, 1) == "u") {
            lo = hex(substr(buf, i + 2, 4))
            if (lo >= 56320 && lo < 57344) { cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); i += 6 }
          }
          if (cp >= 32 || cp == 9 || cp == 10) out = out utf8(cp)
        }
        else if (e != "b" && e != "f") out = out e
      }
      printf "%s", out
    }'
}

# project_dir JSON: the folder the session runs in
project_dir() {
  local dir=${CLAUDE_PROJECT_DIR:-}
  [ -n "$dir" ] || dir=$(printf '%s' "$1" | json_str cwd)
  unix_path "${dir:-$PWD}"
}

# config KEY PROJECT: a setting from <project>/.newleaf/config.json, else ~/.claude/newleaf.json
config() {
  local f v
  for f in "$2/.newleaf/config.json" "$HOME/.claude/newleaf.json"; do
    [ -f "$f" ] || continue
    v=$(sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" "$f" | head -n 1)
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  return 0
}

# calls: from transcript lines on stdin, the input size of each main-thread API
# call (fresh + cache write + cache read), and "reset" where a compaction falls
calls() {
  LC_ALL=C awk '
    function num(k) { return match($0, "\"" k "\":[0-9]+") ? substr($0, RSTART + length(k) + 3, RLENGTH - length(k) - 3) + 0 : 0 }
    index($0, "\"compact_boundary\"") { print "reset"; next }
    index($0, "\"type\":\"assistant\"") && index($0, "\"usage\"") && !index($0, "\"isSidechain\":true") {
      s = num("input_tokens") + num("cache_creation_input_tokens") + num("cache_read_input_tokens")
      if (s > 0) print s
    }'
}
