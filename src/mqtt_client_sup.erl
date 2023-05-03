-module(mqtt_client_sup).

-behaviour(supervisor).

-export([start_client/4]).

-export([start_link/0]).

-export([init/1]).

start_client(Owner, Host, Port, Opts) ->
    supervisor:start_child(?MODULE, [Owner, Host, Port, Opts]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Flags = #{strategy => simple_one_for_one, intensity => 5, period => 10},
    Children = [
        #{
            id => mqtt_client,
            start => {mqtt_client, start_link, []},
            restart => temporary,
            type => worker
        }
    ],
    {ok, {Flags, Children}}.
