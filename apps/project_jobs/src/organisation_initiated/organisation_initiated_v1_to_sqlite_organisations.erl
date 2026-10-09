%% @doc Projects organisation_initiated_v1 into the organisations table. Records the organisation, its name and its initiator.
%%
%% One upsert setting only this event's columns (jobs_read_model_store says
%% why), so a replay is the same write again and order across events does
%% not matter.
-module(organisation_initiated_v1_to_sqlite_organisations).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"organisation_initiated_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    Data = maps:get(data, Event, Event),
    stored(jobs_read_model_store:exec(
           "INSERT INTO organisations (organisation_id, name, initiated_by, initiated_at)"
           " VALUES (?, ?, ?, ?)"
           " ON CONFLICT(organisation_id) DO UPDATE SET name = excluded.name,"
           " initiated_by = excluded.initiated_by, initiated_at = excluded.initiated_at",
           [maps:get(organisation_id, Data), maps:get(name, Data),
            hex(maps:get(initiated_by, Data)), maps:get(initiated_at, Data)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).
