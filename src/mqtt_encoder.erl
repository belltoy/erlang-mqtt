-module(mqtt_encoder).

-include("mqtt_packet.hrl").

-export([encode/2]).

-spec encode(mqtt_codec:packet(), mqtt_codec:opts()) -> iodata().
encode(#mqtt_connect{
        protocol_name = ProtocolName,
        protocol_version = ProtocolVersion,
        last_will = LastWill,
        clean_session = CleanSession,
        keep_alive = KeepAlive,
        client_id = ClientId,
        username = Username,
        password = Password,
        properties = Props}, Opts) ->
    Remaining = [
        %% Variable header
        encode_utf8_string(ProtocolName),
        <<ProtocolVersion:8>>,
        <<
          (encode_bool(Username =/= undefined)):1,
          (encode_bool(Password =/= undefined)):1,
          (encode_last_will_flags(LastWill)):4,
          (encode_bool(CleanSession)):1,
          0:1 % reserved
        >>,
        <<KeepAlive:16>>,
        encode_properties(Props, connect, Opts),
        %% Paylaod
        encode_utf8_string(ClientId),
        encode_last_will(LastWill, Opts),
        encode_optional_string(Username),
        encode_optional_string(Password)
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?CONNECT:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_connack{session_present = SessionPresent,
                     reason_code = ReasonCode,
                     properties = Props}, Opts) ->
    Remaining = [
        %% Variable header
        <<0:7, (encode_bool(SessionPresent)):1>>,
        <<ReasonCode:8>>,
        encode_properties(Props, connack, Opts)
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?CONNACK:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_publish{
          topic = Topic,
          message = Message,
          dup = Dup,
          qos = QoS,
          retain = Retain,
          packet_id = PacketId,
          properties = Props}, Opts) ->
    Remaining = [
        %% Variable header
        encode_utf8_string(Topic),
        case QoS of
            0 -> <<>>;
            _ when QoS >= 1 ->
                %% TODO: Validate packet id is set
                ok = check_packet_id(PacketId),
                <<PacketId:16>>
        end,
        encode_properties(Props, publish, Opts),
        %% Payload
        Message
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?PUBLISH:4, (encode_bool(Dup)):1, (encode_qos(QoS)):2, (encode_bool(Retain)):1>>, RemainingLen, Remaining];

