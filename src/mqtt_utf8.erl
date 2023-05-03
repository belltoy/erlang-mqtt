-module(mqtt_utf8).

-export([validate_utf8_string/1]).

%% @doc Validate UTF-8 string according to RFC 3629 and MQTT
%% UTF-8 encoded string rules.
%%
%% If the input data is a incomplete UTF-8 string, return false.
-spec validate_utf8_string(binary()) -> boolean().
validate_utf8_string(<<>>) -> true;
validate_utf8_string(String) ->
    %% Validate UTF-8 string according to RFC 3629
    %% Validate UTF-8 character according to MQTT-1.5.4-1
    case unicode:characters_to_binary(String) of
        Bin when is_binary(Bin) -> validate_utf8_char(Bin);
        _ -> false
    end.

%% Validate UTF-8 character according to
%% MQTT-1.5.4-2
%% and all 66 non-characters
validate_utf8_char(<<>>)-> true;
validate_utf8_char(<<C/utf8, _Rest/binary>>)
  when 16#0000 =< C, C =< 16#001F;       %% C0 controls
       16#007F =< C, C =< 16#009F;       %% C1 controls
       %% 66 non-characters in all
       16#FDD0 =< C, C =< 16#FDEF;       %% non-characters in the BMP, 32 non-characters
       C =:= 16#FFFE; C =:= 16#FFFF;     %% non-characters, the last two code pints in the BMP
       C =:= 16#1FFFE; C =:= 16#1FFFF;   %% non-characters in each of the 16 supplementary planes
       C =:= 16#2FFFE; C =:= 16#2FFFF;
       C =:= 16#3FFFE; C =:= 16#3FFFF;
       C =:= 16#4FFFE; C =:= 16#4FFFF;
       C =:= 16#5FFFE; C =:= 16#5FFFF;
       C =:= 16#6FFFE; C =:= 16#6FFFF;
       C =:= 16#7FFFE; C =:= 16#7FFFF;
       C =:= 16#8FFFE; C =:= 16#8FFFF;
       C =:= 16#9FFFE; C =:= 16#9FFFF;
       C =:= 16#AFFFE; C =:= 16#AFFFF;
       C =:= 16#BFFFE; C =:= 16#BFFFF;
       C =:= 16#CFFFE; C =:= 16#CFFFF;
       C =:= 16#DFFFE; C =:= 16#DFFFF;
       C =:= 16#EFFFE; C =:= 16#EFFFF;
       C =:= 16#FFFFE; C =:= 16#FFFFF;
       C =:= 16#10FFFE; C =:= 16#10FFFF
       -> false;
validate_utf8_char(<<_/utf8, Rest/binary>>) -> validate_utf8_char(Rest);
validate_utf8_char(_) -> false.
