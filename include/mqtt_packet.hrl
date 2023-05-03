%%--------------------------------------------------------------------
%% MQTT Control Packet Types
%%--------------------------------------------------------------------

-define(MAX_PACKET_SIZE, 16#fffffff).

-define(RESERVED,     0). %% Reserved
-define(CONNECT,      1). %% Client request to connect to Server
-define(CONNACK,      2). %% Server to Client: Connect acknowledgment
-define(PUBLISH,      3). %% Publish message
-define(PUBACK,       4). %% Publish acknowledgment
-define(PUBREC,       5). %% Publish received (assured delivery part 1)
-define(PUBREL,       6). %% Publish release (assured delivery part 2)
-define(PUBCOMP,      7). %% Publish complete (assured delivery part 3)
-define(SUBSCRIBE,    8). %% Client subscribe request
-define(SUBACK,       9). %% Server Subscribe acknowledgment
-define(UNSUBSCRIBE, 10). %% Unsubscribe request
-define(UNSUBACK,    11). %% Unsubscribe acknowledgment
-define(PINGREQ,     12). %% PING request
-define(PINGRESP,    13). %% PING response
-define(DISCONNECT,  14). %% Client or Server is disconnecting
-define(AUTH,        15). %% Authentication exchange MQTT v5

-define(PROTOCOL_V3, 3).
-define(PROTOCOL_V4, 4).
-define(PROTOCOL_V5, 5).

-define(PROTOCOL_NAME_V3, <<"MQIsdp">>).
-define(PROTOCOL_NAME_V4, <<"MQTT">>).
-define(PROTOCOL_NAME_V5, <<"MQTT">>).

%% Reason codes for MQTT v3 and v4
-define(REASON_CODE_V4_UNSUPPORTED_PROTOCOL_VERSION, 1).
-define(REASON_CODE_V4_CLIENT_IDENTIFIER_NOT_VALID,  2).
-define(REASON_CODE_V4_SERVER_UNAVAILABLE,           3).
-define(REASON_CODE_V4_BAD_USER_NAME_OR_PASSWORD,    4).
-define(REASON_CODE_V4_NOT_AUTHORIZED,               5).

%% Reason codes for MQTT v5
-define(REASON_CODE_SUCCESS,                                0).
-define(REASON_CODE_NORMAL_DISCONNECTION,                   0).
-define(REASON_CODE_GRANTED_QOS_0,                          0).
-define(REASON_CODE_GRANTED_QOS_1,                          1).
-define(REASON_CODE_GRANTED_QOS_2,                          2).
-define(REASON_CODE_DISCONNECT_WITH_WILL_MESSAGE,           4).
-define(REASON_CODE_NO_MATCHING_SUBSCRIBERS,                16).
-define(REASON_CODE_NO_SUBSCRIPTION_EXISTED,                17).
-define(REASON_CODE_CONTINUE_AUTHENTICATION,                24).
-define(REASON_CODE_RE_AUTHENTICATE,                        25).
-define(REASON_CODE_UNSPECIFIED_ERROR,                      128).
-define(REASON_CODE_MALFORMED_PACKET,                       129).
-define(REASON_CODE_PROTOCOL_ERROR,                         130).
-define(REASON_CODE_IMPLEMENTATION_SPECIFIC_ERROR,          131).
-define(REASON_CODE_UNSUPPORTED_PROTOCOL_VERSION,           132).
-define(REASON_CODE_CLIENT_IDENTIFIER_NOT_VALID,            133).
-define(REASON_CODE_BAD_USER_NAME_OR_PASSWORD,              134).
-define(REASON_CODE_NOT_AUTHORIZED,                         135).
-define(REASON_CODE_SERVER_UNAVAILABLE,                     136).
-define(REASON_CODE_SERVER_BUSY,                            137).
-define(REASON_CODE_BANNED,                                 138).
-define(REASON_CODE_SERVER_SHUTTING_DOWN,                   139).
-define(REASON_CODE_BAD_AUTHENTICATION_METHOD,              140).
-define(REASON_CODE_KEEP_ALIVE_TIMEOUT,                     141).
-define(REASON_CODE_SESSION_TAKEN_OVER,                     142).
-define(REASON_CODE_TOPIC_FILTER_INVALID,                   143).
-define(REASON_CODE_TOPIC_NAME_INVALID,                     144).
-define(REASON_CODE_PACKET_IDENTIFIER_IN_USE,               145).
-define(REASON_CODE_PACKET_IDENTIFIER_NOT_FOUND,            146).
-define(REASON_CODE_RECEIVE_MAXIMUM_EXCEEDED,               147).
-define(REASON_CODE_TOPIC_ALIAS_INVALID,                    148).
-define(REASON_CODE_PACKET_TOO_LARGE,                       149).
-define(REASON_CODE_MESSAGE_RATE_TOO_HIGH,                  150).
-define(REASON_CODE_QUOTA_EXCEEDED,                         151).
-define(REASON_CODE_ADMINISTRATIVE_ACTION,                  152).
-define(REASON_CODE_PAYLOAD_FORMAT_INVALID,                 153).
-define(REASON_CODE_RETAIN_NOT_SUPPORTED,                   154).
-define(REASON_CODE_QOS_NOT_SUPPORTED,                      155).
-define(REASON_CODE_USE_ANOTHER_SERVER,                     156).
-define(REASON_CODE_SERVER_MOVED,                           157).
-define(REASON_CODE_SHARED_SUBSCRIPTIONS_NOT_SUPPORTED,     158).
-define(REASON_CODE_CONNECTION_RATE_EXCEEDED,               159).
-define(REASON_CODE_MAXIMUM_CONNECT_TIME,                   160).
-define(REASON_CODE_SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED, 161).
-define(REASON_CODE_WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED,   162).

-record(mqtt_last_will, {
    topic :: mqtt_codec:topic(),
    message :: binary(),
    qos :: mqtt_codec:qos(),
    retain :: boolean(),
    properties :: undefined | mqtt_last_will_properties()
}).

-record(mqtt_connect, {
    protocol_name = ?PROTOCOL_NAME_V4 :: unicode:unicode_binary(),
    protocol_version :: 3 | 4 | 5,
    last_will        :: undefined | #mqtt_last_will{},
    clean_session    :: boolean(),
    keep_alive       :: 0..16#FFFF,
    client_id        :: unicode:unicode_binary(),
    username         :: undefined | unicode:unicode_binary(),
    password         :: undefined | binary(),
    properties       :: undefined | mqtt_connect_properties()
}).

-record(mqtt_connack, {
    session_present :: boolean(),
    % return_code :: 0..255,
    %% Only for MQTT v5
    reason_code :: ?REASON_CODE_SUCCESS                                   %% 0, 0x00

                 | ?REASON_CODE_V4_UNSUPPORTED_PROTOCOL_VERSION           %% MQTT v3, v4 only
                 | ?REASON_CODE_V4_CLIENT_IDENTIFIER_NOT_VALID            %% MQTT v3, v4 only
                 | ?REASON_CODE_V4_SERVER_UNAVAILABLE                     %% MQTT v3, v4 only
                 | ?REASON_CODE_V4_BAD_USER_NAME_OR_PASSWORD              %% MQTT v3, v4 only
                 | ?REASON_CODE_V4_NOT_AUTHORIZED                         %% MQTT v3, v4 only

                 | ?REASON_CODE_UNSPECIFIED_ERROR                         %% MQTT v5 only, 128, 0x80
                 | ?REASON_CODE_MALFORMED_PACKET                          %% MQTT v5 only, 129, 0x81
                 | ?REASON_CODE_PROTOCOL_ERROR                            %% MQTT v5 only, 130, 0x82
                 | ?REASON_CODE_IMPLEMENTATION_SPECIFIC_ERROR             %% MQTT v5 only, 131, 0x83
                 | ?REASON_CODE_UNSUPPORTED_PROTOCOL_VERSION              %% MQTT v5 only, 132, 0x84
                 | ?REASON_CODE_CLIENT_IDENTIFIER_NOT_VALID               %% MQTT v5 only, 133, 0x85
                 | ?REASON_CODE_BAD_USER_NAME_OR_PASSWORD                 %% MQTT v5 only, 134, 0x86
                 | ?REASON_CODE_NOT_AUTHORIZED                            %% MQTT v5 only, 135, 0x87
                 | ?REASON_CODE_SERVER_UNAVAILABLE                        %% MQTT v5 only, 136, 0x88
                 | ?REASON_CODE_SERVER_BUSY                               %% MQTT v5 only, 137, 0x89
                 | ?REASON_CODE_BANNED                                    %% MQTT v5 only, 138, 0x8A
                 | ?REASON_CODE_BAD_AUTHENTICATION_METHOD                 %% MQTT v5 only, 140, 0x8C
                 | ?REASON_CODE_TOPIC_NAME_INVALID                        %% MQTT v5 only, 144, 0x90
                 | ?REASON_CODE_PACKET_TOO_LARGE                          %% MQTT v5 only, 149, 0x95
                 | ?REASON_CODE_QUOTA_EXCEEDED                            %% MQTT v5 only, 151, 0x97
                 | ?REASON_CODE_PAYLOAD_FORMAT_INVALID                    %% MQTT v5 only, 153, 0x99
                 | ?REASON_CODE_RETAIN_NOT_SUPPORTED                      %% MQTT v5 only, 154, 0x9A
                 | ?REASON_CODE_QOS_NOT_SUPPORTED                         %% MQTT v5 only, 155, 0x9B
                 | ?REASON_CODE_USE_ANOTHER_SERVER                        %% MQTT v5 only, 156, 0x9C
                 | ?REASON_CODE_SERVER_MOVED                              %% MQTT v5 only, 157, 0x9D
                 | ?REASON_CODE_CONNECTION_RATE_EXCEEDED,                 %% MQTT v5 only, 159, 0x9F
    %% Only for MQTT v5
    properties :: undefined | mqtt_connack_properties()
}).

-define(RETAIN_HANDLING_SEND_AT_SUBSCRIBE_TIME, 0).
-define(RETAIN_HANDLING_SEND_IF_SUBSCRIPTION_DOES_NOT_EXIST, 1).
-define(RETAIN_HANDLING_DO_NOT_SEND, 2).

-record(mqtt_publish, {
    topic :: mqtt_codec:topic(),
    message :: binary(),
    dup :: boolean(),
    qos :: mqtt_codec:qos(),
    retain :: boolean(),
    packet_id :: undefined | mqtt_codec:packet_id(),
    properties :: undefined | mqtt_publish_properties()
}).

-record(mqtt_puback, {
    packet_id :: mqtt_codec:packet_id(),

    %% Only for MQTT v5
    reason_code :: ?REASON_CODE_SUCCESS                                  %% 0,   0x00
                 | ?REASON_CODE_NO_MATCHING_SUBSCRIBERS                  %% 16,  0x10
                 | ?REASON_CODE_UNSPECIFIED_ERROR                        %% 128, 0x80
                 | ?REASON_CODE_IMPLEMENTATION_SPECIFIC_ERROR            %% 131, 0x83
                 | ?REASON_CODE_NOT_AUTHORIZED                           %% 135, 0x87
                 | ?REASON_CODE_TOPIC_NAME_INVALID                       %% 144, 0x90
                 | ?REASON_CODE_PACKET_IDENTIFIER_IN_USE                 %% 145, 0x91
                 | ?REASON_CODE_QUOTA_EXCEEDED                           %% 151, 0x97
                 | ?REASON_CODE_PAYLOAD_FORMAT_INVALID,                  %% 153, 0x99
    %% Only for MQTT v5
    properties :: undefined | mqtt_puback_properties()
}).

-record(mqtt_pubrec, {
    packet_id :: mqtt_codec:packet_id(),
    %% Only for MQTT v5
    reason_code :: undefined
                 | ?REASON_CODE_SUCCESS                                  %% 0,   0x00
                 | ?REASON_CODE_NO_MATCHING_SUBSCRIBERS                  %% 16,  0x10
                 | ?REASON_CODE_UNSPECIFIED_ERROR                        %% 128, 0x80
                 | ?REASON_CODE_IMPLEMENTATION_SPECIFIC_ERROR            %% 131, 0x83
                 | ?REASON_CODE_NOT_AUTHORIZED                           %% 135, 0x87
                 | ?REASON_CODE_TOPIC_NAME_INVALID                       %% 144, 0x90
                 | ?REASON_CODE_PACKET_IDENTIFIER_IN_USE                 %% 145, 0x91
                 | ?REASON_CODE_QUOTA_EXCEEDED                           %% 151, 0x97
                 | ?REASON_CODE_PAYLOAD_FORMAT_INVALID,                  %% 153, 0x99
    %% Only for MQTT v5
    properties :: undefined | mqtt_pubrec_properties()
}).

-record(mqtt_pubrel, {
    packet_id :: mqtt_codec:packet_id(),
    %% Only for MQTT v5
    reason_code :: undefined
                 | ?REASON_CODE_SUCCESS                                  %% 0,   0x00
                 | ?REASON_CODE_PACKET_IDENTIFIER_NOT_FOUND,             %% 146, 0x92
    %% Only for MQTT v5
    properties :: undefined | mqtt_pubrel_properties()
}).

-record(mqtt_pubcomp, {
    packet_id :: mqtt_codec:packet_id(),
    %% Only for MQTT v5
    reason_code :: undefined
                 | ?REASON_CODE_SUCCESS                                 %% 0,   0x00
                 | ?REASON_CODE_PACKET_IDENTIFIER_NOT_FOUND,            %% 146, 0x92
    %% Only for MQTT v5
    properties :: undefined | mqtt_pubcomp_properties()
}).

-record(mqtt_subscription, {
    topic_filter :: mqtt_codec:topic(),

    %% Subscription options
    max_qos :: mqtt_codec:qos(),
    %% Only for MQTT v5
    no_local = false :: boolean(),
    retain_as_published = false :: boolean(),
    retain_handling = send_at_subscribe :: send_at_subscribe           %% Send at subscribe time, 0
                                         | send_if_not_exist           %% Send if subscription does not exist, 1
                                         | do_not_send                 %% Do not send, 2
}).

-record(mqtt_subscribe, {
    packet_id :: mqtt_codec:packet_id(),
    topic_filters :: [#mqtt_subscription{}],
    %% Only for MQTT v5
    properties :: undefined | mqtt_subscribe_properties()
}).

-record(mqtt_suback, {
    packet_id :: mqtt_codec:packet_id(),
    reason_codes :: [ ?REASON_CODE_GRANTED_QOS_0                            %% 0,   0x00
                    | ?REASON_CODE_GRANTED_QOS_1                            %% 1,   0x01
                    | ?REASON_CODE_GRANTED_QOS_2                            %% 2,   0x02
                    | ?REASON_CODE_UNSPECIFIED_ERROR                        %% 128, 0x80

                    | ?REASON_CODE_IMPLEMENTATION_SPECIFIC_ERROR            %% Only for MQTT v5, 131, 0x83
                    | ?REASON_CODE_NOT_AUTHORIZED                           %% Only for MQTT v5, 135, 0x87
                    | ?REASON_CODE_TOPIC_FILTER_INVALID                     %% Only for MQTT v5, 143, 0x8F
                    | ?REASON_CODE_PACKET_IDENTIFIER_IN_USE                 %% Only for MQTT v5, 145, 0x91
                    | ?REASON_CODE_QUOTA_EXCEEDED                           %% Only for MQTT v5, 151, 0x97
                    | ?REASON_CODE_SHARED_SUBSCRIPTIONS_NOT_SUPPORTED       %% Only for MQTT v5, 158, 0x9E
                    | ?REASON_CODE_SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED   %% Only for MQTT v5, 161, 0xA1
                    | ?REASON_CODE_WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED     %% Only for MQTT v5, 162, 0xA2
                    ],
    %% Only for MQTT v5
    properties :: undefined | mqtt_suback_properties()
}).

-record(mqtt_unsubscribe, {
    packet_id :: mqtt_codec:packet_id(),
    topic_filters :: [mqtt_codec:topic()],
    %% Only for MQTT v5
    properties :: undefined | mqtt_unsubscribe_properties()
}).

-record(mqtt_unsuback, {
    packet_id :: mqtt_codec:packet_id(),
    %% Only for MQTT v5
    reason_codes :: [ ?REASON_CODE_SUCCESS                                  %% 0,   0x00
                    | ?REASON_CODE_NO_SUBSCRIPTION_EXISTED                  %% 17,  0x11
                    | ?REASON_CODE_UNSPECIFIED_ERROR                        %% 128, 0x80
                    | ?REASON_CODE_IMPLEMENTATION_SPECIFIC_ERROR            %% 131, 0x83
                    | ?REASON_CODE_NOT_AUTHORIZED                           %% 135, 0x87
                    | ?REASON_CODE_TOPIC_FILTER_INVALID                     %% 143, 0x8F
                    | ?REASON_CODE_PACKET_IDENTIFIER_IN_USE                 %% 145, 0x91
                    ],
    %% Only for MQTT v5
    properties :: undefined | mqtt_unsuback_properties()
}).

-record(mqtt_pingreq, {}).

-record(mqtt_pingresp, {}).

-record(mqtt_disconnect, {
    %% Only for MQTT v5
    reason_code :: ?REASON_CODE_NORMAL_DISCONNECTION                        %% 0,   0x00
                 | ?REASON_CODE_DISCONNECT_WITH_WILL_MESSAGE                %% 4,   0x04
                 | ?REASON_CODE_UNSPECIFIED_ERROR                           %% 128, 0x80
                 | ?REASON_CODE_MALFORMED_PACKET                            %% 129, 0x81
                 | ?REASON_CODE_PROTOCOL_ERROR                              %% 130, 0x82
                 | ?REASON_CODE_IMPLEMENTATION_SPECIFIC_ERROR               %% 131, 0x83
                 | ?REASON_CODE_NOT_AUTHORIZED                              %% 135, 0x87
                 | ?REASON_CODE_SERVER_BUSY                                 %% 137, 0x89
                 | ?REASON_CODE_SERVER_SHUTTING_DOWN                        %% 139, 0x8B
                 | ?REASON_CODE_KEEP_ALIVE_TIMEOUT                          %% 141, 0x8D
                 | ?REASON_CODE_SESSION_TAKEN_OVER                          %% 142, 0x8E
                 | ?REASON_CODE_TOPIC_FILTER_INVALID                        %% 143, 0x8F
                 | ?REASON_CODE_TOPIC_NAME_INVALID                          %% 144, 0x90
                 | ?REASON_CODE_RECEIVE_MAXIMUM_EXCEEDED                    %% 147, 0x93
                 | ?REASON_CODE_TOPIC_ALIAS_INVALID                         %% 148, 0x94
                 | ?REASON_CODE_PACKET_TOO_LARGE                            %% 149, 0x95
                 | ?REASON_CODE_MESSAGE_RATE_TOO_HIGH                       %% 150, 0x96
                 | ?REASON_CODE_QUOTA_EXCEEDED                              %% 151, 0x97
                 | ?REASON_CODE_ADMINISTRATIVE_ACTION                       %% 152, 0x98
                 | ?REASON_CODE_PAYLOAD_FORMAT_INVALID                      %% 153, 0x99
                 | ?REASON_CODE_RETAIN_NOT_SUPPORTED                        %% 154, 0x9A
                 | ?REASON_CODE_QOS_NOT_SUPPORTED                           %% 155, 0x9B
                 | ?REASON_CODE_USE_ANOTHER_SERVER                          %% 156, 0x9C
                 | ?REASON_CODE_SERVER_MOVED                                %% 157, 0x9D
                 | ?REASON_CODE_SHARED_SUBSCRIPTIONS_NOT_SUPPORTED          %% 158, 0x9E
                 | ?REASON_CODE_CONNECTION_RATE_EXCEEDED                    %% 159, 0x9F
                 | ?REASON_CODE_MAXIMUM_CONNECT_TIME                        %% 160, 0xA0
                 | ?REASON_CODE_SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED      %% 161, 0xA1
                 | ?REASON_CODE_WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED,       %% 162, 0xA2
    %% Only for MQTT v5
    properties :: undefined | mqtt_disconnect_properties()
}).

%% Only for MQTT v5
-record(mqtt_auth, {
    reason_code :: ?REASON_CODE_SUCCESS                                     %% 0,   0x00
                 | ?REASON_CODE_CONTINUE_AUTHENTICATION                     %% 24,  0x18
                 | ?REASON_CODE_RE_AUTHENTICATE,                            %% 25,  0x19
    properties :: undefined | mqtt_auth_properties()
}).

-type subscription_identifier() :: 1..16#FFFF.

-type utf8_string_pairs() :: [{unicode:unicode_binary(), unicode:unicode_binary()}].

-type mqtt_connect_properties() :: #{
    session_expiry_interval      => 0..16#FFFF_FFFF,
    receive_maximum              => 1..16#FFFF,
    maximum_packet_size          => 1..16#FFFF_FFFF,
    topic_alias_maximum          => 0..16#FFFF,
    request_response_information => boolean(),
    request_problem_information  => boolean(),
    user_properties              => utf8_string_pairs(),
    authentication_method        => unicode:unicode_binary(),
    authentication_data          => binary()
}.

-type mqtt_connack_properties() :: #{
    session_expiry_interval           => 0..16#FFFF_FFFF,
    receive_maximum                   => 1..16#FFFF,
    maximum_qos                       => 0..2,
    retain_available                  => boolean(),
    maximum_packet_size               => 1..16#FFFF_FFFF,
    assigned_client_identifier        => unicode:unicode_binary(),
    topic_alias_maximum               => 0..16#FFFF,
    reason_string                     => unicode:unicode_binary(),
    user_properties                   => utf8_string_pairs(),
    wildcard_subscription_available   => boolean(),
    subscription_identifier_available => boolean(),
    shared_subscription_available     => boolean(),
    server_keep_alive                 => 0..16#FFFF,
    response_information              => unicode:unicode_binary(),
    server_reference                  => unicode:unicode_binary(),
    authentication_method             => unicode:unicode_binary(),
    authentication_data               => binary()
}.

