%% @doc Projects profile_withdrawn_v1 into the profiles table. Hides the profile again, unless a later publication is already there.
%%
%% One upsert setting only this event's columns (jobs_read_model_store says
%% why), so a replay is the same write again and order across events does
%% not matter.
-module(profile_withdrawn_v1_to_sqlite_profiles).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"profile_withdrawn_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    Data = maps:get(data, Event, Event),
    stored(jobs_read_model_store:exec(
           "INSERT INTO profiles (citizen, published, published_version) VALUES (?, 0, ?)"
           " ON CONFLICT(citizen) DO UPDATE SET published = excluded.published,"
           " published_version = excluded.published_version"
           " WHERE excluded.published_version > profiles.published_version",
           [hex(maps:get(citizen_did, Data)), maps:get(version, Event, 0)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).
