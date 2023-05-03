-module(mqtt_client).

-include_lib("kernel/include/logger.hrl").
-include("mqtt_packet.hrl").

-behaviour(gen_statem).

-export([
    connect/1,
    connect/2,
    connect/3,
    close/1,
    publish/3,
    publish/4,
    subscribe/2,
    subscribe/3
]).

-export([
    start_link/4,
    init/1,
    callback_mode/0,
    terminate/3
]).

-export([
    idle/3,
    connecting/3,
    connected/3
]).

-define(DEFAULT_KEEP_ALIVE_SECONDS, 60).

-record(state, {
    protocol_version,
    socket,
    host,
    port,
    owner,
    buffer = <<>>,
    keep_alive,
    encode_opts = #{},
    decode_opts = #{},
    packet_id = 0,
    inflight_publishes = #{},
    inflight_receives = #{},
    inflight_subscribes = #{},
    monitor
}).

connect(Host) ->
    connect(Host, 1883).

connect(Host, Port) ->
    connect(Host, Port, #{}).

connect(Host, Port, Opts) ->
    mqtt_client_sup:start_client(self(), Host, Port, Opts).

close(Pid) ->
    gen_statem:cast(Pid, close).

publish(Pid, Topic, Message) ->
    publish(Pid, Topic, Message, #{}).

publish(Pid, Topic, Message, Opts) ->
    gen_statem:call(Pid, {publish, Topic, Message, Opts}).

subscribe(Pid, TopicFilter) ->
    subscribe(Pid, TopicFilter, #{}).
subscribe(Pid, TopicFilter, Opts) ->
    gen_statem:call(Pid, {subscribe, TopicFilter, Opts}).

start_link(Owner, Host, Port, Opts) ->
    gen_statem:start_link(?MODULE, [Owner, Host, Port, Opts], []).

callback_mode() ->
    state_functions.

init([Owner, Host, Port, Opts]) ->
    Version = maps:get(protocol_version, Opts, 5),
    Keepalive = maps:get(keep_alive, Opts, ?DEFAULT_KEEP_ALIVE_SECONDS),
    {ok, idle, #state{host = Host,
                      port = Port,
                      owner = Owner,
                      monitor = erlang:monitor(process, Owner),
                      keep_alive = Keepalive,
                      protocol_version = Version,
                      encode_opts = #{protocol_version => Version, from => client},
                      decode_opts = #{protocol_version => Version, from => server}
                     },
     [{next_event, internal, connect}]}.

idle(internal, connect, #state{
    keep_alive = KeepAlive,
    host = Host, port = Port
} = State) ->
    case gen_tcp:connect(Host, Port, [binary, {packet, raw}, {active, false}]) of
        {ok, Socket} ->
            {ok, {PeerAddr, PeerPort}} = inet:peername(Socket),
            {ok, {LocalAddr, LocalPort}} = inet:sockname(Socket),
            ?LOG_INFO("Connected to MQTT broker: ~s:~p at ~s:~p",
                      [inet:ntoa(PeerAddr), PeerPort, inet:ntoa(LocalAddr), LocalPort]),
            Opts = #{from => client, protocol_version => 5},
            ok = gen_tcp:send(Socket, mqtt_codec:encode(#mqtt_connect{
                                                           protocol_name = ?PROTOCOL_NAME_V5,
                                                           protocol_version = 5,
                                                           clean_session = true,
                                                           keep_alive = KeepAlive,
                                                           client_id = <<"mqtt_client">>
                                                       }, Opts)),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, connecting, State#state{socket = Socket}};
        {error, Reason} ->
            {stop, Reason, State}
    end.

