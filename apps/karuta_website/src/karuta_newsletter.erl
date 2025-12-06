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
    Posts = [
        {1, <<"Karuta 0.1.0 Released">>,
         <<"We're excited to announce the first release of Karuta, bringing logic programming to the BEAM!">>,
         <<"<p>After months of development, we're thrilled to announce the release of Karuta 0.1.0!</p>
            <p>This initial release includes:</p>
            <ul>
                <li>Core Prolog-style unification and pattern matching</li>
                <li>Tail call optimization for recursive predicates</li>
                <li>Integration with Mnesia through the Domino relational layer</li>
                <li>Full interoperability with Erlang/OTP</li>
            </ul>
            <p>Try it out and let us know what you think!</p>">>,
         release, erlang:system_time(second) - 86400 * 7, <<"Karuta Team">>},

        {2, <<"Introducing Domino: Relations as First-Class Types">>,
         <<"Learn how Domino implements E.F. Codd's extended relational model using Mnesia.">>,
         <<"<p>Domino is Karuta's relational database layer, built on top of Mnesia.</p>
            <p>Unlike traditional ORMs, Domino treats relations as first-class types. This means:</p>
            <ul>
                <li>Relations are not just data storage—they're part of the type system</li>
                <li>Type checking includes relational integrity constraints</li>
                <li>Queries are expressed in pure logic, not SQL</li>
                <li>The compiler can verify relational consistency at compile time</li>
            </ul>
            <p>This approach aligns perfectly with E.F. Codd's vision of the relational model.</p>">>,
         feature, erlang:system_time(second) - 86400 * 14, <<"Mateus Magueta">>},

        {3, <<"Roadmap: Pattern Guards and Constraint Logic Programming">>,
         <<"A preview of what's coming in Karuta 0.2.0 and beyond.">>,
         <<"<p>We're planning exciting features for the next releases:</p>
            <h3>Karuta 0.2.0</h3>
            <ul>
                <li>Pattern guards for more expressive matching</li>
                <li>Improved error messages with source locations</li>
                <li>Better REPL experience</li>
            </ul>
            <h3>Karuta 0.3.0</h3>
            <ul>
                <li>Constraint Logic Programming (CLP) support</li>
                <li>Tabled evaluation for optimization</li>
                <li>Module system for code organization</li>
            </ul>
            <p>Stay tuned for updates!</p>">>,
         roadmap, erlang:system_time(second) - 86400 * 21, <<"Karuta Team">>},

        {4, <<"How Karuta Optimizes Tail Recursion">>,
         <<"A deep dive into how we leverage the BEAM's tail call optimization.">>,
         <<"<p>One of Karuta's key features is automatic tail call optimization for recursive predicates.</p>
            <p>When you write a tail-recursive predicate like:</p>
            <pre><code>factorial[X, Out] :- 'factorial loop'[X, 1, Out].
'factorial loop'[0, Out, Out].
'factorial loop'[N, Acc, Out] :-
    multiply[N, Acc, NewAcc],
    plus[N, -1, Prev],
    'factorial loop'[Prev, NewAcc, Out].</code></pre>
            <p>Karuta compiles this to use the BEAM's tail call optimization, turning it into an efficient loop.</p>
            <p>No stack growth, no overflow—just clean, efficient recursion!</p>">>,
         feature, erlang:system_time(second) - 86400 * 28, <<"Mateus Magueta">>}
    ],

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
