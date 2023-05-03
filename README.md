MQTT codec for Erlang/Elixir
============================

A codec library for MQTT v3.1 (3), v3.1.1 (4), v5.0 (5).

## Usage

Add this repo in your `rebar.config` as a dependent:

```erlang
{deps, [
    {mqtt, {git, "https://github.com/belltoy/erlang-mqtt.git", {branch, "master"}}}
]}.
```

This library provides an MQTT codec for MQTT v3.1, v3.1.1 and v5.0.

- `mqtt_codec:decode/2`
- `mqtt_codec:encode/2`

And a `mqtt_packet.hrl` header file for all provided records and constants.

This is a basic for Erlang/Elixir to build your own MQTT broker/client.

There is a simple MQTT client on top of it.
Read [`mqtt_client.erl`](/src/mqtt_client.erl) for more detail.

## TODO

- [ ] Error handling

## License

Copyright 2023, belltoy.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
