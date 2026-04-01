#!/usr/bin/env bash
# Usage: called by .github/workflows/notify-email-on-new-post.yml
set -e

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

  BASENAME=$(basename "$FILE" .md)
  YEAR=$(printf '%s' "$BASENAME" | cut -d'-' -f1)
  MONTH=$(printf '%s' "$BASENAME" | cut -d'-' -f2)
  DAY=$(printf '%s' "$BASENAME" | cut -d'-' -f3)
  SLUG=$(printf '%s' "$BASENAME" | cut -d'-' -f4-)
  POST_URL="${SITE_BASE_URL%/}/${YEAR}/${MONTH}/${DAY}/${SLUG}/"

  echo "Processing: $FILE (lang=$LANG, url=$POST_URL)"

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

    HTML=$(python3 scripts/render_email.py "$FILE" "$POST_URL" "$UNSUB_URL" "$UNSUB_LABEL")

    PAYLOAD=$(jq -n \
      --arg from "Matteo Petrani <newsletter@matteopetrani.com>" \
      --arg to "$EMAIL" \
      --arg subject "$TITLE" \
      --arg html "$HTML" \
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
