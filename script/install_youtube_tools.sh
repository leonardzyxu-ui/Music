#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/Tools"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"

if [[ -z "$PYTHON_BIN" || ! -x "$PYTHON_BIN" ]]; then
  echo "python3 was not found. Install Python 3 first." >&2
  exit 1
fi

mkdir -p "$TOOLS/python" "$TOOLS/bin"

install_with_pip() {
  "$PYTHON_BIN" -m pip install --upgrade --target "$TOOLS/python" yt-dlp
}

install_with_wheel() {
  local tmp_dir wheel_url wheel_file

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl was not found, and pip install failed." >&2
    return 1
  fi

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  wheel_url="$(
    curl -fsSL https://pypi.org/simple/yt-dlp/ |
      "$PYTHON_BIN" -c '
import html.parser
import re
import sys

links = []

class Parser(html.parser.HTMLParser):
    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        attrs = dict(attrs)
        href = attrs.get("href", "")
        if "py3-none-any.whl" in href:
            links.append(href)

Parser().feed(sys.stdin.read())
if not links:
    raise SystemExit("No yt-dlp wheel found on PyPI")

def version_key(url):
    name = url.rsplit("/", 1)[-1].split("#", 1)[0]
    match = re.search(r"yt_dlp-([^-]+)-", name)
    version = match.group(1) if match else ""
    return [int(part) if part.isdigit() else part for part in re.split(r"([0-9]+)", version)]

print(sorted(links, key=version_key)[-1])
'
  )"

  wheel_file="$tmp_dir/yt-dlp.whl"
  curl -fL "$wheel_url" -o "$wheel_file"
  rm -rf "$TOOLS/python/yt_dlp" "$TOOLS/python/yt_dlp-"*.dist-info
  "$PYTHON_BIN" -m zipfile -e "$wheel_file" "$TOOLS/python"
}

if ! install_with_pip; then
  echo "pip install failed; trying direct PyPI wheel download." >&2
  install_with_wheel
fi

cat > "$TOOLS/bin/yt-dlp" <<SH
#!/usr/bin/env bash
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="\${PYTHON_BIN:-$PYTHON_BIN}"
if [[ ! -x "\$PYTHON_BIN" ]]; then
  PYTHON_BIN="\$(command -v python3)"
fi
if [[ -z "\${SSL_CERT_FILE:-}" && -f /etc/ssl/cert.pem ]]; then
  export SSL_CERT_FILE=/etc/ssl/cert.pem
fi
if [[ -z "\${REQUESTS_CA_BUNDLE:-}" && -n "\${SSL_CERT_FILE:-}" ]]; then
  export REQUESTS_CA_BUNDLE="\$SSL_CERT_FILE"
fi
PYTHONPATH="\$ROOT/python" exec "\$PYTHON_BIN" -m yt_dlp "\$@"
SH
chmod +x "$TOOLS/bin/yt-dlp"

"$TOOLS/bin/yt-dlp" --version
echo "yt-dlp is ready for Music at $TOOLS/bin/yt-dlp"
