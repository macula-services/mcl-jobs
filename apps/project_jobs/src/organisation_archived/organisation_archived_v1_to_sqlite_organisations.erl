%% @doc Projects organisation_archived_v1 into the organisations table. Archives the organisation: it leaves the page, and answers by id as archived.
%%
%% One upsert setting only this event's columns (jobs_read_model_store says
%% why), so a replay is the same write again and order across events does
%% not matter.
-module(organisation_archived_v1_to_sqlite_organisations).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"organisation_archived_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    Data = maps:get(data, Event, Event),
    stored(jobs_read_model_store:exec(
           "INSERT INTO organisations (organisation_id, archived) VALUES (?, 1)"
           " ON CONFLICT(organisation_id) DO UPDATE SET archived = 1",
           [maps:get(organisation_id, Data)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.
