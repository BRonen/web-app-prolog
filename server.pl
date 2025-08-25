:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(sqlite)).

%% Logs

log(info, Msg) :-
    format(user_output, "[LOG] ~w~n", [Msg]).
log(error, Msg) :-
    format(user_output, "[ERROR] ~w~n", [Msg]).

%% Database

row_to_user(row(Id, Name, Email, CreatedAt, UpdatedAt), User) :-
    User = _{id:Id, name:Name, email:Email, created_at:CreatedAt, updated_at:UpdatedAt}.

%% Routes

http_route('/health', get, _Request, Db) :-
    sqlite_prepare(Db, "SELECT sqlite_version()", Stmt),
    sqlite_one(Stmt, row(Ver)),
    reply_json_dict(_{srv:"root", sqlite:Ver}).

http_route('/users', get, _Request, Db) :-
    sqlite_prepare(Db, "SELECT * from users;", Stmt),
    sqlite_many(Stmt, _L, Rows, _),
    maplist(
        row_to_user,
        Rows,
        Users
    ),
    reply_json_dict(_{users:Users}).

http_route('/users', post, Request, Db) :- !,
    http_read_json_dict(Request, Body),
    log(info, Body),

    uuid(Uuid),
    get_dict(name, Body, Name),
    get_dict(email, Body, Email),

    sqlite_prepare(Db, "INSERT INTO users VALUES ( ?1, ?2, ?3, DATETIME(), DATETIME() ) RETURNING *;", Stmt),
    sqlite_bind(Stmt, bv(Uuid, Name, Email)),
    sqlite_one(Stmt, Row),
    row_to_user(Row, User),
    reply_json_dict(_{user:User}).

http_route(Path, get, _Request, Db) :-
    atom_concat('/users/', IdAtom, Path), !,
    sqlite_prepare(Db, "SELECT * FROM users WHERE id = ?1;", Stmt),
    sqlite_bind(Stmt, bv(IdAtom)),
    sqlite_one(Stmt, Row),
    row_to_user(Row, User),
    reply_json_dict(_{user:User}).

http_route(Path, delete, _Request, Db) :-
    atom_concat('/users/', IdAtom, Path), !,
    sqlite_prepare(Db, "DELETE FROM users WHERE id = ?1 RETURNING *;", Stmt),
    sqlite_bind(Stmt, bv(IdAtom)),
    sqlite_one(Stmt, Row),
    row_to_user(Row, User),
    reply_json_dict(_{user:User}).

http_route(Path, put, Request, Db) :-
    atom_concat('/users/', IdAtom, Path), !,
    http_read_json_dict(Request, Body),
    log(info, Body),

    get_dict(name, Body, Name),
    get_dict(email, Body, Email),

    sqlite_prepare(Db, "UPDATE users SET name = ?1, email = ?2, updated_at = datetime() WHERE id = ?3 RETURNING *;", Stmt),
    sqlite_bind(Stmt, bv(Name, Email, IdAtom)),
    sqlite_one(Stmt, Row),
    row_to_user(Row, User),
    reply_json_dict(_{user:User}).

http_route(_Path, _Method, _Request, _Db) :-
    reply_json_dict(_{error:"Not Found"}, [status(404)]).

%% Server setup

build_router_dispatcher(Db, Request) :-
    memberchk(path(Path), Request),
    memberchk(method(Method), Request),
    ( http_route(Path, Method, Request, Db) -> true
    ; reply_json_dict(_{error:"Unexpected error"}, [status(500)])
    ).

start(Port, DbPath) :-
    sqlite_open(DbPath, Db, [mode(write)]),
    http_server(build_router_dispatcher(Db), [port(Port)]).

stop(Port) :- http_stop_server(Port, []).

%% Database setup

is_dot('.')  :- !.
is_dot('..') :- !.
is_dot(_)    :- fail.

list_dir(Dir, Paths) :-
    directory_files(Dir, Entries),
    exclude(is_dot, Entries, Clean),
    maplist({Dir}/[Entry,Path]>>directory_file_path(Dir, Entry, Path), Clean, Paths).

read_file(F, B) :-
    open(F, read, S),
    read_string(S, _, B),
    close(S).

run_migration(Db, MigrationPath) :-
    read_file(MigrationPath, Migration),
    sqlite_prepare(Db, Migration, Stmt),
    sqlite_do(Stmt).

migrate(DbPath, MigrationDir) :-
    list_dir(MigrationDir, Paths),
    sqlite_open(DbPath, Db, [mode(write)]),
    maplist({Db}/[Path]>>run_migration(Db, Path), Paths).
