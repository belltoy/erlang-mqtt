-module(mqtt_codec).

-include("mqtt_packet.hrl").

-export([decode/2]).

-export([encode/2]).

-export_type([
    opts/0,
    topic/0,
    qos/0,
    packet_id/0,
    packet/0
]).

-type opts() :: #{
    from := client | server,
    protocol_version => 3 | 4 | 5,
    max_payload => non_neg_integer()
}.

-type topic() :: unicode:unicode_binary().
-type qos() :: 0 | 1 | 2.
-type packet_id() :: 1..65535.
-type packet() ::
    #mqtt_connect{} |
    #mqtt_connack{} |
    #mqtt_publish{} |
    #mqtt_puback{} |
    #mqtt_pubrec{} |
    #mqtt_pubrel{} |
    #mqtt_pubcomp{} |
    #mqtt_subscribe{} |
    #mqtt_suback{} |
    #mqtt_unsubscribe{} |
    #mqtt_unsuback{} |
    #mqtt_pingreq{} |
    #mqtt_pingresp{} |
    #mqtt_disconnect{} |
    #mqtt_auth{}.

-spec encode(packet(), opts()) -> iodata().
encode(Packet, Opts) ->
    mqtt_encoder:encode(Packet, Opts).

-spec decode(binary(), opts()) -> Result
    when Result :: {ok, packet(), Rest}
                 | {error, Reason}
                 | incomplete,
         Rest :: binary(),
         Reason :: mqtt_decoder:error_reason().
decode(Data, Opts) ->
    mqtt_decoder:decode(Data, Opts).
