-module(karuta_newsletter_handler).

-export([init/2]).

-include_lib("stdlib/include/qlc.hrl").

init(Req0, State) ->
    #{offset := OffsetBin, category := CategoryBin} = cowboy_req:match_qs([
        {offset, [], <<"0">>},
        {category, [], <<"all">>}
    ], Req0),

    Offset = binary_to_integer(OffsetBin),
    Category = binary_to_atom(CategoryBin),

    Posts = case Category of
        all ->
            {ok, P} = karuta_newsletter:get_posts(Offset, 4),
            P;
        _ ->
            {ok, P} = karuta_newsletter:get_posts_by_category(Category, Offset, 4),
            P
    end,

    Html = render_posts(Posts),

    Req = cowboy_req:reply(200,
        #{<<"content-type">> => <<"text/html; charset=utf-8">>},
        Html,
        Req0
    ),
    {ok, Req, State}.

render_posts(Posts) ->
    lists:map(fun(Post) ->
        render_post_card(Post)
    end, Posts).

render_post_card({newsletter_post, _Id, Title, Excerpt, Content, Category, PubAt, Author}) ->
    CategoryLabel = category_to_label(Category),
    DateStr = format_date(PubAt),

    [<<"<article class=\"blog-post\">
        <div class=\"post-meta\">
            <span class=\"post-date\">">>, DateStr, <<"</span>
            <span class=\"post-separator\">•</span>
            <span class=\"post-category-label\">">>, CategoryLabel, <<"</span>
            <span class=\"post-separator\">•</span>
            <span class=\"post-author\">">>, Author, <<"</span>
        </div>
        <h2 class=\"post-title-link\"><a href=\"#\">">>, Title, <<"</a></h2>
        <div class=\"post-excerpt\">">>, Excerpt, <<"</div>
        <div class=\"post-full-content\">">>, Content, <<"</div>
    </article>">>].

category_to_label(release) -> <<"Release">>;
category_to_label(feature) -> <<"Feature">>;
category_to_label(roadmap) -> <<"Roadmap">>;
category_to_label(general) -> <<"General">>;
category_to_label(_) -> <<"General">>.

format_date(Timestamp) ->
    {{Y, M, D}, _} = calendar:system_time_to_universal_time(Timestamp, second),
    Month = month_to_name(M),
    Day = integer_to_binary(D),
    Year = integer_to_binary(Y),
    <<Month/binary, " ", Day/binary, ", ", Year/binary>>.

month_to_name(1) -> <<"Jan">>;
month_to_name(2) -> <<"Feb">>;
month_to_name(3) -> <<"Mar">>;
month_to_name(4) -> <<"Apr">>;
month_to_name(5) -> <<"May">>;
month_to_name(6) -> <<"Jun">>;
month_to_name(7) -> <<"Jul">>;
month_to_name(8) -> <<"Aug">>;
month_to_name(9) -> <<"Sep">>;
month_to_name(10) -> <<"Oct">>;
month_to_name(11) -> <<"Nov">>;
month_to_name(12) -> <<"Dec">>.
