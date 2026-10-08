%%% @doc Aggregate for a citizen's profile.
%%%
%%% One profile per citizen, keyed by the citizen's DID. Lifecycle:
%%% initiate_profile (birth) -> archive_profile (terminal).
%%%
%%% The lifecycle rules live here, in execute/2; the desk handlers only
%%% validate a payload and build the event. Rules: a profile is initiated
%%% once, only an initiated profile can be archived, and only once.
%%% @end
-module(profile_aggregate).
-behaviour(evoq_aggregate).

-include("profile_status.hrl").

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/1, store_id/0]).

-spec state_module() -> module().
state_module() -> profile_state.

%% @doc The store every profile stream lives in: the one mcl_jobs opens.
%% mcl_jobs' tests assert it agrees with mcl_jobs_service:event_store/0.
-spec store_id() -> atom().
store_id() -> mcl_jobs_store.

%% @doc reckon-db stream ids must match ^[a-z]{1,32}-[a-f0-9]{32}$, so the
%% stream is addressed by a 128-bit digest of the DID, not the DID itself.
%% Events carry the DID in their own data for whoever needs it back.
-spec stream_id(binary()) -> binary().
stream_id(CitizenDid) ->
    Digest = binary:part(crypto:hash(sha256, CitizenDid), 0, 16),
    <<"profile-", (binary:encode_hex(Digest, lowercase))/binary>>.

init(CitizenDid) ->
    {ok, profile_state:new(CitizenDid)}.

execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, profile_state:status(State), Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    profile_state:apply_event(State, Event).

do_execute(initiate_profile_v1, Status, Payload) ->
    initiate(evoq_bit_flags:has(Status, ?PROFILE_INITIATED), Payload);
do_execute(archive_profile_v1, Status, Payload) ->
    archive(evoq_bit_flags:has(Status, ?PROFILE_INITIATED),
            evoq_bit_flags:has(Status, ?PROFILE_ARCHIVED),
            Payload);
do_execute(_Unknown, _Status, _Payload) ->
    {error, unknown_command}.

initiate(true, _Payload) -> {error, already_initiated};
initiate(false, Payload) -> maybe_initiate_profile:handle_from_map(Payload).

archive(false, _Archived, _Payload) -> {error, not_initiated};
archive(true, true, _Payload) -> {error, already_archived};
archive(true, false, Payload) -> maybe_archive_profile:handle_from_map(Payload).