connecting(info, {tcp, Socket, Data}, #state{socket = Socket, buffer = Buffer,
                                             protocol_version = ProtoVersion,
                                             decode_opts = DecodeOpts,
                                             keep_alive = KeepAlive
                                            } = State) ->
    Received = <<Buffer/binary, Data/binary>>,
    case mqtt_codec:decode(Received, DecodeOpts) of
        {ok, #mqtt_connack{reason_code = ?REASON_CODE_SUCCESS, properties = Props}, Rest} ->
            ok = inet:setopts(Socket, [{active, once}]),
            case {ProtoVersion, Props} of
                {?PROTOCOL_V5, #{server_keep_alive := ServerKeepAlive}} when ServerKeepAlive > 0 ->
                    {next_state, connected, State#state{buffer = Rest, keep_alive = ServerKeepAlive}};
                _ ->
                    % {next_state, connected, State#state{buffer = Rest}, {next_event, internal, subscribe}}
                    case KeepAlive of
                        0 -> {next_state, connected, State#state{buffer = Rest}};
                        _ -> {next_state, connected, State#state{buffer = Rest},
                             {state_timeout, KeepAlive * 1000, keepalive}}
                    end
            end;
        {ok, #mqtt_connack{reason_code = ReasonCode}, _Rest} ->
            {stop, ReasonCode, State};
        {error, Reason} ->
            {stop, Reason, State};
        incomplete ->
            ok = inet:setopts(Socket, [{active, once}]),
            {keep_state, State#state{buffer = Received}}
    end;
connecting({call, _From}, _Request, State) ->
    {keep_state, State, postpone};
connecting(info, {'DOWN', _Ref, process, _Pid, _Reason}, _State) ->
    {stop, normal}.

connected(state_timeout, keepalive, #state{socket = Socket, encode_opts = EncodeOpts} = State) ->
    ?LOG_DEBUG("Sending Ping request"),
    ok = gen_tcp:send(Socket, mqtt_codec:encode(#mqtt_pingreq{}, EncodeOpts)),
    {keep_state, State, {state_timeout, State#state.keep_alive * 1000, keepalive}};

connected({call, From}, {subscribe, TopicFilter, Opts}, State) ->
    State1 = handle_subscribe_request(From, TopicFilter, Opts, State),
    {keep_state, State1};
connected({call, From}, {publish, Topic, Message, Opts}, State) ->
    State1 = handle_publish_request(From, Topic, Message, Opts, State),
    {keep_state, State1};
connected(cast, close, #state{socket = Socket, encode_opts = EncodeOpts} = State) ->
    Disconnect = #mqtt_disconnect{reason_code = ?REASON_CODE_NORMAL_DISCONNECTION},
    ok = gen_tcp:send(Socket, mqtt_codec:encode(Disconnect, EncodeOpts)),
    {stop, normal, State};
connected(info, {tcp, Socket, Received}, State) ->
    case handle_buffer(Received, State) of
        {incomplete, State1} ->
            ok = inet:setopts(Socket, [{active, once}]),
            {keep_state, State1};
        {error, Reason} ->
            {stop, Reason, State}
    end.

terminate(_Reason, _State, _Data) ->
    ok.

%% For SUBSCRIBE at QoS 1 ack
send_puback(PacketId, Socket, EncodeOpts) ->
    Packet = #mqtt_puback{
        packet_id = PacketId,
        reason_code = ?REASON_CODE_SUCCESS
    },
    ok = gen_tcp:send(Socket, mqtt_codec:encode(Packet, EncodeOpts)).

%% For SUBSCRIBE at QoS 2 rec
send_pubrec(PacketId, Socket, EncodeOpts) ->
    Packet = #mqtt_pubrec{
        packet_id = PacketId,
        reason_code = ?REASON_CODE_SUCCESS
    },
    ok = gen_tcp:send(Socket, mqtt_codec:encode(Packet, EncodeOpts)).

%% For SUBSCRIBE at QoS 2 comp
send_pubcomp(PacketId, Socket, EncodeOpts) ->
    Packet = #mqtt_pubcomp{
        packet_id = PacketId,
        reason_code = ?REASON_CODE_SUCCESS
    },
    ok = gen_tcp:send(Socket, mqtt_codec:encode(Packet, EncodeOpts)).

%% For PUBLISH at QoS 2 rel
send_pubrel(PacketId, Socket, EncodeOpts) ->
    Packet = #mqtt_pubrel{
        packet_id = PacketId,
        reason_code = ?REASON_CODE_SUCCESS
    },
    ok = gen_tcp:send(Socket, mqtt_codec:encode(Packet, EncodeOpts)).

handle_buffer(Buffer1, #state{buffer = Buffer0} = State) ->
    Buffer2 = <<Buffer0/binary, Buffer1/binary>>,
    case mqtt_codec:decode(Buffer2, State#state.decode_opts) of
        {ok, Packet, Rest} ->
            State1 = handle_packet(Packet, State#state{buffer = Rest}),
            %% NOTE: Important, server may send multiple packets in one TCP packet
            handle_buffer(<<>>, State1);
        {error, _Reason} = Error -> Error;
        incomplete ->
            {incomplete, State#state{buffer = Buffer2}}
    end.

handle_packet(#mqtt_suback{packet_id = PacketId, reason_codes = ReasonCodes}, State) ->
    ?LOG_DEBUG("Received SUBACK for packet id: ~p", [PacketId]),
    case maps:take(PacketId, State#state.inflight_subscribes) of
        error ->
            ?LOG_INFO("Received SUBACK for unknown packet id: ~p", [PacketId]),
            State;
        {{From, _Sub}, NewInFlightSub} ->
            ok = gen_server:reply(From, {ok, ReasonCodes}),
            State#state{inflight_subscribes = NewInFlightSub}
    end;

%% For SUBSCRIBE receive
handle_packet(#mqtt_publish{packet_id = PacketId} = Packet,
              #state{socket = Socket, encode_opts = EncodeOpts} = State) ->
    ?LOG_INFO("Received publish: ~p", [Packet]),
    case Packet#mqtt_publish.qos of
        1 ->
            ok = send_puback(PacketId, Socket, EncodeOpts),
            State;
        2 ->
            ok = send_pubrec(PacketId, Socket, EncodeOpts),
            In1 = maps:put(PacketId, true, State#state.inflight_receives),
            State#state{inflight_receives = In1};
        _ ->
            State
    end;

%% For SUBSCRIBE at QoS 2 receive
handle_packet(#mqtt_pubrel{packet_id = PacketId},
              #state{socket = Socket, encode_opts = EncodeOpts} = State) ->
    ?LOG_INFO("Received PUBREL for packet id: ~p", [PacketId]),
    case maps:take(PacketId, State#state.inflight_receives) of
        error ->
            ?LOG_WARNING("Received PUBREL for unknown packet id: ~p", [PacketId]),
            State;
        {_, InflightReceives} ->
            ok = send_pubcomp(PacketId, Socket, EncodeOpts),
            State#state{inflight_receives= InflightReceives}
    end;

%% For PUBLISH at QoS 1
handle_packet(#mqtt_puback{packet_id = PacketId, reason_code = ReasonCode}, State) ->
    ?LOG_INFO("Received PUBACK: ~p, Reason Code: ~p", [PacketId, ReasonCode]),
    case maps:take(PacketId, State#state.inflight_publishes) of
        error ->
            ?LOG_WARNING("Received PUBACK for unknown packet id: ~p", [PacketId]),
            State;
        {{From, 1, publish}, InflightPublishes} ->
            gen_statem:reply(From, {ok, ReasonCode}),
            State#state{inflight_publishes = InflightPublishes}
    end;

%% For PUBLISH at QoS 2 receive
handle_packet(#mqtt_pubrec{packet_id = PacketId, reason_code = ReasonCode},
              #state{socket = Socket, encode_opts = EncodeOpts} = State) ->
    ?LOG_INFO("Received PUBREC for packet id: ~p, Reason Code: ~p", [PacketId, ReasonCode]),
    case {maps:take(PacketId, State#state.inflight_publishes), ReasonCode} of
        {error, _} ->
            ?LOG_WARNING("Received PUBREC for unknown packet id: ~p", [PacketId]),
            State;
        {{{From, 2, publish}, InflightPublishes}, ?REASON_CODE_SUCCESS} ->
            ok = send_pubrel(PacketId, Socket, EncodeOpts),
            In1 = InflightPublishes#{PacketId => {From, 2, pubrel}},
            State#state{inflight_publishes = In1};
        {{{From, 2, publish}, InflightPublishes}, _} ->
            gen_statem:reply(From, {error, ReasonCode}),
            State#state{inflight_publishes = InflightPublishes}
    end;

%% For PUBLISH at QoS 2 receive
handle_packet(#mqtt_pubcomp{packet_id = PacketId, reason_code = ReasonCode}, State) ->
    ?LOG_INFO("Received PUBCOMP for packet id: ~p", [PacketId]),
    case maps:take(PacketId, State#state.inflight_publishes) of
        error ->
            ?LOG_WARNING("Received PUBCOMP for unknown packet id: ~p", [PacketId]),
            State;
        {{From, 2, pubrel}, InflightPublishes} ->
            gen_statem:reply(From, {ok, ReasonCode}),
            State#state{inflight_publishes = InflightPublishes}
    end;

handle_packet(#mqtt_pingresp{}, State) ->
    ?LOG_DEBUG("Received Ping response"),
    State.

handle_publish_request(From, Topic, Message, Opts, #state{socket = Socket} = State) ->
    QoS = maps:get(qos, Opts, 0),
    Dup = maps:get(dup, Opts, false),
    Retain = maps:get(retain, Opts, false),
    Props = maps:get(properties, Opts, undefined),
    PacketId = case QoS of
                   0 -> undefined;
                   _ -> State#state.packet_id + 1
               end,
    Packet = #mqtt_publish{
        topic = Topic,
        message = Message,
        dup = Dup,
        qos = QoS,
        retain = Retain,
        packet_id = PacketId,
        properties = Props
    },
    ok = gen_tcp:send(Socket, mqtt_codec:encode(Packet, State#state.encode_opts)),
    case QoS of
        0 ->
            gen_statem:reply(From, ok),
            State;
            % {keep_state_and_data, {reply, From, ok}};
        _ ->
            InflightPublishes = maps:put(
                PacketId, {From, QoS, publish},
                State#state.inflight_publishes
            ),
            State#state{inflight_publishes = InflightPublishes, packet_id = PacketId}
    end.

handle_subscribe_request(From, TopicFilter, Opts,
    #state{socket = Socket,
           encode_opts = EncodeOpts,
           inflight_subscribes = Inflight0
          } = State) ->
    MaxQoS = maps:get(max_qos, Opts, 0),
    NoLocal = maps:get(no_local, Opts, false),
    RetainAsPublished = maps:get(retain_as_published, Opts, false),
    RetainHandling = maps:get(retain_handling, Opts, send_at_subscribe),
    PacketId = State#state.packet_id + 1,
    Subscriptions = [
        #mqtt_subscription{
            topic_filter = TopicFilter,
            max_qos = MaxQoS,
            no_local = NoLocal,
            retain_as_published = RetainAsPublished,
            retain_handling = RetainHandling
        }
    ],
    Sub = #mqtt_subscribe{
        packet_id = PacketId,
        topic_filters = Subscriptions
    },
    ok = gen_tcp:send(Socket, mqtt_codec:encode(Sub, EncodeOpts)),
    Inflight1 = Inflight0#{PacketId => {From, Sub}},
    State#state{packet_id = PacketId, inflight_subscribes = Inflight1}.
