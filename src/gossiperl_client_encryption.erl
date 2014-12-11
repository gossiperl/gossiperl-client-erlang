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

-export([maybe_encrypt/2, maybe_decrypt/2]).

-include("records.hrl").

maybe_encrypt(Msg, Config) ->
  case Config#clientConfig.symmetric_key of
    undefined ->
      Msg;
    _ ->
      crypto:block_encrypt(
        aes_cbc256,
        Config#clientConfig.symmetric_key,
        Config#clientConfig.iv,
        ?AES_PAD( Msg ) )
  end.

maybe_decrypt(Msg, Config) ->
  case Config#clientConfig.symmetric_key of
    undefined ->
      Msg;
    _ ->
      try
        crypto:block_decrypt(
          aes_cbc256,
          Config#clientConfig.symmetric_key,
          Config#clientConfig.iv,
          Msg )
      catch
        _Error:_Reason ->
          {error, decryption_failed}
      end
  end.
