-module(mqtt_codec_SUITE).

-include_lib("mqtt/include/mqtt_packet.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0]).

-export([encode_decode/1]).

all() ->
    [encode_decode].

encode_decode(_Config) ->
    Packet = #mqtt_connect{
        protocol_name = ?PROTOCOL_NAME_V4,
        protocol_version = 4,
        clean_session = true,
        keep_alive = 60,
        client_id = <<"mqtt_client">>
    },
    Data = iolist_to_binary(mqtt_codec:encode(Packet, #{protocol_version => 4})),
    ?assertEqual({ok, Packet, <<>>}, mqtt_codec:decode(Data,
                                           #{protocol_version => 4,
                                             from => client})),

    Packet1 = #mqtt_connect{
        protocol_name = ?PROTOCOL_NAME_V5,
        protocol_version = 5,
        clean_session = true,
        keep_alive = 60,
        client_id = <<"mqtt_client">>
    },
    Data1 = iolist_to_binary(mqtt_codec:encode(Packet1, #{protocol_version => 5})),
    ?assertEqual({ok, Packet1, <<>>}, mqtt_codec:decode(Data1,
                                           #{protocol_version => 5,
                                             from => client})),
    ok.
