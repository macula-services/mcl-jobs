%% @doc The PRJ division's SQLite store: one gen_server owning one esqlite
%% connection, the only writer of the read model.
%%
%% A NIF connection belongs to the process that opened it, so every write goes
%% through this process. The DDL lives here and only here; query_jobs reads the
%% schema this module creates, and a schema-contract test pins the columns the
%% query desks select to the columns declared here.
%%
%% Every write is one upsert that sets only the columns of the event it
%% projects, so events of one stream may arrive in any order. The two groups
%% that an event can set back (the description, and published) carry their
%% own version, and a write older than what is there changes nothing. A row a
%% later event created before its initiation has initiated_at NULL, and the
%% query side treats it as not there.
-module(jobs_read_model_store).

-behaviour(gen_server).

-export([start_link/1, exec/2, q/2, schema/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {conn :: esqlite3:esqlite3()}).

%% @doc The schema, in creation order: the one place the read model's shape is
%% written down. Ids are lowercase hex; skills are newline-separated (a skill
%% can carry no control character); flags are 0 or 1.
-spec schema() -> [string()].
schema() ->
    ["CREATE TABLE IF NOT EXISTS profiles ("
     " citizen            TEXT PRIMARY KEY,"
     " initiated_at       INTEGER,"
     " headline           TEXT,"
     " skills             TEXT,"
     " location           TEXT,"
     " described_version  INTEGER NOT NULL DEFAULT -1,"
     " published          INTEGER NOT NULL DEFAULT 0,"
     " published_version  INTEGER NOT NULL DEFAULT -1,"
     " archived           INTEGER NOT NULL DEFAULT 0)",
     "CREATE TABLE IF NOT EXISTS organisations ("
     " organisation_id    TEXT PRIMARY KEY,"
     " name               TEXT,"
     " initiated_by       TEXT,"
     " initiated_at       INTEGER,"
     " archived           INTEGER NOT NULL DEFAULT 0)"].

-spec start_link(string()) -> {ok, pid()} | {error, term()}.
start_link(SqlitePath) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, SqlitePath, []).

%% @doc One parameterised write: ok, or {error, Reason}, which a projection
%% returns as {error, {store_error, Reason}} for evoq to retry.
-spec exec(string(), list()) -> ok | {error, term()}.
exec(Sql, Args) ->
    gen_server:call(?MODULE, {exec, Sql, Args}, 5000).

%% @doc One parameterised read, for tests and inspection.
-spec q(string(), list()) -> [list()] | {error, term()}.
q(Sql, Args) ->
    gen_server:call(?MODULE, {q, Sql, Args}, 5000).

init(SqlitePath) ->
    ok = filelib:ensure_dir(SqlitePath),
    opened(esqlite3:open(SqlitePath)).

opened({ok, Conn}) -> schemed(Conn, create_schema(Conn, schema()));
opened({error, Reason}) -> {stop, {open_failed, Reason}}.

schemed(Conn, ok) -> {ok, #state{conn = Conn}};
schemed(_Conn, {error, Reason}) -> {stop, {schema_failed, Reason}}.

handle_call({exec, Sql, Args}, _From, #state{conn = Conn} = State) ->
    {reply, written(esqlite3:q(Conn, Sql, Args)), State};
handle_call({q, Sql, Args}, _From, #state{conn = Conn} = State) ->
    {reply, esqlite3:q(Conn, Sql, Args), State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

create_schema(Conn, [Sql | Rest]) -> next_ddl(esqlite3:exec(Conn, Sql), Conn, Rest);
create_schema(_Conn, []) -> ok.

next_ddl(ok, Conn, Rest) -> create_schema(Conn, Rest);
next_ddl({error, _} = E, _Conn, _Rest) -> E.

written([]) -> ok;
written({error, _} = E) -> E;
written(Rows) -> {error, {unexpected_rows, Rows}}.
