#!/usr/bin/env bash
#
# Reads what Battistics already emits, and stores nothing.
#
# Every install fetches the appcast once a day and downloads a DMG when it
# updates, and GitHub counts both. That is the whole data source: no telemetry
# in the app, no endpoint to run, no file to keep in sync.
#
# Release download counts are cumulative and never expire, so there is nothing
# to snapshot — run this whenever you want the current numbers. Traffic is the
# one exception, a rolling 14-day window, and it needs push access on the repo,
# so nobody but the owner can read it.
#
# Every number here is a TOTAL, not a unique count. GitHub exposes no uniques
# for release assets, and the app has no identifier to count with. Treat the
# active-install line as an estimate.

set -euo pipefail

REPO="${BATTISTICS_REPO:-doguyilmaz/battistics}"

command -v gh >/dev/null || {
    echo "gh is required: brew install gh" >&2
    exit 1
}

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
rule() { printf '%s\n' "────────────────────────────────────────────────"; }

releases=$(gh api "repos/$REPO/releases" --paginate)

bold "Installs by version"
rule
printf '%-10s %-12s %10s\n' "VERSION" "PUBLISHED" "DOWNLOADS"
jq -r '.[] | . as $r | (.assets[] | select(.name | endswith(".dmg")))
    | "\($r.tag_name)\t\($r.published_at[0:10])\t\(.download_count)"' <<<"$releases" |
    while IFS=$'\t' read -r tag date count; do
        printf '%-10s %-12s %10s\n' "$tag" "$date" "$count"
    done
total=$(jq '[.[].assets[] | select(.name | endswith(".dmg")) | .download_count] | add // 0' <<<"$releases")
printf '%-10s %-12s %10s\n' "total" "" "$total"

echo
bold "Update checks (each install polls once a day)"
rule
latest_date=$(jq -r '[.[] | select(.prerelease == false)] | first | .published_at' <<<"$releases")
# -u because GitHub's timestamp is UTC and `date -j -f` would otherwise read it
# as local, which is a whole day out whenever the offset crosses midnight.
published=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$latest_date" +%s)
days=$((((($(date +%s) - published)) / 86400) + 1))

for feed in appcast-2.xml appcast.xml; do
    hits=$(jq --arg f "$feed" '[.[] | select(.prerelease == false)] | first
        | [.assets[] | select(.name == $f) | .download_count] | add // 0' <<<"$releases")
    case "$feed" in
    appcast-2.xml) label="current  (com.doguyilmaz)" ;;
    appcast.xml) label="legacy   (com.dogukyilmaz)" ;;
    esac
    # Decimal, because integer division reported a feed still being polled
    # as zero for any rate below one a day.
    rate=$(awk -v h="$hits" -v d="$days" 'BEGIN { printf "%.1f", h / d }')
    printf '%-26s %5s fetches / %s days  ≈ %s a day\n' \
        "$label" "$hits" "$days" "$rate"
done
echo "  Legacy reaching zero is when the 1.0.2 migration can be dropped."

echo
bold "Discovery (rolling 14 days, needs push access)"
rule
if views=$(gh api "repos/$REPO/traffic/views" 2>/dev/null); then
    printf 'views    %5s  (%s unique)\n' \
        "$(jq .count <<<"$views")" "$(jq .uniques <<<"$views")"
    clones=$(gh api "repos/$REPO/traffic/clones")
    printf 'clones   %5s  (%s unique)\n' \
        "$(jq .count <<<"$clones")" "$(jq .uniques <<<"$clones")"
else
    echo "unavailable — traffic requires push access on $REPO"
fi
printf 'stars    %5s\n' "$(gh api "repos/$REPO" --jq .stargazers_count)"
