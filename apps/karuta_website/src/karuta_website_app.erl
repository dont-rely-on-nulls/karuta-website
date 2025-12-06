-module(karuta_website_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    karuta_newsletter:init_schema(),
    karuta_newsletter:create_table(),
    karuta_newsletter:seed_data(),

    Dispatch = cowboy_router:compile([
        {'_', [
            {"/", karuta_website_handler, []},
            {"/newsletter", karuta_newsletter_page_handler, []},
            {"/newsletter/posts", karuta_newsletter_handler, []},
            {"/favicon.ico", cowboy_static, {priv_file, karuta_website, "static/favicon.ico"}},
            {"/static/[...]", cowboy_static, {priv_dir, karuta_website, "static"}}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(http_listener,
        [{port, 8080}],
        #{env => #{dispatch => Dispatch}}
    ),
    karuta_website_sup:start_link().

stop(_State) ->
    ok.
