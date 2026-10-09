%% @doc Projects profile_archived_v1 into the profiles table. Archives the profile for good: no query answers it again.
%%
%% One upsert setting only this event's columns (jobs_read_model_store says
%% why), so a replay is the same write again and order across events does
%% not matter.
-module(profile_archived_v1_to_sqlite_profiles).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"profile_archived_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    Data = maps:get(data, Event, Event),
    stored(jobs_read_model_store:exec(
           "INSERT INTO profiles (citizen, archived) VALUES (?, 1)"
           " ON CONFLICT(citizen) DO UPDATE SET archived = 1",
           [hex(maps:get(citizen_did, Data))]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).
