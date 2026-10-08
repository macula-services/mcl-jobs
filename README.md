# mcl-jobs

**LinkedIn as it was intended, but over the Macula Mesh**

## Status: walking skeleton

The service boots, joins the mesh and answers `/health` on its Unix socket,
`/run/mcl/health.sock` inside the container. `mcl_om` answers `mcl-jobs/info` on
the mesh for it: name, version, health word, procedures.

Two CMD divisions keep their dossiers in the service's own event store,
`mcl_jobs_store`:

| Division | Desks | Dossier |
|----------|-------|---------|
| `guide_profile_lifecycle` | `initiate_profile`, `archive_profile` | a citizen's profile, keyed by their DID |
| `guide_organisation_lifecycle` | `initiate_organisation`, `archive_organisation` | an organisation, keyed by its id, with its name |

A dossier is initiated once; only an initiated dossier can be archived, and only
once. The desks are not on the mesh yet and there is no query side: the service
announces no capability of its own, because nothing would answer it.

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
`ghcr.io/macula-services/mcl-jobs:latest`, the deploy channel: a host that follows
`:latest` deploys every merge. A `v*` tag publishes its own version and nothing
else, the rollback archive: pin a host to one to roll back. A push that changes
only documentation builds no image (`scripts/is_image_push.sh`).

The service's org, the `<org>` in every procedure it offers (`<org>/<name>`), is
this repository's name, fixed in `config/sys.config.src`. The realm's grant names
it; without an org mcl_om advertises nothing.

Two things CI cannot do for you, both of which have bitten:

1. The registry package may be created **private**, and the pull then fails on
   the host with a bare `unauthorized` that names nothing. Check it after the
   first build. On ghcr the `org.opencontainers.image.source` label in the
   Containerfile is what links the package to the repository.
2. The host needs `MCL_REALM` and the pinned station pair supplied from
   somewhere they are not committed.

## The service contract

Six callbacks in `mcl_jobs_service`, all required, all resolved **by name** by
`mcl_om` at startup on a live node. The `-behaviour(mcl_om_service)`
attribute turns a missing one into a compile error rather than an `undef` where
nobody is watching, and the eunit suite guards the attribute itself.

mcl_om adds one capability of its own to every service: `mcl-jobs/info`, open to
any mesh caller, answering the service's name, version, labels, health word and
advertised procedures. It needs no code here, and this service may not declare
a capability named `info`.

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
