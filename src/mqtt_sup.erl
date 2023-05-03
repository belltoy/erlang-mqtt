-module(mqtt_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Flags = #{strategy => one_for_one, intensity => 5, period => 10},
    Children = [#{id => mqtt_client_sup,
                   start => {mqtt_client_sup, start_link, []},
                   restart => permanent,
                   shutdown => 5000,
                   type => supervisor,
                   modules => [mqtt_client_sup]}],
    {ok, {Flags, Children}}.
