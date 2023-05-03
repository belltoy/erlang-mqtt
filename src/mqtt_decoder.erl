-module(mqtt_decoder).

-include("mqtt_packet.hrl").

-export([decode/2]).

-export_type([error_reason/0]).

-type error_reason() :: unsupported_protocol
                      | {malformed_packet, <<_:8>>}
                      | empty_topic_filters
                      | malformed_packet
                      | malformed_will
                      | malformed_topics
                      | protocol_error
                      | malformed_string_pair
                      | malformed_string
                      | malformed_binary
                      | invalid_qos
                      | invalid_retain_handling
                      | unknown_property
                      | packet_too_large
                      | zero_packet_id
                      | {property_more_than_once, atom()}.

-define(PUT_NEW(Key, Value, Map), case maps:is_key(Key, Map) of
    true -> error({property_more_than_once, Key});
    false -> maps:put(Key, Value, Map)
end).

-spec decode(binary(), mqtt_codec:opts()) -> Result
    when Result :: {ok, mqtt_codec:packet(), Rest}
                 | {error, Reason}
                 | incomplete,
         Rest :: binary(),
         Reason :: error_reason().
decode(<<Data/binary>>, _Opts) when erlang:byte_size(Data) < 2 ->
    incomplete;
decode(<<Header:1/binary, Bin/binary>>, Opts) ->
    %% TODO: incomplete
    {Len, Rest} = decode_variable_length(Bin),
    decode(Header, Len, Rest, Opts).

decode(Header, RemainingLength, Data, Opts) ->
    MaxPayload = min(maps:get(max_payload, Opts, ?MAX_PACKET_SIZE), ?MAX_PACKET_SIZE),
    case {RemainingLength > MaxPayload, Data} of
        {true, _} ->
            {error, packet_too_large};
        {false, <<Payload:RemainingLength/binary, Rest/binary>>} ->
            try
                Packet = decode_packet(Header, Payload, Opts),
                %% TODO: Validate packet for protocol errors
                {ok, Packet, Rest}
            catch
                error:Reason ->
                    {error, Reason}
            end;
        _ ->
            incomplete
    end.

%% TODO: Doc
-spec decode_packet(FixedHeader, binary(), mqtt_codec:opts()) -> mqtt_codec:packet()
    when FixedHeader :: <<_:8>>.
decode_packet(<<?CONNECT:4, 0:4>>,
              <<ProtoNameLen:16, ProtoName:ProtoNameLen/binary, ProtoVersion:8, Rest/binary>>,
              #{from := client} = Opts) ->
    case {ProtoName, ProtoVersion} of
        {<<"MQIsdp">>, 3} ->
            decode_connect(ProtoName, ProtoVersion, Rest, Opts);
        {<<"MQTT">>, Ver} when Ver =:= 4; Ver =:= 5 ->
            decode_connect(ProtoName, ProtoVersion, Rest, Opts);
        _ ->
            error(unsupported_protocol)
    end;

decode_packet(<<?CONNACK:4, 0:4>>,
              <<0:7, SessionPresent:1, ReasonCode:8, Rest/binary>>,
              #{from := server} = Opts) ->
    {Properties, Rest1} = decode_properties(Rest, connack, Opts),
    ensure_end_of_packet(Rest1),
    #mqtt_connack{
        session_present = SessionPresent =:= 1,
        reason_code = ReasonCode,
        properties = Properties
    };

decode_packet(<<?PUBLISH:4, Dup:1, QoS0:2, Retain:1>>,
              <<TopicLen:16, Topic:TopicLen/binary, Rest/binary>>,
              Opts) ->
    QoS = decode_qos(QoS0),
    {PacketId1, Rest2} =
        case {QoS, Rest} of
            {0, _} -> {undefined, Rest};
            {_, <<PacketId:16, Rest1/binary>>} ->
                ok = check_packet_id(PacketId),
                {PacketId, Rest1}
        end,
    {Properties, Payload} = decode_properties(Rest2, publish, Opts),
    #mqtt_publish{
        topic = decode_topic(Topic),
        message = Payload,
        dup = Dup =:= 1,
        qos = QoS,
        retain = Retain =:= 1,
        packet_id = PacketId1,
        properties = Properties
    };

