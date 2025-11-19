#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/preview-telegram-message.sh [options] path/to/post.md

Options:
  --site URL   Override SITE_BASE_URL (can also use env var)
  --send       Actually send the message using TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
  --help       Show this help

Without --send the script simply prints the HTML payload so you can see how Telegram
rendering will look without creating a commit/push.
EOF
}

SITE_BASE_URL="${SITE_BASE_URL:-}"
SEND_MESSAGE=0
POST_FILE=""

first_words() {
  local file="$1"
  local limit="${2:-50}"
  local body
  body=$(awk '
    BEGIN { front=0 }
    /^---[ \t]*$/ {
      front++
      next
    }
    {
      if (front >= 2) { print }
    }
  ' "$file")

  body=$(printf '%s' "$body" | sed 's/{%[^%]*%}//g' | tr '\n' ' ')
  body=$(printf '%s' "$body" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')

  if [[ -z "$body" ]]; then
    printf 'Nuovo post sul blog...'
    return
  fi

  local snippet
  snippet=$(printf '%s\n' "$body" | awk -v limit="$limit" '{
    out=""
    for (i = 1; i <= NF && i <= limit; i++) {
      out = out (i == 1 ? "" : " ") $i
    }
    print out
  }')

  if [[ -z "$snippet" ]]; then
    printf 'Nuovo post sul blog...'
  else
    printf '%s...' "$snippet"
  fi
}

telegram_text() {
  local file="$1"
  local raw
  raw=$(awk '
    /^telegram:/ {
      sub(/^telegram:[ ]*/, "", $0);
      gsub(/^"/, "", $0);
      gsub(/"$/, "", $0);
      print;
      exit;
    }
  ' "$file")

  if [[ -n "$raw" ]]; then
    printf '%s' "$raw"
  else
    first_words "$file" 50
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site)
      shift
      SITE_BASE_URL="${1:-}"
      ;;
    --send)
      SEND_MESSAGE=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      POST_FILE="$1"
      ;;
  esac
  shift || true
done

if [[ -z "$POST_FILE" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$POST_FILE" ]]; then
  echo "File not found: $POST_FILE" >&2
  exit 1
fi

if [[ -z "$SITE_BASE_URL" ]]; then
  SITE_BASE_URL="https://example.com"
fi

# Extract title
TITLE=$(awk '/^title:/ {sub(/^title:[ ]*/, "", $0); print; exit}' "$POST_FILE")
[[ -z "$TITLE" ]] && TITLE="Nuovo post"

TELEGRAM_TEXT=$(telegram_text "$POST_FILE")

escape_html() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

TITLE_ESCAPED=$(escape_html "$TITLE")
TELEGRAM_ESCAPED=$(escape_html "$TELEGRAM_TEXT")

BASENAME=$(basename "$POST_FILE" .md)
YEAR=$(echo "$BASENAME" | cut -d'-' -f1)
MONTH=$(echo "$BASENAME" | cut -d'-' -f2)
DAY=$(echo "$BASENAME" | cut -d'-' -f3)
SLUG=$(echo "$BASENAME" | cut -d'-' -f4-)

POST_PATH="/${YEAR}/${MONTH}/${DAY}/${SLUG}/"
POST_URL="${SITE_BASE_URL%/}${POST_PATH}"

TEXT=$(printf '<b>%s</b>\n&gt; %s\n<a href="%s">Leggi</a>' \
  "${TITLE_ESCAPED}" \
  "${TELEGRAM_ESCAPED}" \
  "${POST_URL}")

echo "----- Telegram HTML payload -----"
printf '%s\n' "$TEXT"
echo "---------------------------------"

if [[ $SEND_MESSAGE -eq 1 ]]; then
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set to use --send" >&2
    exit 1
  fi

  echo "Sending preview message to chat ${TELEGRAM_CHAT_ID}..."
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${TEXT}" \
    -d "parse_mode=HTML"
  echo
fi
