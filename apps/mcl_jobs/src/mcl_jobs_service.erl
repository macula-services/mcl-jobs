%% @doc The mcl_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
%%
%% IT ANNOUNCES ITS LIFECYCLE AND QUERY PROCEDURES AND ASKS FOR NO TOPIC AUTHORITY.
%% Advertising a capability before it exists puts a lie on the mesh that another
%% service can find and call, so each entry names a responder that answers, and
%% a test pins the list so growing it is a deliberate act.
-module(mcl_jobs_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
%% ==========================================================================
%% AND THE STORE THIS SERVICE OWNS
%% ==========================================================================
%%
%% Generated because this service was scaffolded with `store=1'. NOT an mcl_om
%% callback: mcl_om opens no store since 0.35.0. mcl_jobs_app reads it and opens
%% the store in its own start/2 before mcl_om:boot/1, with reckon_db, evoq and
%% reckon_evoq declared by this service in rebar.config and its app.src.
%%
%% ⚠ ONE MAP, NOT THE OLD `store_id/0' AND `data_dir/0' CALLBACKS. mcl_om 0.35
%% warns at every boot about a service module exporting those two together,
%% because that is how a service built for the old contract looks, and a false
%% warning teaches everyone to ignore the true one.
%%
%% ⚠ `config/sys.config.src' MUST CARRY THE `evoq' BLOCK, which is why it was
%% generated with one. The per-store evoq subscription reads the global log, and
%% that crashes on `{not_configured, event_store_adapter}' without it. evoq starts
%% as a release-boot application before any service's `start/2' runs, so nothing
%% can inject it later. A sibling put two of three fleet nodes into a boot-crash
%% loop this exact way.
-export([event_store/0]).

info() ->
    #{name => <<"mcl-jobs">>,
      version => <<"0.1.0">>,
      description => <<"LinkedIn as it was intended, but over the Macula Mesh">>}.

start(_Opts) -> mcl_jobs_sup:start_link().

stop(_State) -> ok.

%% Green once the supervision tree is up. Replace this with a real probe of
%% whatever this service needs in order to do its job. A dark mesh is usually NOT
%% a health failure: decide that deliberately rather than by default.
health() -> ok.

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO. Other services find this one by these
%% names, so each entry is a promise that something answers. Each is a CALL
%% that acts as its caller (the node id that signed it) and replies #{} or
%% #{reason => Why}; README, "Procedures", is the contract.
capabilities() ->
    [procedure(Name)
     || Name <- [<<"initiate_profile">>, <<"describe_profile">>, <<"publish_profile">>,
                 <<"withdraw_profile">>, <<"archive_profile">>,
                 <<"initiate_organisation">>, <<"archive_organisation">>,
                 <<"get_profile_by_id">>, <<"get_profiles_page">>,
                 <<"get_organisation_by_id">>, <<"get_organisations_page">>]].

%% Each is answered by <name>_responder, names the KEM key (kem_advertise in
%% sys.config) and refuses a call in the clear: a profile is personal data,
%% and crosses a station only as ciphertext.
procedure(Name) ->
    #{name => Name, version => 1, confidential => required,
      handler => {binary_to_atom(<<Name/binary, "_responder">>), []}}.

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. mcl-jobs publishes
%% and subscribes to none: its procedures are CALLs, served under the realm's
%% org-wide provider grant for mcl-jobs, so it asks for nothing. Popped, an attacker
%% gains precisely this and no more, which is the whole point of listing it.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"mcl-jobs">>,
      actions => [],
      resources => [],
      ttl_days => 30}.

%% ==========================================================================
%% The store
%% ==========================================================================

%% @doc The reckon-db store this service owns, as mcl_jobs_app opens it.
%%
%% `id': ⚠ IT IS NAMED IN TWO PLACES, here and in the `evoq' block of
%% `config/sys.config.src', and nothing makes them agree by itself. Disagreeing
%% opens one store and addresses another. A generated test compares the two.
%%
%% `dir': where it lives on disk (the store itself at <dir>/<id>/). ⚠ DEFAULTS TO
%% A PATH INSIDE THE CONTAINER AND MUST NOT STAY THERE ON A NODE. The fleet keeps
%% application data on its `/bulk' drives and boots from a small eMMC, so
%% `deploy/docker-compose.yml' mounts a volume and sets MCL_DATA_DIR. A container
%% without the mount loses its record on every recreate.
%%
%% `indexes': the secondary indexes the store maintains, e.g. [tags, event_type,
%% {payload, <<"plate">>}], declared when it opens (a store already running
%% ignores a second declaration). None until a query needs one.
%%
%% `mode': `single', one node's store; `cluster' makes reckon-db form a Ra cluster
%% across every node that opens the same id.
%%
%% `integrity': `disabled', or `#{enabled => true, key_source => {env_var, Name}}'
%% for per-store HMAC tamper-resistance. The store refuses to start when integrity
%% is enabled and the key cannot be loaded, so provision the key first.
-spec event_store() -> #{id := atom(), dir := string(), indexes := [term()],
                         mode := single | cluster, integrity := disabled | map()}.
event_store() ->
    #{id => mcl_jobs_store,
      dir => chosen(os:getenv("MCL_DATA_DIR")),
      indexes => [],
      mode => single,
      integrity => disabled}.

chosen(false) -> "/tmp/mcl_jobs";
chosen("") -> "/tmp/mcl_jobs";
chosen(Path) -> Path.