decode_packet(<<?PUBACK:4, 0:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {ReasonCode, Properties} = decode_reason_code_and_properties(Rest, puback, Opts),
    #mqtt_puback{packet_id = PacketId, reason_code = ReasonCode, properties = Properties};

decode_packet(<<?PUBREC:4, 0:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {ReasonCode, Properties} = decode_reason_code_and_properties(Rest, pubrec, Opts),
    #mqtt_pubrec{packet_id = PacketId, reason_code = ReasonCode, properties = Properties};

decode_packet(<<?PUBREL:4, 2#0010:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {ReasonCode, Properties} = decode_reason_code_and_properties(Rest, pubrel, Opts),
    #mqtt_pubrel{packet_id = PacketId, reason_code = ReasonCode, properties = Properties};

decode_packet(<<?PUBCOMP:4, 0:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {ReasonCode, Properties} = decode_reason_code_and_properties(Rest, pubcomp, Opts),
    #mqtt_pubcomp{packet_id = PacketId, reason_code = ReasonCode, properties = Properties};

decode_packet(<<?SUBSCRIBE:4, 2#0010:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {Properties, Payload} = decode_properties(Rest, subscribe, Opts),
    case decode_subscription(Payload, Opts) of
        [] -> error(empty_topic_filters);
        T ->
            #mqtt_subscribe{
                packet_id = PacketId,
                topic_filters = T,
                properties = Properties
            }
    end;

decode_packet(<<?SUBACK:4, 0:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {Properties, Payload} = decode_properties(Rest, suback, Opts),
    #mqtt_suback{
        packet_id = PacketId,
        reason_codes = decode_reason_codes(Payload),
        properties = Properties
    };

decode_packet(<<?UNSUBSCRIBE:4, 2#0010:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {Properties, Payload} = decode_properties(Rest, unsubscribe, Opts),
    #mqtt_unsubscribe{
        packet_id = PacketId,
        topic_filters = decode_unsubscribe_topics(Payload),
        properties = Properties
    };

decode_packet(<<?UNSUBACK:4, 0:4>>, <<PacketId:16, Rest/binary>>, Opts) ->
    ok = check_packet_id(PacketId),
    {Properties, Payload} = decode_properties(Rest, unsuback, Opts),
    #mqtt_unsuback{
        packet_id = PacketId,
        reason_codes = decode_reason_codes(Payload),
        properties = Properties
    };

decode_packet(<<?PINGREQ:4, 0:4>>, <<>>, _Opts) ->
    #mqtt_pingreq{};

decode_packet(<<?PINGRESP:4, 0:4>>, <<>>, _Opts) ->
    #mqtt_pingresp{};

decode_packet(<<?DISCONNECT:4, 0:4>>, <<Rest/binary>>, Opts) ->
    {ReasonCode, Properties} = decode_reason_code_and_properties(Rest, disconnect, Opts),
    #mqtt_disconnect{reason_code = ReasonCode, properties = Properties};

decode_packet(<<?AUTH:4, 0:4>>,
              <<ReasonCode:8, Rest/binary>>,
              #{protocol_version := ?PROTOCOL_V5} = Opts) ->
    {Properties, Rest1} = decode_properties(Rest, auth, Opts),
    ensure_end_of_packet(Rest1),
    #mqtt_auth{
        reason_code = ReasonCode,
        properties = Properties
    };

decode_packet(Header, _Data, _Opts) ->
    error({malformed_packet, Header}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Private functions for decoding
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

decode_bool(0) -> false;
decode_bool(1) -> true;
decode_bool(_) -> error(protocol_error).

-spec decode_qos(0 | 1 | 2 | any()) -> 0 | 1 | 2.
decode_qos(0) -> 0;
decode_qos(1) -> 1;
decode_qos(2) -> 2;
decode_qos(_) -> error(invalid_qos).

-spec decode_retain_handling(0 | 1 | 2 | any()) -> 0 | 1 | 2.
decode_retain_handling(0) -> send_at_subscribe;
decode_retain_handling(1) -> send_if_not_exists;
decode_retain_handling(2) -> do_not_send;
decode_retain_handling(_) -> error(invalid_retain_handling).

decode_variable_length(<<0:1, Len:7, Rest/binary>>) ->
    {Len, Rest};
decode_variable_length(<<1:1, Len1:7, 0:1, Len2:7, Rest/binary>>) ->
    {Len1 + (Len2 bsl 7), Rest};
decode_variable_length(<<1:1, Len1:7, 1:1, Len2:7, 0:1, Len3:7, Rest/binary>>) ->
    {Len1 + (Len2 bsl 7) + (Len3 bsl 14), Rest};
decode_variable_length(<<1:1, Len1:7, 1:1, Len2:7, 1:1, Len3:7, 0:1, Len4:7, Rest/binary>>) ->
    {Len1 + (Len2 bsl 7) + (Len3 bsl 14) + (Len4 bsl 21), Rest}.

decode_connect(ProtoName, ProtoVersion,
               <<HasUsername:1,
                 HasPassword:1,
                 LastWillFlags:4/bits,
                 CleanSession:1,
                 0:1,  %% Reserved(0)
                 KeepAlive:16,
                 Rest/binary>>, Opts0) ->
    Opts                  = Opts0#{protocol_version => ProtoVersion},
    {Properties, Payload} = decode_properties(Rest, connect, Opts),
    {ClientId, Rest2}     = decode_utf8_string(Payload),
    {Will, Rest3}         = decode_last_will(LastWillFlags, Rest2, Opts),
    {Username, Rest4}     = decode_optional_string(HasUsername, Rest3),
    {Password, Rest5}      = decode_optional_string(HasPassword, Rest4),
    ensure_end_of_packet(Rest5),
    #mqtt_connect{
       protocol_name    = ProtoName,
       protocol_version = ProtoVersion,
       last_will        = Will,
       clean_session    = CleanSession =:= 1,
       keep_alive       = KeepAlive,
       client_id        = ClientId,
       username         = Username,
       password         = Password,
       properties       = Properties
    }.

decode_last_will(<<0:1, 0:2, 0:1>>, Payload, _Opts) ->
    {undefined, Payload};
decode_last_will(<<Retain:1, QoS0:2, 1:1>>, Rest, Opts) ->
    QoS = decode_qos(QoS0),
    {WillProperties, Rest1} = decode_properties(Rest, will_properties, Opts),
    case Rest1 of
        <<TopicLen:16, Topic:TopicLen/binary,
          MessageLen:16, Message:MessageLen/binary, Rest2/binary>> ->
            {#mqtt_last_will{
                topic = decode_topic(Topic),
                message = Message,
                qos = QoS,
                retain = Retain =:= 1,
                properties = WillProperties
            }, Rest2};
        _ ->
            error(malformed_will)
    end;
decode_last_will(<<_:1, _:2, _:1>>, _Rest, _Opts) ->
    error(malformed_will).

decode_topic(Topic) ->
    %% TODO: validate topic
    Topic.

ensure_end_of_packet(<<>>) ->
    ok;
ensure_end_of_packet(_Rest) ->
    error(malformed_packet).

decode_utf8_string_pair(<<KeyLen:16, Key:KeyLen/binary,
                          ValLen:16, Val:ValLen/binary,
                          Rest/binary>>) ->
    %% TODO: Validate UTF-8
    {{Key, Val}, Rest};
decode_utf8_string_pair(_) ->
    error(malformed_string_pair).

decode_optional_string(0, Payload) ->
    {undefined, Payload};
decode_optional_string(1, Payload) ->
    decode_utf8_string(Payload).

decode_utf8_string(<<Len:16, String:Len/binary, Rest/binary>>) ->
    %% Validate UTF-8
    case mqtt_utf8:validate_utf8_string(String) of
        true -> {String, Rest};
        false -> error(malformed_string)
    end;
decode_utf8_string(_R) ->
    error(malformed_string).

decode_binary_data(<<Len:16, Binary:Len/binary, Rest/binary>>) ->
    {Binary, Rest};
decode_binary_data(_) ->
    error(malformed_binary).

decode_subscription(Topics, Opts) ->
    decode_subscription(Topics, Opts, []).

decode_subscription(
    <<Len:16, Topic:Len/binary, 0:2, Rh:2, Rap:1, NL:1, QoS:2, Rest/binary>>,
    #{protocol_version := ?PROTOCOL_V5} = Opts, Acc) ->
    %% TODO: Validate topic filter
    Sub = #mqtt_subscription{
        topic_filter = decode_topic(Topic),
        max_qos = decode_qos(QoS),
        retain_handling = decode_retain_handling(Rh),
        retain_as_published = decode_bool(Rap),
        no_local = decode_bool(NL)
    },
    decode_subscription(Rest, Opts, [Sub | Acc]);
decode_subscription(
    <<Len:16, Topic:Len/binary, 0:6, QoS:2, Rest/binary>>, Opts, Acc) ->
    %% TODO: Validate topic filter
    Sub = #mqtt_subscription{topic_filter = decode_topic(Topic), max_qos = decode_qos(QoS)},
    decode_subscription(Rest, Opts, [Sub | Acc]);
decode_subscription(<<>>, _Opts, Acc) ->
    lists:reverse(Acc);
decode_subscription(Topics, _Opts, _) ->
    error({malformed_topics, Topics}).

decode_reason_codes(ReturnCodes) ->
    decode_reason_codes(ReturnCodes, []).

decode_reason_codes(<<ReasonCode:8, Rest/binary>>, Acc) ->
    decode_reason_codes(Rest, [ReasonCode | Acc]);
decode_reason_codes(<<>>, Acc) ->
    lists:reverse(Acc);
decode_reason_codes(_, _) ->
    error(malformed_packet).

decode_unsubscribe_topics(Topics) ->
    decode_unsubscribe_topics(Topics, []).

decode_unsubscribe_topics(<<Len:16, Topic:Len/binary, Rest/binary>>, Acc) ->
    T = decode_topic(Topic),
    decode_unsubscribe_topics(Rest, [T | Acc]);
decode_unsubscribe_topics(<<>>, Acc) ->
    lists:reverse(Acc);
decode_unsubscribe_topics(Topics, _) ->
    error({malformed_topics, Topics}).

check_packet_id(0) -> error(zero_packet_id);
check_packet_id(_PacketId) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Private functions for decoding properties
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

default_reason_code(PacketType) ->
    case PacketType of
        puback -> ?REASON_CODE_SUCCESS;
        pubrec -> ?REASON_CODE_SUCCESS;
        pubrel -> ?REASON_CODE_SUCCESS;
        pubcomp -> ?REASON_CODE_SUCCESS;
        disconnect -> ?REASON_CODE_NORMAL_DISCONNECTION
    end.

%% TODO: Protocol versions
-spec decode_reason_code_and_properties(binary(), PacketType, map()) ->
    {integer(), undefined | map(), binary()}
      when PacketType :: puback | pubrec | pubrel | pubcomp | disconnect.
decode_reason_code_and_properties(<<>>, PacketType, _Opts) ->
    {default_reason_code(PacketType), undefined};
decode_reason_code_and_properties(<<ReasonCode:8>>,
                                           _PacketType, _Opts) ->
    {ReasonCode, undefined};
decode_reason_code_and_properties(<<ReasonCode:8, Rest/binary>>,
                                           PacketType, Opts) ->
    {Properties, Rest1} = decode_properties(Rest, PacketType, Opts),
    ensure_end_of_packet(Rest1),
    {ReasonCode, Properties}.

decode_properties(Bin, _PacketType, #{protocol_version := ProtoVersion} = _Opts)
  when ProtoVersion =/= ?PROTOCOL_V5 ->
    {undefined, Bin};
decode_properties(Bin, PacketType, Opts) ->
    decode_properties_v5(Bin, PacketType, Opts).

decode_properties_v5(<<>>, _PacketType, _Opts) ->
    %% FIXME: Invalid property length
    error(malformed_packet);
decode_properties_v5(Bin, PacketType, Opts) ->
    case decode_variable_length(Bin) of
        {0, Rest} ->
            {undefined, Rest};
        {Len, Rest} when Len > erlang:byte_size(Rest) ->
            error(malformed_packet);
        {Len, Rest} ->
            case Rest of
                <<PropertiesBin:Len/binary, Rest1/binary>> ->
                    {decode_property_v5(PropertiesBin, PacketType, #{}, Opts), Rest1};
                _ ->
                    error(malformed_packet)
            end
    end.

decode_property_v5(<<>>, _PacketType, #{} = Props, _Opts)
  when erlang:map_size(Props) =:= 0 ->
    undefined;
decode_property_v5(<<>>, _PacketType, Props, _Opts) -> Props;
decode_property_v5(<<16#01, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(payload_format_indicator, Val, Props), Opts);

decode_property_v5(<<16#02, Val:32/big, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(message_expiry_interval, Val, Props), Opts);

decode_property_v5(<<16#03, StrLen:16, Val:StrLen/binary, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(content_type, Val, Props), Opts);

decode_property_v5(<<16#08, StrLen:16, Val:StrLen/binary, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(response_topic, Val, Props), Opts);

decode_property_v5(<<16#09, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    {Data, Rest1} = decode_binary_data(Rest),
    decode_property_v5(Rest1, PacketType, ?PUT_NEW(correlation_data, Data, Props), Opts);

decode_property_v5(<<16#0B, Rest/binary>>, PacketType, Props, #{from := From} = Opts)
  when PacketType =:= publish; PacketType =:= subscribe ->
    {SubscriptionIdentifier, Rest1} = decode_variable_length(Rest),
    case {SubscriptionIdentifier, PacketType, From} of
        {0, _, _} ->
            error(protocol_error);
        {_, publish, server} ->
            SubIds = maps:get(subscription_identifiers, Props, []),
            NewSubIds = lists:append(SubIds, [SubscriptionIdentifier]),
            Props1 = Props#{subscription_identifiers => NewSubIds},
            decode_property_v5(Rest1, PacketType, Props1, Opts);
        {_, subscribe, client} ->
            Props1 = ?PUT_NEW(subscription_identifier, SubscriptionIdentifier, Props),
            decode_property_v5(Rest1, PacketType, Props1, Opts);
        {_, _, _} ->
            error(malformed_packet)
    end;

decode_property_v5(<<16#11, Val:32/big, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect;
       PacketType =:= connack;
       PacketType =:= disconnect ->
    Props1 = ?PUT_NEW(session_expiry_interval, Val, Props),
    decode_property_v5(Rest, PacketType, Props1, Opts);

decode_property_v5(<<16#12, StrLen:16, Val:StrLen/binary, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    Props1 = ?PUT_NEW(assigned_client_identifier, Val, Props),
    decode_property_v5(Rest, PacketType, Props1, Opts);

decode_property_v5(<<16#13, Val:16, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(server_keep_alive, Val, Props), Opts);

decode_property_v5(<<16#15, StrLen:16, Val:StrLen/binary, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect;
       PacketType =:= connack;
       PacketType =:= auth ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(authentication_method, Val, Props), Opts);

decode_property_v5(<<16#16, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect;
       PacketType =:= connack;
       PacketType =:= auth ->
    {Data, Rest1} = decode_binary_data(Rest),
    decode_property_v5(Rest1, PacketType, ?PUT_NEW(authentication_data, Data, Props), Opts);

decode_property_v5(<<16#17, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect ->
    decode_property_v5(Rest, PacketType,
                       ?PUT_NEW(request_problem_information, decode_bool(Val), Props), Opts);

decode_property_v5(<<16#18, Val:32, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= will_properties ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(will_delay_interval, Val, Props), Opts);

decode_property_v5(<<16#19, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect ->
    decode_property_v5(Rest, PacketType,
                       ?PUT_NEW(request_response_information, decode_bool(Val), Props), Opts);

decode_property_v5(<<16#1A, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    {String, Rest1} = decode_utf8_string(Rest),
    decode_property_v5(Rest1, PacketType, ?PUT_NEW(response_information, String, Props), Opts);

decode_property_v5(<<16#1C, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack;
       PacketType =:= disconnect ->
    {String, Rest1} = decode_utf8_string(Rest),
    decode_property_v5(Rest1, PacketType, ?PUT_NEW(server_reference, String, Props), Opts);

decode_property_v5(<<16#1F, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack;
       PacketType =:= puback;
       PacketType =:= pubrec;
       PacketType =:= pubrel;
       PacketType =:= pubcomp;
       PacketType =:= suback;
       PacketType =:= unsuback;
       PacketType =:= disconnect;
       PacketType =:= auth ->
    {String, Rest1} = decode_utf8_string(Rest),
    decode_property_v5(Rest1, PacketType, ?PUT_NEW(reason_string, String, Props), Opts);

decode_property_v5(<<16#21, 0:16/big, _Rest/binary>>, _PacketType, _Props, _Opts) ->
    error(protocol_error);
decode_property_v5(<<16#21, Val:16/big, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect;
       PacketType =:= connack ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(receive_maximum, Val, Props), Opts);

decode_property_v5(<<16#22, Val:16/big, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect;
       PacketType =:= connack ->
    decode_property_v5(Rest, PacketType, ?PUT_NEW(topic_alias_maximum, Val, Props), Opts);

decode_property_v5(<<16#23, Val:16/big, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= publish ->
    decode_property_v5(Rest, PacketType, Props#{topic_alias => Val}, Opts);

decode_property_v5(<<16#24, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    QoS = decode_qos(Val),
    decode_property_v5(Rest, PacketType, Props#{maximum_qos => QoS}, Opts);

decode_property_v5(<<16#25, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    Props1 = ?PUT_NEW(retain_available, decode_bool(Val), Props),
    decode_property_v5(Rest, PacketType, Props1, Opts);

decode_property_v5(<<16#26, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect;
       PacketType =:= connack;
       PacketType =:= publish;
       PacketType =:= will_properties;
       PacketType =:= puback;
       PacketType =:= pubrec;
       PacketType =:= pubrel;
       PacketType =:= pubcomp;
       PacketType =:= subscribe;
       PacketType =:= suback;
       PacketType =:= unsubscribe;
       PacketType =:= unsuback;
       PacketType =:= disconnect;
       PacketType =:= auth ->
    {StringPair, Rest1} = decode_utf8_string_pair(Rest),
    Pairs = maps:get(user_properties, Props, []),
    Props1 = Props#{user_properties => Pairs ++ [StringPair]},
    decode_property_v5(Rest1, PacketType, Props1, Opts);

decode_property_v5(<<16#27, 0:32, _Rest/binary>>, _PacketType, _Props, _Opts) ->
    error(protocol_error);
decode_property_v5(<<16#27, Val:32, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connect;
       PacketType =:= connack ->
    Props1 = ?PUT_NEW(maximum_packet_size, Val, Props),
    decode_property_v5(Rest, PacketType, Props1, Opts);

decode_property_v5(<<16#28, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    Props1 = ?PUT_NEW(wildcard_subscription_available, decode_bool(Val), Props),
    decode_property_v5(Rest, PacketType, Props1, Opts);

decode_property_v5(<<16#29, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    Props1 = ?PUT_NEW(subscription_identifier_available, decode_bool(Val), Props),
    decode_property_v5(Rest, PacketType, Props1, Opts);

decode_property_v5(<<16#2A, Val, Rest/binary>>, PacketType, Props, Opts)
  when PacketType =:= connack ->
    Props1 = ?PUT_NEW(shared_subscription_available, decode_bool(Val), Props),
    decode_property_v5(Rest, PacketType, Props1, Opts);

decode_property_v5(<<Property:8, _Rest/binary>>, _PacketType, _Props, _Opts) ->
    error({unknown_property, Property}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% End of decoding properties
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