-type mqtt_last_will_properties() :: #{
    will_delay_interval      => 0..16#FFFF_FFFF,
    payload_format_indicator => 0..1,
    message_expiry_interval  => 0..16#FFFF_FFFF,
    content_type             => unicode:unicode_binary(),
    response_topic           => unicode:unicode_binary(),
    correlation_data         => binary(),
    user_properties          => utf8_string_pairs()
}.

-type mqtt_puback_properties() :: #{
    reason_string   => unicode:unicode_binary(),
    user_properties => utf8_string_pairs()
}.

-type mqtt_pubcomp_properties() :: #{
    reason_string   => unicode:unicode_binary(),
    user_properties => utf8_string_pairs()
}.

-type mqtt_pubrec_properties() :: #{
    reason_string   => unicode:unicode_binary(),
    user_properties => utf8_string_pairs()
}.

-type mqtt_pubrel_properties() :: #{
    reason_string   => unicode:unicode_binary(),
    user_properties => utf8_string_pairs()
}.

-type mqtt_publish_properties() :: #{
    payload_format_indicator => 0..1,
    message_expiry_interval  => 0..16#FFFF_FFFF,
    topic_alias              => 1..16#FFFF,
    response_topic           => unicode:unicode_binary(),
    correlation_data         => binary(),
    user_properties          => utf8_string_pairs(),
    subscription_identifiers => [subscription_identifier()],
    content_type             => unicode:unicode_binary()
}.

-type mqtt_subscribe_properties() :: #{
    subscription_identifier => subscription_identifier(),
    user_properties         => utf8_string_pairs()
}.

-type mqtt_suback_properties() :: #{
    reason_string   => unicode:unicode_binary(),
    user_properties => utf8_string_pairs()
}.

-type mqtt_unsubscribe_properties() :: #{
    user_properties => utf8_string_pairs()
}.

-type mqtt_unsuback_properties() :: #{
    reason_string   => unicode:unicode_binary(),
    user_properties => utf8_string_pairs()
}.

-type mqtt_disconnect_properties() :: #{
    session_expiry_interval => 0..16#FFFF_FFFF,
    reason_string           => unicode:unicode_binary(),
    user_properties         => utf8_string_pairs()
}.

-type mqtt_auth_properties() :: #{
    authentication_method => unicode:unicode_binary(),
    authentication_data   => binary(),
    reason_string         => unicode:unicode_binary(),
    user_properties       => utf8_string_pairs()
}.
