%% @doc OTP application entry for the PRJ division.
%%
%% Starting this app opens the SQLite read model and registers the
%% projections with evoq. mcl_jobs lists this app among its own, so it starts
%% first, and by the time mcl_jobs_app opens the store subscription and its
%% catch-up replay runs, every projection is listening.
-module(project_jobs_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> project_jobs_sup:start_link().

stop(_State) -> ok.
