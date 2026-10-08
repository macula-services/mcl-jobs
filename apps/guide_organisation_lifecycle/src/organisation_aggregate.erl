%%% @doc Aggregate for an organisation.
%%%
%%% One aggregate per organisation, keyed by its organisation id. Lifecycle:
%%% initiate_organisation (birth) -> archive_organisation (terminal).
%%%
%%% The lifecycle rules live here, in execute/2; the desk handlers only
%%% validate a payload and build the event. Rules: an organisation is
%%% initiated once; only an initiated organisation can be archived, only by
%%% the node that initiated it, and only once. The checks run in that order,
%%% so someone who did not initiate an organisation learns nothing about
%%% whether it was archived.
%%% @end
-module(organisation_aggregate).
-behaviour(evoq_aggregate).

-include("organisation_status.hrl").

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/1, store_id/0, valid_id/1]).

-spec state_module() -> module().
state_module() -> organisation_state.

%% @doc The store every organisation stream lives in: the one mcl_jobs opens.
%% mcl_jobs' tests assert it agrees with mcl_jobs_service:event_store/0.
-spec store_id() -> atom().
store_id() -> mcl_jobs_store.

%% @doc An organisation id is 1 to 64 of [a-z0-9-]: opaque, chosen by whoever
%% initiates it, and safe to show anywhere.
-spec valid_id(term()) -> boolean().
valid_id(Id) when is_binary(Id), byte_size(Id) >= 1, byte_size(Id) =< 64 ->
    nomatch =/= re:run(Id, <<"^[a-z0-9-]+$">>);
valid_id(_) ->
    false.

%% @doc reckon-db stream ids must match ^[a-z]{1,32}-[a-f0-9]{32}$, so the
%% stream is addressed by a 128-bit digest of the organisation id, not the id
%% itself. Events carry the id in their own data for whoever needs it back.
-spec stream_id(binary()) -> binary().
stream_id(OrganisationId) ->
    Digest = binary:part(crypto:hash(sha256, OrganisationId), 0, 16),
    <<"organisation-", (binary:encode_hex(Digest, lowercase))/binary>>.

init(OrganisationId) ->
    {ok, organisation_state:new(OrganisationId)}.

execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, State, Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    organisation_state:apply_event(State, Event).

do_execute(initiate_organisation_v1, State, Payload) ->
    initiate(initiated(State), Payload);
do_execute(archive_organisation_v1, State, Payload) ->
    archive(initiated(State),
            organisation_state:initiated_by(State) =:= maps:get(archived_by, Payload, undefined),
            evoq_bit_flags:has(organisation_state:status(State), ?ORGANISATION_ARCHIVED),
            Payload);
do_execute(_Unknown, _State, _Payload) ->
    {error, unknown_command}.

initiated(State) ->
    evoq_bit_flags:has(organisation_state:status(State), ?ORGANISATION_INITIATED).

initiate(true, _Payload) -> {error, already_initiated};
initiate(false, Payload) -> maybe_initiate_organisation:handle_from_map(Payload).

archive(false, _ByInitiator, _Archived, _Payload) -> {error, not_initiated};
archive(true, false, _Archived, _Payload) -> {error, not_initiator};
archive(true, true, true, _Payload) -> {error, already_archived};
archive(true, true, false, Payload) -> maybe_archive_organisation:handle_from_map(Payload).
