-module(karuta_newsletter).

-export([
    init_schema/0,
    create_table/0,
    seed_data/0,
    get_posts/2,
    get_posts_by_category/3,
    add_post/6
]).

-record(newsletter_post, {
    id,
    title,
    excerpt,
    content,
    category,
    published_at,
    author
}).

init_schema() ->
    case mnesia:create_schema([node()]) of
        ok -> ok;
        {error, {_, {already_exists, _}}} -> ok;
        Error -> Error
    end.

create_table() ->
    mnesia:start(),
    case mnesia:create_table(newsletter_post, [
        {attributes, record_info(fields, newsletter_post)},
        {disc_copies, [node()]},
        {type, set}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, newsletter_post}} -> ok;
        Error -> Error
    end.

seed_data() ->
    Posts = [],

    F = fun() ->
        lists:foreach(fun({Id, Title, Excerpt, Content, Category, PubAt, Author}) ->
            Post = #newsletter_post{
                id = Id,
                title = Title,
                excerpt = Excerpt,
                content = Content,
                category = Category,
                published_at = PubAt,
                author = Author
            },
            mnesia:write(Post)
        end, Posts)
    end,
    mnesia:transaction(F).

get_posts(Offset, Limit) ->
    F = fun() ->
        All = mnesia:match_object(#newsletter_post{_ = '_'}),
        Sorted = lists:reverse(lists:keysort(#newsletter_post.published_at, All)),
        lists:sublist(Sorted, Offset + 1, Limit)
    end,
    case mnesia:transaction(F) of
        {atomic, Posts} -> {ok, Posts};
        Error -> Error
    end.

get_posts_by_category(Category, Offset, Limit) ->
    F = fun() ->
        All = mnesia:match_object(#newsletter_post{category = Category, _ = '_'}),
        Sorted = lists:reverse(lists:keysort(#newsletter_post.published_at, All)),
        lists:sublist(Sorted, Offset + 1, Limit)
    end,
    case mnesia:transaction(F) of
        {atomic, Posts} -> {ok, Posts};
        Error -> Error
    end.

add_post(Id, Title, Excerpt, Content, Category, Author) ->
    F = fun() ->
        Post = #newsletter_post{
            id = Id,
            title = Title,
            excerpt = Excerpt,
            content = Content,
            category = Category,
            published_at = erlang:system_time(second),
            author = Author
        },
        mnesia:write(Post)
    end,
    mnesia:transaction(F).
