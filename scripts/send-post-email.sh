#!/usr/bin/env bash
# Usage: called by .github/workflows/notify-email-on-new-post.yml
set -e

# ── helpers ────────────────────────────────────────────────────────────────────

base64url() {
  printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '='
}

make_unsub_token() {
  local email="$1" lang="$2"
  local payload
  payload=$(base64url "${email}|${lang}|0")
  local sig
  sig=$(printf '%s' "${payload}" \
    | openssl dgst -sha256 -hmac "${HMAC_SECRET}" -binary \
    | base64 | tr '+/' '-_' | tr -d '=')
  printf '%s.%s' "${payload}" "${sig}"
}

url_encode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()),end="")'
}

# Strip Jekyll frontmatter, return markdown body
extract_body() {
  awk 'BEGIN{n=0} /^---/{n++; next} n>=2{print}' "$1"
}

# Render full email HTML — body written to temp file, metadata via env vars
build_email_html() {
  local file="$1"
  local tmp_md tmp_html
  tmp_md=$(mktemp)
  tmp_html=$(mktemp)

  extract_body "$file" > "$tmp_md"
  pandoc --from=markdown --to=html --no-highlight "$tmp_md" > "$tmp_html"
  rm "$tmp_md"

  EMAIL_TITLE="$2" EMAIL_DATE="$3" EMAIL_POST_URL="$4" \
  EMAIL_UNSUB_URL="$5" EMAIL_UNSUB_LABEL="$6" \
  EMAIL_BODY_FILE="$tmp_html" \
  python3 - << 'PYEOF'
import os, re

title       = os.environ['EMAIL_TITLE']
date_str    = os.environ['EMAIL_DATE']
unsub_url   = os.environ['EMAIL_UNSUB_URL']
unsub_label = os.environ['EMAIL_UNSUB_LABEL']
body_file   = os.environ['EMAIL_BODY_FILE']

with open(body_file) as f:
    body = f.read()

os.unlink(body_file)

body = re.sub(r'<p>',          r'<p style="margin:0 0 1.4em 0">',                                                   body)
body = re.sub(r'<h2>',         r'<h2 style="font-weight:400;font-size:1.3em;margin:2em 0 0.5em 0">',                body)
body = re.sub(r'<h3>',         r'<h3 style="font-weight:400;font-size:1.1em;margin:1.5em 0 0.5em 0">',              body)
body = re.sub(r'<a ',          r'<a style="color:#222222" ',                                                         body)
body = re.sub(r'<blockquote>', r'<blockquote style="border-left:2px solid #ccc;margin:1.5em 0;padding:0 0 0 20px;color:#555">', body)
body = re.sub(r'<ul>',         r'<ul style="padding-left:1.5em;margin:0 0 1.4em 0">',                               body)
body = re.sub(r'<ol>',         r'<ol style="padding-left:1.5em;margin:0 0 1.4em 0">',                               body)
body = re.sub(r'<li>',         r'<li style="margin-bottom:0.4em">',                                                  body)
body = re.sub(r'<hr\s*/?>',    r'<hr style="border:none;border-top:1px solid #e0dbd3;margin:2em 0">',               body)

print(f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;1,400&display=swap" rel="stylesheet">
<style>
body{{font-family:"EB Garamond",Georgia,"Times New Roman",serif;background:#ffffff;color:#222222;margin:0;padding:0;font-size:20px;line-height:1.7;-webkit-font-smoothing:antialiased}}
.wrapper{{max-width:600px;margin:0 auto;padding:48px 32px}}
h1{{font-family:"EB Garamond",Georgia,serif;font-weight:400;font-size:2em;line-height:1.2;margin:0 0 12px 0;color:#222222}}
.meta{{font-size:0.75em;color:#888888;margin:0 0 2em 0;font-family:monospace}}
.footer{{margin-top:3em;padding-top:1.5em;border-top:1px solid #e0dbd3;font-size:0.75em;color:#999999}}
.footer a{{color:#999999}}
</style>
</head>
<body>
<div class="wrapper">
  <h1>{title}</h1>
  <p class="meta">{date_str}</p>
  <div class="content">{body}</div>
  <div class="footer"><a href="{unsub_url}">{unsub_label}</a></div>
</div>
</body>
</html>""")
PYEOF

}

# ── detect new posts ───────────────────────────────────────────────────────────

if [ -n "$BEFORE_SHA" ] && [ "$BEFORE_SHA" != "0000000000000000000000000000000000000000" ]; then
  DIFF_OUTPUT=$(git diff --name-status "$BEFORE_SHA" "${GITHUB_SHA}")
else
  DIFF_OUTPUT=$(git show --name-status --pretty="" "${GITHUB_SHA}")
fi

CHANGED_POSTS=$(printf '%s\n' "$DIFF_OUTPUT" \
  | awk '$1 == "A" { print $2 }' \
  | grep -E '^(it|en)/_posts/' || true)

if [ -z "$CHANGED_POSTS" ]; then
  echo "No new posts found."
  exit 0
fi

# ── process each new post ──────────────────────────────────────────────────────

for FILE in $CHANGED_POSTS; do
  [ -f "$FILE" ] || continue

  LANG=$(printf '%s' "$FILE" | cut -d'/' -f1)
  [ "$LANG" = "it" ] || [ "$LANG" = "en" ] || continue

  if [ "$LANG" = "it" ]; then
    SEGMENT_ID="${RESEND_SEGMENT_ID_IT}"
    UNSUB_LABEL="Disiscriviti"
  else
    SEGMENT_ID="${RESEND_SEGMENT_ID_EN}"
    UNSUB_LABEL="Unsubscribe"
  fi

  TITLE=$(awk '/^title:/ { sub(/^title:[ "]*/, ""); sub(/"[ ]*$/, ""); print; exit }' "$FILE")
  [ -z "$TITLE" ] && TITLE="Nuovo post"

  DATE_RAW=$(awk '/^date:/ { print $2; exit }' "$FILE")
  DATE_STR=$(date -d "$DATE_RAW" '+%Y-%m-%d' 2>/dev/null || printf '%s' "$DATE_RAW")

  BASENAME=$(basename "$FILE" .md)
  YEAR=$(printf '%s' "$BASENAME" | cut -d'-' -f1)
  MONTH=$(printf '%s' "$BASENAME" | cut -d'-' -f2)
  DAY=$(printf '%s' "$BASENAME" | cut -d'-' -f3)
  SLUG=$(printf '%s' "$BASENAME" | cut -d'-' -f4-)
  POST_URL="${SITE_BASE_URL%/}/${YEAR}/${MONTH}/${DAY}/${SLUG}/"

  echo "Processing: $FILE (lang=$LANG)"

  HTML=$(build_email_html "$FILE" "$TITLE" "$DATE_STR" "$POST_URL" "UNSUB_PLACEHOLDER" "$UNSUB_LABEL")

  # ── fetch subscribers ────────────────────────────────────────────────────────

  CONTACTS_JSON=$(curl -s \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    "https://api.resend.com/audiences/${SEGMENT_ID}/contacts")

  EMAILS=$(printf '%s' "$CONTACTS_JSON" \
    | jq -r '.data[] | select(.unsubscribed == false) | .email' 2>/dev/null || true)

  if [ -z "$EMAILS" ]; then
    echo "  No subscribers for lang=$LANG, skipping."
    continue
  fi

  # ── send one email per subscriber ────────────────────────────────────────────

  for EMAIL in $EMAILS; do
    TOKEN=$(make_unsub_token "$EMAIL" "$LANG")
    UNSUB_URL="${WORKER_BASE_URL%/}/unsubscribe?token=$(printf '%s' "$TOKEN" | url_encode)"

    # Inject per-subscriber unsubscribe URL
    FINAL_HTML="${HTML/UNSUB_PLACEHOLDER/$UNSUB_URL}"

    PAYLOAD=$(jq -n \
      --arg from "Matteo Petrani <newsletter@matteopetrani.com>" \
      --arg to "$EMAIL" \
      --arg subject "$TITLE" \
      --arg html "$FINAL_HTML" \
      --arg unsub "<${UNSUB_URL}>" \
      '{from: $from, to: [$to], subject: $subject, html: $html,
        headers: {"List-Unsubscribe": $unsub}}')

    RESULT=$(curl -s -X POST "https://api.resend.com/emails" \
      -H "Authorization: Bearer ${RESEND_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD")

    echo "  -> $EMAIL: $(printf '%s' "$RESULT" | jq -r '.id // .message // "error"')"
  done
done
