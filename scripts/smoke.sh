#!/usr/bin/env bash
# This exists so "the skeleton walks" is a fact checked over the mesh, not a
# claim: it calls a DEPLOYED mcl-jobs through the stations, and every answer
# comes back from the live event store.
#
# Each run uses fresh identities and a fresh organisation id, so it can run
# again and again against the same deployment and never collides with itself:
#
#   mcl-jobs/info                       answers, with a version
#   initiate_profile                    ok          (the caller's own profile)
#   initiate_profile again              already_initiated
#   archive_profile                     ok
#   archive_profile again               already_archived
#   initiate_organisation               ok          (founder = this run's key)
#   archive_organisation, other key     not_initiator
#   archive_organisation                ok
#   archive_organisation again          already_archived
#
# The pairs that are refused the second time can only be refused if the first
# answer was stored: that is the live-store path.
#
# Usage:
#   MCL_REALM_KEY=<hex or @file> MACULA_STATION_SEEDS=host:port,... \
#   MACULA_STATION_NODE_IDS=<hex>,... scripts/smoke.sh
#
# The same three values the service runs with (README, Configuration). The realm
# is io.macula unless SMOKE_REALM says otherwise. Exits 0 when every check
# passes, 1 naming each one that did not.
#
# Needs: macula-cli >= 0.10, jq, od.
set -euo pipefail

realm=${SMOKE_REALM:-io.macula}
realm_key=${MCL_REALM_KEY:?set MCL_REALM_KEY to the realm key in hex, or @file}
IFS=, read -r -a hosts <<<"${MACULA_STATION_SEEDS:?set MACULA_STATION_SEEDS}"
IFS=, read -r -a ids <<<"${MACULA_STATION_NODE_IDS:?set MACULA_STATION_NODE_IDS}"
[ "${#hosts[@]}" -eq "${#ids[@]}" ] || { echo "seeds and node ids differ in count" >&2; exit 1; }
seeds=()
for i in "${!hosts[@]}"; do seeds+=(-seed "${hosts[$i]}@${ids[$i]}"); done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
founder="$work/founder.key"
stranger="$work/stranger.key"
org="org-smoke-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"

# call <key file> <procedure> <payload json> -> the reply JSON, or {"reason": "transport: ..."}
call() {
  local out
  out=$(macula-cli call -json "${seeds[@]}" -identity "$1" -realm "$realm" \
    -realm-key "$realm_key" -payload "$3" "mcl-jobs/$2" 2>&1) || true
  jq -c 'if .ok then (.data.result // {}) else {reason: ("transport: " + (.error.kind // .error.message // "unknown"))} end' \
    <<<"$out" 2>/dev/null || jq -nc --arg o "$out" '{reason: ("transport: " + $o)}'
}

failed=0
# expect <label> <wanted: ok | a reason> <reply json>
expect() {
  local got
  got=$(jq -r '.reason // "ok"' <<<"$3")
  if [ "$got" = "$2" ]; then echo "ok   $1: $got"; else echo "FAIL $1: wanted $2, got $got" >&2; failed=1; fi
}

info=$(call "$founder" info '{}')
version=$(jq -r '.version // empty' <<<"$info")
if [ -n "$version" ]; then echo "ok   info: version $version"; else echo "FAIL info: $info" >&2; failed=1; fi

expect "initiate_profile"              ok                "$(call "$founder" initiate_profile '{}')"
expect "initiate_profile again"        already_initiated "$(call "$founder" initiate_profile '{}')"
expect "archive_profile"               ok                "$(call "$founder" archive_profile '{}')"
expect "archive_profile again"         already_archived  "$(call "$founder" archive_profile '{}')"

org_payload=$(jq -nc --arg id "$org" '{organisation_id: $id, name: "Smoke Test Cooperative"}')
id_payload=$(jq -nc --arg id "$org" '{organisation_id: $id}')
expect "initiate_organisation"         ok                "$(call "$founder" initiate_organisation "$org_payload")"
expect "archive_organisation, other"   not_initiator     "$(call "$stranger" archive_organisation "$id_payload")"
expect "archive_organisation"          ok                "$(call "$founder" archive_organisation "$id_payload")"
expect "archive_organisation again"    already_archived  "$(call "$founder" archive_organisation "$id_payload")"

exit "$failed"
