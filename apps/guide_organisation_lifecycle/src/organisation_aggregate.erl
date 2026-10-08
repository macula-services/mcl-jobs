%%% @doc Aggregate for an organisation.
%%%
%%% One aggregate per organisation, keyed by its organisation id. Lifecycle:
%%% initiate_organisation (birth) -> archive_organisation (terminal).
%%%
%%% The lifecycle rules live here, in execute/2; the desk handlers only
%%% validate a payload and build the event. Rules: an organisation is initiated
%%% once, only an initiated organisation can be archived, and only once.
%%% @end
-module(organisation_aggregate).
-behaviour(evoq_aggregate).

-include("organisation_status.hrl").

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/1, store_id/0]).

-spec state_module() -> module().
state_module() -> organisation_state.

%% @doc The store every organisation stream lives in: the one mcl_jobs opens.
%% mcl_jobs' tests assert it agrees with mcl_jobs_service:event_store/0.
-spec store_id() -> atom().
store_id() -> mcl_jobs_store.

%% @doc reckon-db stream ids must match ^[a-z]{1,32}-[a-f0-9]{32}$, so the
%% stream is addressed by a 128-bit digest of the organisation id, not the id itself.
%% Events carry the id in their own data for whoever needs it back.
-spec stream_id(binary()) -> binary().
stream_id(OrganisationId) ->
    Digest = binary:part(crypto:hash(sha256, OrganisationId), 0, 16),
    <<"organisation-", (binary:encode_hex(Digest, lowercase))/binary>>.

init(OrganisationId) ->
    {ok, organisation_state:new(OrganisationId)}.

execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, organisation_state:status(State), Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    organisation_state:apply_event(State, Event).

do_execute(initiate_organisation_v1, Status, Payload) ->
    initiate(evoq_bit_flags:has(Status, ?ORGANISATION_INITIATED), Payload);
do_execute(archive_organisation_v1, Status, Payload) ->
    archive(evoq_bit_flags:has(Status, ?ORGANISATION_INITIATED),
            evoq_bit_flags:has(Status, ?ORGANISATION_ARCHIVED),
            Payload);
do_execute(_Unknown, _Status, _Payload) ->
    {error, unknown_command}.

initiate(true, _Payload) -> {error, already_initiated};
initiate(false, Payload) -> maybe_initiate_organisation:handle_from_map(Payload).

archive(false, _Archived, _Payload) -> {error, not_initiated};
archive(true, true, _Payload) -> {error, already_archived};
archive(true, false, Payload) -> maybe_archive_organisation:handle_from_map(Payload).
