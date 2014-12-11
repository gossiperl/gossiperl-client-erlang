%% Copyright (c) 2014 Radoslaw Gruchalski <radek@gruchalski.com>
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.

-module(gossiperl_client_encryption).

-behaviour(gen_server).

-export([start_link/1, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).

-include("records.hrl").

%% @doc Starts encryption module.
start_link(Config) ->
  gen_server:start_link({local, ?ENCRYPTION(Config)}, ?MODULE, [Config], []).

%% @doc Stops encryption module.
stop() -> gen_server:cast(?MODULE, stop).

%% @doc Initializes encryption module.
-spec init( [ client_config() ] ) -> { ok, { encryption, client_config() } }.
init([Config]) ->
  {ok, {encryption, Config}}.

%% @doc Encrypt Msg and deliver to a caller.
handle_call({ maybe_encrypt, Msg }, From, { encryption, Config }) when is_binary(Msg) ->
  case Config#clientConfig.symmetric_key of
    undefined ->
      gen_server:reply(From, { ok, Msg });
    _ ->
      gen_server:reply(From, { ok, crypto:block_encrypt( aes_cbc256,
                                                         Config#clientConfig.symmetric_key,
                                                         Config#clientConfig.iv,
                                                         ?AES_PAD( Msg ) ) } )
  end,
  {noreply, {encryption, Config}};

%% @doc Decncrypt Msg and deliver to a caller.
handle_call({ maybe_decrypt, Msg }, From, { encryption, Config }) when is_binary(Msg) ->
  case Config#clientConfig.symmetric_key of
    undefined ->
      gen_server:reply(From, { ok, Msg });
    _ ->
      try
        gen_server:reply(From, { ok, crypto:block_decrypt( aes_cbc256,
                                                           Config#clientConfig.symmetric_key,
                                                           Config#clientConfig.iv,
                                                           Msg ) } )
      catch
        _Error:Reason -> gen_server:reply(From, {error, { decryption_failed, Reason }} )
      end
  end,
  {noreply, {encryption, Config}}.

handle_cast(stop, LoopData) ->
  {stop, normal, LoopData}.

handle_info(_, LoopData) ->
  {noreply, LoopData}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, _LoopData) ->
  {ok}.
