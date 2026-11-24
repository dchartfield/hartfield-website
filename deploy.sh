#!/usr/bin/env bash
# Build and deploy the Hartfield Technologies site to S3.
#
#   ./deploy.sh              build and upload
#   ./deploy.sh --dry-run    build and show what would change, upload nothing
#   ./deploy.sh --build-only build into ./dist so you can preview locally
#
# Settings come from config.env next to this script. Each {{NAME}} placeholder
# in site/*.html is replaced with the matching value from config.env.
# Requires: aws CLI v2 with credentials that can write to the bucket, and perl.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/site"
DIST="$ROOT/dist"
CONFIG="$ROOT/config.env"

MODE="deploy"
case "${1:-}" in
  --dry-run)    MODE="dry-run" ;;
  --build-only) MODE="build" ;;
  "")           ;;
  -h|--help)    sed -n '2,11p' "$0"; exit 0 ;;
  *)            echo "Unknown option: $1" >&2; exit 2 ;;
esac

[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG" >&2; exit 1; }
# shellcheck source=config.env
set -a; source "$CONFIG"; set +a

# Digits-only phone for tel: links, e.g. (512) 555-0100 -> +15125550100
digits="$(printf '%s' "${PHONE:-}" | tr -cd '0-9')"
if [[ ${#digits} -eq 10 ]]; then PHONE_DIGITS="+1$digits"; else PHONE_DIGITS="+$digits"; fi
export PHONE_DIGITS

# Refuse to publish unfinished business details: Twilio rejects sites with
# placeholder or missing contact information.
missing=()
for var in LEGAL_NAME STATE_OF_FORMATION BUSINESS_ADDRESS PHONE EMAIL DOMAIN EFFECTIVE_DATE; do
  val="${!var:-}"
  if [[ -z "$val" || "$val" == TODO* ]]; then missing+=("$var"); fi
done
if (( ${#missing[@]} )) && [[ "$MODE" != "build" ]]; then
  echo "Fill in these values in config.env before deploying: ${missing[*]}" >&2
  exit 1
fi

# --- Build ---------------------------------------------------------------
rm -rf "$DIST"
cp -R "$SRC" "$DIST"
find "$DIST" -name '.DS_Store' -delete

for f in "$DIST"/*.html; do
  # Replace {{NAME}} with $NAME from the environment; HTML-escape & < >.
  perl -pi -e '
    s/\{\{([A-Z_]+)\}\}/
      exists $ENV{$1}
        ? do { my $v = $ENV{$1}; $v =~ s#&#&amp;#g; $v =~ s#<#&lt;#g; $v =~ s#>#&gt;#g; $v }
        : die "Unknown placeholder {{$1}} in $ARGV\n"
    /ge' "$f"
done

if grep -l '{{' "$DIST"/*.html >/dev/null 2>&1; then
  echo "Unreplaced placeholders remain in:" >&2; grep -l '{{' "$DIST"/*.html >&2; exit 1
fi
echo "Built site into $DIST"

if [[ "$MODE" == "build" ]]; then
  (( ${#missing[@]} )) && echo "Note: still TODO in config.env: ${missing[*]}"
  echo "Preview with:  (cd \"$DIST\" && python3 -m http.server 8000)"
  exit 0
fi

# --- Upload --------------------------------------------------------------
command -v aws >/dev/null || { echo "aws CLI not found. Install it: brew install awscli" >&2; exit 1; }
[[ -n "${S3_BUCKET:-}" ]] || { echo "Set S3_BUCKET in config.env" >&2; exit 1; }

AWS_ARGS=()
[[ -n "${AWS_PROFILE:-}" ]] || unset AWS_PROFILE
[[ -n "${AWS_PROFILE:-}" ]] && AWS_ARGS+=(--profile "$AWS_PROFILE")

PREFIX="${S3_PREFIX:-}"; PREFIX="${PREFIX#/}"; PREFIX="${PREFIX%/}"
DEST="s3://$S3_BUCKET${PREFIX:+/$PREFIX}"

DRY=()
[[ "$MODE" == "dry-run" ]] && DRY=(--dryrun)

echo "Deploying to $DEST ${DRY:+(dry run)}"

# Assets (CSS, JS, images) can be cached for a day.
aws ${AWS_ARGS[@]+"${AWS_ARGS[@]}"} s3 sync "$DIST" "$DEST" ${DRY[@]+"${DRY[@]}"} --delete \
  --exclude "*.html" \
  --cache-control "public, max-age=86400"

# HTML is revalidated on every visit so edits show up immediately.
aws ${AWS_ARGS[@]+"${AWS_ARGS[@]}"} s3 sync "$DIST" "$DEST" ${DRY[@]+"${DRY[@]}"} --delete \
  --exclude "*" --include "*.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "no-cache"

if [[ -n "${CLOUDFRONT_DISTRIBUTION_ID:-}" && "$MODE" == "deploy" ]]; then
  echo "Invalidating CloudFront distribution $CLOUDFRONT_DISTRIBUTION_ID"
  aws ${AWS_ARGS[@]+"${AWS_ARGS[@]}"} cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --paths "/${PREFIX:+$PREFIX/}*" >/dev/null
fi

echo "Done. https://$DOMAIN/${PREFIX:+$PREFIX/}"
