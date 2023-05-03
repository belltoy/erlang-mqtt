-module(prop_mqtt_codec_SUITE).

-include_lib("mqtt/include/mqtt_packet.hrl").
-include_lib("proper/include/proper.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0]).

-export([prop_codec/1, prop_string_too_long/1]).

all() ->
    [prop_codec, prop_string_too_long].

prop_codec(_Config) ->
    ?assert(proper:quickcheck(prop_protocol_codec())).

prop_string_too_long(_Config) ->
    ?assert(proper:quickcheck(prop_codec_too_long_string())).

prop_protocol_codec() ->
    ?FORALL(Packet, client_packet(),
            begin
                try
                    ProtocolVersion = Packet#mqtt_connect.protocol_version,
                    Bin = mqtt_codec:encode(Packet,
                                            #{protocol_version => ProtocolVersion,
                                              from => client}),
                    case mqtt_codec:decode(iolist_to_binary(Bin),
                                           #{protocol_version => ProtocolVersion,
                                             from => client}) of
                        {ok, _, _} -> true
                    end
                catch
                    _:Reason ->
                        ct:pal("Codec error: ~p ~p~n", [Reason, iolist_size(Packet#mqtt_connect.client_id)]),
                        false
                end
            end).

prop_codec_too_long_string() ->
    ?FORALL(Packet, connect_packet(false),
            begin
                ProtocolVersion = Packet#mqtt_connect.protocol_version,
                ?assertError(
                   string_too_long,
                   mqtt_codec:encode(Packet,
                                     #{protocol_version => ProtocolVersion,
                                       from => client})),
                true
            end).

client_packet() ->
    connect_packet(true).

connect_packet(Valid) ->
    ?LET({ProtocolName, ProtocolVersion}, protocol(),
          ?LET(ClientId, case Valid of
                             true -> valid_utf8_string();
                             false -> invalid_utf8_string()
                         end,
               #mqtt_connect{
                   protocol_name = ProtocolName,
                   protocol_version = ProtocolVersion,
                   clean_session = boolean(),
                   keep_alive = 60,
                   client_id = unicode:characters_to_binary(ClientId)
               })).

valid_utf8_string() ->
    ?SUCHTHAT(X, proper_unicode:utf8(),
              erlang:byte_size(X) =< 16#FFFF andalso
              mqtt_utf8:validate_utf8_string(X)).

invalid_utf8_string() ->
    ?SUCHTHAT(X,
        %% Slow
        % ?LET(C,
        %      ?LET(X, proper_types:integer(16#1_0000, 16#1_0010),
        %              proper_types:vector(X, proper_unicode:utf8(1))),
        %      unicode:characters_to_binary(C)),

        ?LET(X, proper_unicode:utf8(1),
                 unicode:characters_to_binary(
                   [ unicode:characters_to_binary(X) || _ <- lists:seq(1, 16#1_0010)]
                 )
            ),
        erlang:byte_size(X) > 16#FFFF).

protocol() ->
    ?LET({ok, ProtocolVersion}, proper_gen:pick(proper_types:range(3, 5)),
         begin
             case ProtocolVersion of
                 3 -> {<<"MQIsdp">>, 3};
                 _ -> {<<"MQTT">>, ProtocolVersion}
             end
         end).
