# mcl-jobs

<!-- Service README template: swap the service name in the badge URLs and the
     package link; everything else is shared. -->

[![CI](https://img.shields.io/github/actions/workflow/status/macula-services/mcl-jobs/lint.yml?branch=main&label=CI)](https://github.com/macula-services/mcl-jobs/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![ghcr.io](https://img.shields.io/badge/ghcr.io-macula--services%2Fmcl-jobs-blue.svg)](https://github.com/macula-services/mcl-jobs/pkgs/container/mcl-jobs)
[![BEAM](https://img.shields.io/badge/beam-28%2B-A90533?logo=erlang&logoColor=white)](https://www.erlang.org)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-support-ea4aaa.svg?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/rgfaber)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-ffdd00.svg?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/rlefever)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/macula-full-dark.svg">
    <img src="assets/macula-full-light.svg" alt="Macula" width="320">
  </picture>
</p>

<p align="center">
  <strong>LinkedIn as it was intended, but over the Macula Mesh</strong>
</p>

---


## Status

The service boots, joins the mesh and answers `/health` on its Unix socket,
`/run/mcl/health.sock` inside the container. `mcl_om` answers `mcl-jobs/info`
(name, version, health word, procedures) and `mcl-jobs/get_limits` on the mesh
for it.

Two CMD divisions keep their dossiers in the service's own event store,
`mcl_jobs_store`, and a read side answers from a SQLite read model beside it:

| Division | Desks | Dossier or read model |
|----------|-------|-----------------------|
| `guide_profile_lifecycle` (CMD) | `initiate_profile`, `describe_profile`, `publish_profile`, `withdraw_profile`, `archive_profile` | a citizen's profile, keyed by their node id |
| `guide_organisation_lifecycle` (CMD) | `initiate_organisation`, `archive_organisation` | an organisation, keyed by its id, with its name and initiator |
| `project_jobs` (PRJ) | one projection per event | `jobs.sqlite3`: profiles, organisations |
| `query_jobs` (QRY) | `get_profile_by_id`, `get_profiles_page`, `get_organisation_by_id`, `get_organisations_page` | reads `jobs.sqlite3` |

## Procedures

Its own procedures are CALLs that act as their **caller**, the node id that signed
the call (macula sets `caller` and overwrites any the payload sent), and each
**requires a sealed call**: the service names its KEM key and refuses a call in the clear, so
a profile crosses a station only as ciphertext. Each replies with its answer, or
`{"reason": "<text>"}` naming the rule that refused it. Those reason strings
are the wire contract.

| Procedure | Payload | Answer |
|-----------|---------|--------|
| `mcl-jobs/initiate_profile` | `{}` | `{}`: the caller's own profile exists |
| `mcl-jobs/describe_profile` | `{"headline", "skills": [...], "location"}` | `{}`: replaces the caller's description; if published, the realm sees the new one at once |
| `mcl-jobs/publish_profile` | `{}` | `{}`: the realm can see the caller's profile |
| `mcl-jobs/withdraw_profile` | `{}` | `{}`: only the caller sees it again |
| `mcl-jobs/archive_profile` | `{}` | `{}`: final; nobody sees it again, and this key cannot initiate another |
| `mcl-jobs/initiate_organisation` | `{"organisation_id", "name"}` | `{}`: the caller becomes its initiator |
| `mcl-jobs/archive_organisation` | `{"organisation_id"}` | `{}`: only by its initiator |
| `mcl-jobs/get_profile_by_id` | `{"citizen": "<64 hex>"}` | `{citizen, headline, skills, location, published}` |
| `mcl-jobs/get_profiles_page` | `{"after"?, "limit"?}` | `{"profiles": [...], "next"?}`, in citizen order |
| `mcl-jobs/get_organisation_by_id` | `{"organisation_id"}` | `{organisation_id, name, initiated_by, initiated_at, archived}` |
| `mcl-jobs/get_organisations_page` | `{"after"?, "limit"?}` | `{"organisations": [...], "next"?}`, active ones in id order |

**Who sees a profile:** the realm sees it when it is published and not
archived; its owner also sees it unpublished. Anything else answers exactly as a
profile that never existed (`not_found`, or absent from the page). One module,
`visible_profiles`, holds that rule for both profile queries. Organisations
have no publish step: initiating one is a public act, and an archived one still
answers by id, with `archived: 1`.

| Reason | Meaning |
|--------|---------|
| `already_initiated` | initiated before, archived or not; an id or a key is never reused |
| `not_initiated` | never initiated |
| `profile_archived` | the profile is archived and changes no more |
| `not_described`, `already_published`, `not_published` | publish needs a description and happens once; withdraw needs it published |
| `not_initiator` | only the node that initiated an organisation may archive it |
| `already_archived` | archived before |
| `invalid_headline`, `invalid_skills`, `invalid_location` | text is UTF-8, kept in NFC, with no control or invisible format characters (bidi overrides, zero-width characters and the like); headline 1 to 200 bytes, up to 30 skills of 1 to 64, location up to 100 |
| `invalid_organisation_id` | not 1 to 64 of `[a-z0-9-]` |
| `missing_name`, `invalid_name` | an organisation name follows the same text rule, at most 200 bytes |
| `invalid_citizen`, `invalid_cursor`, `invalid_limit` | a citizen is 64 hex characters; a limit is 1 to 50 (default 20) |
| `not_found` | nothing the caller may see |
| `no_caller` | the CALL carried no 32-byte node id |
| `store_unavailable`, `internal_error` | the service's own fault; its log has it |

Plus `mcl-jobs/info` and `mcl-jobs/get_limits`, which `mcl_om` adds to every service.

Known limits. A profile belongs to a node key, so whoever loses their key loses
their profile, and archiving is final for that key. Organisation ids go to
whoever initiates them first and are never released. Anyone the realm admits
can publish a profile, so the directory is exactly as trustworthy as the realm.
Events are permanent: a description, once given, stays in the service's event
store after it is replaced, withdrawn or archived, even though no query shows it.

`scripts/smoke.sh` calls all of this against a deployed service with fresh
identities and checks every answer, that every reply came back sealed, and the
refusals that only a stored event can produce.

The architecture (C4 context, containers, components) is in
[architecture/README.md](architecture/README.md).

## Running it

    rebar3 compile
    rebar3 eunit
    rebar3 lint

    scripts/health.sh                      # against a running node

The image builds in one pinned image and runs on another, a pair named by
digest in the two `FROM` lines of the `Containerfile`. The builder carries the
whole toolchain (OTP 28.4.3 with ML-DSA, rebar3, Rust for macula's NIFs), so
building needs nothing on the host but podman or docker. CI lints and tests in
that same builder image, and the service's tests fail if the two drift apart.

    podman build -t mcl-jobs -f Containerfile .

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `MCL_REALM` | required | 64-hex realm tag, the `sha256` of the realm's name. No default: a service that guesses its realm announces itself where nobody can attribute it. |
| `MCL_REALM_KEY` | required | The realm's public signing key, hex encoded: the **trust anchor**, not an identifier. Every org-namespaced advertisement is verified against it, so without it nothing resolves, the boot claim never reaches the realm, and the service stays green while unreachable. Public material, not a secret. |
| `MACULA_STATION_SEEDS` | required | Station hosts to dial, `host[:port]`, comma-separated. No default: naming a realm costs nothing, dialling somebody else's live station from every dev clone does. |
| `MACULA_STATION_NODE_IDS` | required | The matching 64-hex station node ids, comma-separated, index-paired with the seeds. The dial is pinned (D5): mcl_om refuses to boot a pool with an unpinned seed. |
| `MCL_SERVICE_NAME` | `mcl-jobs` | Label on the boot claim the realm's operator sees. Falls back to the service's own name. |
| `MCL_BOX` | empty | Label naming the host, also on the boot claim. Set it where you deploy. |
| `MCL_NODE_NAME` | `mcl_jobs` | Erlang node name. |
| `MCL_NODE_HOST` | `127.0.0.1` | Erlang node host. |
| `MCL_COOKIE` | `mcl_jobs` | Erlang cookie. |

`deploy/docker-compose.yml` runs it, and carries what the service knows about
itself. If you deploy through something else, let that carry **placement**: which
host, which station, which realm, which secret store. Keeping the two apart is
what stops a config table in a README and the real environment drifting.

## Deployment

The image has two channels. A push to `main` publishes
`ghcr.io/macula-services/mcl-jobs:latest`; a host configured to follow that tag
picks up every merge, and the fleet instead pins a release digest. A `v*` tag
publishes its own version and nothing else, the rollback archive: pin a host to
one to roll back. A push that changes
only documentation builds no image (`scripts/is_image_push.sh`).

The service's org, the `<org>` its own procedure names carry (`<org>/<name>`), is
this repository's name, fixed in `config/sys.config.src`. The realm's grant names
it; without an org mcl_om refuses to boot, naming the setting.

Two things CI cannot do for you, both of which have bitten:

1. The registry package may be created **private**, and the pull then fails on
   the host with a bare `unauthorized` that names nothing. Check it after the
   first build. On ghcr the `org.opencontainers.image.source` label in the
   Containerfile is what links the package to the repository.
2. The host needs `MCL_REALM` and the pinned station seeds and node ids supplied
   from somewhere they are not committed.

## The service contract

Six callbacks in `mcl_jobs_service`, all required, all resolved **by name** by
`mcl_om` at startup on a live node. The `-behaviour(mcl_om_service)`
attribute turns a missing one into a compile error rather than an `undef` where
nobody is watching, and the eunit suite guards the attribute itself.

mcl_om adds two capabilities of its own to every service. `mcl-jobs/info` is open
to any mesh caller and answers the service's name, version, labels, health word
and advertised procedures; `mcl-jobs/get_limits` is open too and answers guard
limits and window stats for each named procedure, or for them all. It needs no code here, and this service may not declare
a capability named `info`. `capabilities/0` in `mcl_jobs_service` is the list.

### The store

This service was scaffolded with `store=1`, so it owns a `reckon-db` store called
`mcl_jobs_store`. Persistence is the service's own: `mcl_om` opens no store and
starts no reckon-db or evoq application. This service declares `reckon_db`, `evoq`
and `reckon_evoq` in `rebar.config` and its app.src, and `mcl_jobs_app` opens the
store and its evoq subscription in `start/2`, before `mcl_om:boot/1`, from what
`mcl_jobs_service:event_store/0` says (id, directory, indexes, mode, integrity).
`config/sys.config.src` carries the `evoq`
adapter block the subscription requires.

⚠ **The store id is written in two places**, `event_store/0` and the `evoq` block,
and nothing makes them agree by itself. A generated test compares them, along
with a second one asserting the `evoq` block is present at all. Keep both.

⚠ **`deploy/docker-compose.yml` mounts a volume, and on a node it must.** Without
it the record lives inside the container and every recreate destroys it, which is
the same as not keeping one.

The store is node-local. To make it span every node running the same store id,
set its `mode` to `cluster`, and reckon-db forms a Ra cluster across them.

⚠ **Not `store_id/0` and `data_dir/0`.** Those were mcl_om callbacks before 0.35;
a service module exporting both is taken for one built on the old contract, and
mcl_om warns about it at every boot.

## Licence

Apache-2.0.
