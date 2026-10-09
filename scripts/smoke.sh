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
#   describe_profile                    ok
#   get_profile_by_id, owner            seen, published 0
#   get_profile_by_id, other key        not_found   (unpublished)
#   publish_profile                     ok
#   get_profile_by_id, other key        seen, published 1, the headline
#   get_profiles_page, other key        lists it
#   withdraw_profile                    ok
#   get_profile_by_id, other key        not_found   (withdrawn)
#   archive_profile                     ok
#   archive_profile again               already_archived
#   get_profile_by_id, owner            not_found   (archived)
#   initiate_organisation               ok          (founder = this run's key)
#   archive_organisation, other key     not_initiator
#   archive_organisation                ok
#   archive_organisation again          already_archived
#   get_organisation_by_id              archived 1, the name
#
# Every call must come back SEALED (encrypted to the service's KEM key): the
# procedures refuse a clear call, and a reply that says sealed 0 fails.
#
# Reads go through the read model, which projections fill asynchronously, so
# a read is retried for a few seconds before it counts as a failure.
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

failed=0

# call <key file> <procedure> <payload json> -> the reply JSON, or {"reason": "transport: ..."}
# A reply that was not sealed fails the run.
call() {
  local out
  out=$(macula-cli call -json "${seeds[@]}" -identity "$1" -realm "$realm" \
    -realm-key "$realm_key" -payload "$3" "mcl-jobs/$2" 2>&1) || true
  if [ "$(jq -r '.ok and .data.sealed == 1' <<<"$out" 2>/dev/null)" = false ] && \
     [ "$(jq -r '.ok' <<<"$out" 2>/dev/null)" = true ]; then
    echo "FAIL $2: the reply was not sealed" >&2; failed=1
  fi
  jq -c 'if .ok then (.data.result // {}) else {reason: ("transport: " + (.error.kind // .error.message // "unknown"))} end' \
    <<<"$out" 2>/dev/null || jq -nc --arg o "$out" '{reason: ("transport: " + $o)}'
}

# read_until <label> <jq test> <key file> <procedure> <payload json>: retry a
# read until the jq test holds on the reply, up to ~10 s.
read_until() {
  local label=$1 test=$2 reply i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    reply=$(call "$3" "$4" "$5")
    if [ "$(jq -r "$test" <<<"$reply")" = true ]; then echo "ok   $label"; return; fi
    sleep 1
  done
  echo "FAIL $label: $reply" >&2; failed=1
}
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

me=$(macula-cli identity -identity "$founder" -json | jq -r '.data.node_id')
by_me=$(jq -nc --arg c "$me" '{citizen: $c}')
headline="Smoke test $org"
description=$(jq -nc --arg h "$headline" '{headline: $h, skills: ["Erlang", "SQL"], location: "Nowhere"}')
expect "describe_profile"              ok                "$(call "$founder" describe_profile "$description")"
read_until "get_profile_by_id, owner: seen, published 0" '.profile.published == 0' \
  "$founder" get_profile_by_id "$by_me"
expect "get_profile_by_id, other key"  not_found         "$(call "$stranger" get_profile_by_id "$by_me")"
expect "publish_profile"               ok                "$(call "$founder" publish_profile '{}')"
read_until "get_profile_by_id, other key: seen, published 1" \
  "(.profile.published == 1) and (.profile.headline == \"$headline\")" "$stranger" get_profile_by_id "$by_me"
listed=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  page_payload='{"limit": 50}'
  for p in $(seq 1 40); do
    page=$(call "$stranger" get_profiles_page "$page_payload")
    if [ "$(jq -r --arg c "$me" '[.profiles[]?.citizen] | index($c) != null' <<<"$page")" = true ]; then listed=1; break; fi
    next=$(jq -r '.next // empty' <<<"$page")
    [ -n "$next" ] || break
    page_payload=$(jq -nc --arg a "$next" '{after: $a, limit: 50}')
  done
  [ "$listed" = 1 ] && break
  sleep 1
done
if [ "$listed" = 1 ]; then echo "ok   get_profiles_page, other key: lists it"
else echo "FAIL get_profiles_page, other key: not listed" >&2; failed=1; fi
expect "withdraw_profile"              ok                "$(call "$founder" withdraw_profile '{}')"
read_until "get_profile_by_id, other key: not_found (withdrawn)" '.reason == "not_found"' \
  "$stranger" get_profile_by_id "$by_me"
expect "archive_profile"               ok                "$(call "$founder" archive_profile '{}')"
expect "archive_profile again"         already_archived  "$(call "$founder" archive_profile '{}')"
read_until "get_profile_by_id, owner: not_found (archived)" '.reason == "not_found"' \
  "$founder" get_profile_by_id "$by_me"

org_payload=$(jq -nc --arg id "$org" '{organisation_id: $id, name: "Smoke Test Cooperative"}')
id_payload=$(jq -nc --arg id "$org" '{organisation_id: $id}')
expect "initiate_organisation"         ok                "$(call "$founder" initiate_organisation "$org_payload")"
expect "archive_organisation, other"   not_initiator     "$(call "$stranger" archive_organisation "$id_payload")"
expect "archive_organisation"          ok                "$(call "$founder" archive_organisation "$id_payload")"
expect "archive_organisation again"    already_archived  "$(call "$founder" archive_organisation "$id_payload")"
read_until "get_organisation_by_id: archived, with its name" \
  '(.archived == 1) and (.name == "Smoke Test Cooperative")' "$stranger" get_organisation_by_id "$id_payload"

exit "$failed"
