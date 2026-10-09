%% @doc The QRY division's SQLite store: one gen_server owning one esqlite
%% connection to the file project_jobs writes.
%%
%% READ-ONLY BY API: only q/2 is exposed, so no query desk can write. The
%% schema is jobs_read_model_store's; this process opens the same file after
%% project_jobs has created it (query_jobs depends on project_jobs).
-module(jobs_query_store).

-behaviour(gen_server).

-export([start_link/1, q/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {conn :: esqlite3:esqlite3()}).

-spec start_link(string()) -> {ok, pid()} | {error, term()}.
start_link(SqlitePath) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, SqlitePath, []).

%% @doc One parameterised read: rows as lists of cells in SELECT order, or
%% {error, Reason}.
-spec q(string(), list()) -> [list()] | {error, term()}.
q(Sql, Args) ->
    gen_server:call(?MODULE, {q, Sql, Args}, 5000).

init(SqlitePath) ->
    opened(esqlite3:open(SqlitePath)).

opened({ok, Conn}) -> {ok, #state{conn = Conn}};
opened({error, Reason}) -> {stop, {open_failed, Reason}}.

handle_call({q, Sql, Args}, _From, #state{conn = Conn} = State) ->
    {reply, esqlite3:q(Conn, Sql, Args), State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.
