-module(karuta_newsletter_page_handler).

-export([init/2]).

init(Req0, State) ->
    Html = render_newsletter_page(),
    Req = cowboy_req:reply(200,
        #{<<"content-type">> => <<"text/html; charset=utf-8">>},
        Html,
        Req0
    ),
    {ok, Req, State}.

render_newsletter_page() ->
    {ok, InitialPosts} = karuta_newsletter:get_posts(0, 4),
    InitialPostsHtml = lists:map(fun(Post) ->
        render_post_card(Post)
    end, InitialPosts),

    [header(), nav(), newsletter_hero(), newsletter_section(InitialPostsHtml), footer()].

header() ->
    <<"<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Karuta Newsletter - Development Updates</title>
    <link rel=\"icon\" type=\"image/x-icon\" href=\"/favicon.ico\">
    <link rel=\"stylesheet\" href=\"/static/css/style.css\">
    <script type=\"module\" src=\"https://cdn.jsdelivr.net/npm/@sudodevnull/datastar\"></script>
</head>
<body>">>.

nav() ->
    <<"<nav class=\"navbar\">
        <div class=\"container\">
            <div class=\"nav-brand\">
                <img src=\"/static/images/domino.png\" alt=\"Karuta Logo\" class=\"logo\">
                <span class=\"brand-name\">Karuta</span>
            </div>
            <div class=\"nav-links\">
                <a href=\"/\">Home</a>
                <a href=\"#newsletter\">Newsletter</a>
                <a href=\"https://github.com/dont-rely-on-nulls/karuta\" target=\"_blank\">GitHub</a>
            </div>
        </div>
    </nav>">>.

newsletter_hero() ->
    <<"<section class=\"blog-hero\">
        <div class=\"container\">
            <h1 class=\"blog-title\">Development Newsletter</h1>
        </div>
    </section>">>.

newsletter_section(InitialPostsHtml) ->
    [<<"<section class=\"blog-content\">
        <div class=\"container\" data-store=\"{offset: 4, category: 'all', hasMore: true}\">
            <div class=\"blog-main\" style=\"max-width: 900px; margin: 0 auto;\">
                <div id=\"posts-list\" class=\"posts-list\">
                    ">>, InitialPostsHtml, <<"
                </div>
                <div class=\"load-more-container\" data-show=\"hasMore\">
                    <a href=\"#\" class=\"load-more-link\"
                       data-on-click=\"$get('/newsletter/posts?offset=' + offset + '&category=' + category).fragments('#posts-list'); offset = offset + 4\">
                        Load More Posts →
                    </a>
                </div>
            </div>
        </div>
    </section>">>].

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

footer() ->
    <<"<footer class=\"footer\">
        <div class=\"container\">
            <p>&copy; 2024 Karuta. Built with logic and love on the BEAM.</p>
        </div>
    </footer>
</body>
</html>">>.