encode(#mqtt_puback{packet_id = PacketId, properties = Props}, Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [<<PacketId:16>>, encode_properties(Props, puback, Opts)],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?PUBACK:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_pubrec{packet_id = PacketId, properties = Props}, Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [<<PacketId:16>>, encode_properties(Props, pubrec, Opts)],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?PUBREC:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_pubrel{packet_id = PacketId, properties = Props}, Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [<<PacketId:16>>, encode_properties(Props, pubrel, Opts)],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?PUBREL:4, 2:4>>, RemainingLen, Remaining];

encode(#mqtt_pubcomp{packet_id = PacketId, properties = Props}, Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [<<PacketId:16>>, encode_properties(Props, pubcomp, Opts)],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?PUBCOMP:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_subscribe{packet_id = PacketId, topic_filters = TopicFilters, properties = Props}, Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [
        <<PacketId:16>>,
        encode_properties(Props, subscribe, Opts),
        encode_topic_filters(TopicFilters, Opts)
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?SUBSCRIBE:4, 2#0010:4>>, RemainingLen, Remaining];

encode(#mqtt_suback{packet_id = PacketId, reason_codes = ReturnCodes, properties = Props}, Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [
        <<PacketId:16>>,
        encode_properties(Props, suback, Opts),
        encode_reason_codes(ReturnCodes, Opts)
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?SUBACK:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_unsubscribe{packet_id = PacketId, topic_filters = TopicFilters, properties = Props}, Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [
        <<PacketId:16>>,
        encode_properties(Props, unsubscribe, Opts),
        encode_topic_filters(TopicFilters, Opts)
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?UNSUBSCRIBE:4, 2#0010:4>>, RemainingLen, Remaining];

encode(#mqtt_unsuback{packet_id = PacketId, reason_codes = ReasonCodes, properties = Props},
       #{protocol_version := ProtoVersion} = Opts) ->
    ok = check_packet_id(PacketId),
    Remaining = [
        <<PacketId:16>>,
        case ProtoVersion of
            ?PROTOCOL_V5 ->
                [encode_properties(Props, unsuback, Opts), encode_reason_codes(ReasonCodes, Opts)];
            _ -> []
        end
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?UNSUBACK:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_pingreq{}, _Opts) ->
    <<?PINGREQ:4, 0:4, 0:8>>;
encode(#mqtt_pingresp{}, _Opts) ->
    <<?PINGRESP:4, 0:4, 0:8>>;

encode(#mqtt_disconnect{reason_code = ReasonCode, properties = Props},
       #{protocol_version := ProtoVersion} = Opts) ->
    Remaining = [
        case ProtoVersion of
            ?PROTOCOL_V5 ->
                [<<ReasonCode:8>>, encode_properties(Props, disconnect, Opts)];
            _ -> []
        end
    ],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?DISCONNECT:4, 0:4>>, RemainingLen, Remaining];

encode(#mqtt_auth{reason_code = ReasonCode, properties = Props},
       #{protocol_version := ?PROTOCOL_V5} = Opts) ->
    Remaining = [<<ReasonCode:8>>, encode_properties(Props, auth, Opts)],
    RemainingLen = encode_variable_byte_integer(iolist_size(Remaining)),
    [<<?AUTH:4, 0:4>>, RemainingLen, Remaining].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Private functions for encoding
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

encode_bool(true) -> 1;
encode_bool(false) -> 0.

encode_qos(0) -> 0;
encode_qos(1) -> 1;
encode_qos(2) -> 2;
encode_qos(_) -> error(invalid_qos).

encode_variable_byte_integer(L) when L >= 16#FFF_FFFF -> error(too_large_payload);
encode_variable_byte_integer(L) when L < 16#80 -> <<0:1, L:7>>;
encode_variable_byte_integer(L) -> <<1:1, (L rem 16#80):7, (encode_variable_byte_integer(L div 16#80))/binary>>.

%% Validate UTF-8
encode_utf8_string(Str) ->
    case unicode:characters_to_binary(Str) of
        Bin when is_binary(Bin) ->
            Len = iolist_size(Bin),
            case {Len > 16#FFFF, mqtt_utf8:validate_utf8_string(Bin)} of
                {true, _} ->
                    error(string_too_long);
                {_, false} ->
                    error(invalid_utf8_string);
                {false, true} ->
                    [<<Len:16>>, Str]
            end;
        _ ->
            error(invalid_utf8_string)
    end.

%% @doc Encode binary data in MQTT data representation
encode_binary(Data) ->
    Len = iolist_size(Data),
    case Len > 16#FFFF of
        true ->
            {error, binary_too_long};
        false ->
            [<<Len:16>>, Data]
    end.

encode_optional_string(undefined) ->
    <<>>;
encode_optional_string(Str) ->
    encode_utf8_string(Str).

encode_last_will_flags(undefined) ->
    0;
encode_last_will_flags(#mqtt_last_will{qos = QoS, retain = Retain}) ->
    1 bor (encode_qos(QoS) bsl 1) bor (encode_bool(Retain) bsl 3).

encode_last_will(undefined, _Opts) ->
    <<>>;
encode_last_will(#mqtt_last_will{topic = Topic, message = Message, properties = Props}, Opts) ->
    [
        encode_properties(Props, will_properties, Opts),
        encode_utf8_string(Topic),
        encode_binary(Message)
    ].

-spec encode_topic_filters([TopicFilter], map()) -> iolist()
     when TopicFilter :: mqtt_codec:topic() | #mqtt_subscription{}.
encode_topic_filters(TopicFilters, Opts) ->
    lists:map(fun(T) -> encode_subscription(T, Opts) end, TopicFilters).

-spec encode_subscription(TopicFilter, Opts :: map()) -> iolist()
     when TopicFilter :: mqtt_codec:topic() | #mqtt_subscription{}.
encode_subscription(#mqtt_subscription{
                        topic_filter = TopicFilter,
                        max_qos = QoS,
                        no_local = NL,
                        retain_as_published = Rap,
                        retain_handling = Rh
                    }, #{protocol_version := ProtoVersion} = _Opts) ->
    case ProtoVersion of
        ?PROTOCOL_V5 ->
            SubOpt = <<0:2, (encode_retain_handling(Rh)):2, (encode_bool(Rap)):1,
                       (encode_bool(NL)):1, (encode_qos(QoS)):2>>,
            [encode_utf8_string(TopicFilter), SubOpt];
        _ ->
            SubOpt = <<0:6, (encode_qos(QoS)):2>>,
            [encode_utf8_string(TopicFilter), SubOpt]
    end;
%% For UNSUBCRIBE
encode_subscription(TopicFilter, _Opts) when is_binary(TopicFilter) ->
    encode_utf8_string(TopicFilter).

encode_reason_codes(ReasonCodes, _Opts) ->
    lists:map(fun(ReasonCode) -> <<ReasonCode:8>> end, ReasonCodes).

encode_retain_handling(send_at_subscribe) -> 0;
encode_retain_handling(send_if_not_exist) -> 1;
encode_retain_handling(do_not_send) -> 2.

check_packet_id(0) -> error(zero_packet_id);
check_packet_id(PacketId) when PacketId > 16#FFFF -> error(packet_id_too_large);
check_packet_id(_PacketId) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Private functions for encoding properties
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

encode_properties(Props, PacketType, #{protocol_version := ?PROTOCOL_V5} = Opts) ->
    encode_properties_v5(Props, PacketType, Opts);
encode_properties(_Properties, _PacketType, _Opts) ->
    [].

encode_properties_v5(undefined, _PacketType, _Opts) ->
    [encode_variable_byte_integer(0), <<>>];
encode_properties_v5(Props, PacketType, Opts) ->
    encode_properties_v5(maps:to_list(Props), PacketType, Opts, []).

encode_properties_v5([{PropId, Value} | Rest], PacketType, Opts, Acc) ->
    encode_properties_v5(Rest, PacketType, Opts,
                         [encode_property(PropId, Value, PacketType, Opts) | Acc]);
encode_properties_v5([], _PacketType, _Opts, Acc) ->
    [encode_variable_byte_integer(iolist_size(Acc)), Acc].

encode_property(payload_format_indicator, Value, PacketType, _Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    <<16#01, Value:8>>;

encode_property(message_expiry_interval, Value, PacketType, _Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    <<16#02, Value:32>>;

encode_property(content_type, Value, PacketType, _Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    [<<16#03>>, encode_utf8_string(Value)];

encode_property(response_topic, Value, PacketType, _Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    [<<16#08>>, encode_utf8_string(Value)];

encode_property(correlation_data, Value, PacketType, _Opts)
  when PacketType =:= publish; PacketType =:= will_properties ->
    [<<16#09>>, encode_binary(Value)];

%% For subscribe properties
encode_property(subscription_identifier, Value, PacketType, _Opts)
  when PacketType =:= subscribe ->
    [<<16#0B>>, encode_variable_byte_integer(Value)];

%% For publish properties
encode_property(subscription_identifiers, Value, PacketType, _Opts)
  when PacketType =:= publish ->
    [[<<16#0B>>, encode_variable_byte_integer(SubId)] || SubId <- Value];

encode_property(session_expiry_interval, Value, PacketType, _Opts)
  when PacketType =:= connect;
       PacketType =:= connack;
       PacketType =:= disconnect ->
    <<16#11, Value:32>>;

encode_property(assigned_client_identifier, Value, PacketType, _Opts)
  when PacketType =:= connack ->
    [<<16#12>>, encode_utf8_string(Value)];

encode_property(server_keep_alive, Value, PacketType, _Opts)
  when PacketType =:= connack ->
    <<16#13, Value:16>>;

encode_property(authentication_method, Value, PacketType, _Opts)
  when PacketType =:= connect;
       PacketType =:= connack;
       PacketType =:= auth ->
    [<<16#15>>, encode_utf8_string(Value)];

encode_property(authentication_data, Value, PacketType, _Opts)
  when PacketType =:= connect;
       PacketType =:= connack;
       PacketType =:= auth ->
    [<<16#16>>, encode_binary(Value)];

encode_property(request_problem_information, Value, PacketType, _Opts)
  when PacketType =:= connect ->
    <<16#17, (encode_bool(Value)):8>>;

encode_property(will_delay_interval, Value, PacketType, _Opts)
  when PacketType =:= will_properties ->
    <<16#18, Value:32>>;

encode_property(request_response_information, Value, PacketType, _Opts)
  when PacketType =:= connect ->
    <<16#19, (encode_bool(Value)):8>>;

encode_property(response_information, Value, PacketType, _Opts)
  when PacketType =:= connack ->
    [<<16#1A>>, encode_utf8_string(Value)];

encode_property(server_reference, Value, PacketType, _Opts)
  when PacketType =:= connack;
       PacketType =:= disconnect ->
    [<<16#1C>>, encode_utf8_string(Value)];

encode_property(reason_string, Value, PacketType, _Opts)
  when PacketType =:= connack;
       PacketType =:= puback;
       PacketType =:= pubrec;
       PacketType =:= pubrel;
       PacketType =:= pubcomp;
       PacketType =:= suback;
       PacketType =:= unsuback;
       PacketType =:= disconnect;
       PacketType =:= auth ->
    [<<16#1F>>, encode_utf8_string(Value)];
encode_property(receive_maximum, Value, PacketType, _Opts)
  when PacketType =:= connect;
       PacketType =:= connack ->
    case Value of
        N when N > 0, N =< 16#FFFF ->
            <<16#21, Value:16>>;
        _ -> error({invalid_property_value, receive_maximum, Value})
    end;

encode_property(topic_alias_maximum, Value, PacketType, _Opts)
  when PacketType =:= connect;
       PacketType =:= connack ->
    <<16#22, Value:16>>;

encode_property(topic_alias, Value, PacketType, _Opts) when PacketType =:= publish ->
    case Value of
        0 ->
            error({invalid_property_value, topic_alias, Value});
        _ ->
            <<16#23, Value:16>>
    end;

encode_property(maximum_qos, Value, PacketType, _Opts) when PacketType =:= connack ->
    case Value of
        N when N =:= 0; N =:= 1; N =:= 2 ->
            <<16#24, N:8>>;
        _ -> error({invalid_property_value, maximum_qos, Value})
    end;

encode_property(retain_available, Value, PacketType, _Opts) when PacketType =:= connack ->
    <<16#25, (encode_bool(Value)):8>>;

encode_property(user_property, {Key, Value}, PacketType, _Opts)
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
    [<<16#26>>, encode_utf8_string(Key), encode_utf8_string(Value)];

encode_property(maximum_packet_size, Value, PacketType, _Opts)
  when PacketType =:= connect;
       PacketType =:= connack ->
    case Value of
        N when N > 0, N =< 16#FFFF_FFFF ->
             <<16#27, Value:32>>;
        _ ->
            error({invalid_property_value, maximum_packet_size, Value})
    end;

encode_property(wildcard_subscription_available, Value, PacketType, _Opts)
  when PacketType =:= connack ->
    <<16#28, (encode_bool(Value)):8>>;

encode_property(subscription_identifier_available, Value, PacketType, _Opts)
  when PacketType =:= connack ->
    <<16#29, (encode_bool(Value)):8>>;

encode_property(shared_subscription_available, Value, PacketType, _Opts)
  when PacketType =:= connack ->
    <<16#2A, (encode_bool(Value)):8>>;

encode_property(_, _, _PacketType, _Opts) ->
    error(unknown_property).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% End of encoding properties
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
