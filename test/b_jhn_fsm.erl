%%==============================================================================
%% Copyright 2013-2015 Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

%%%-------------------------------------------------------------------
%%% @doc
%%%   A utility module for the jhn_fsm_tests unit test module.
%%% @end
%%%
%% @author Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%% @copyright (C) 2013-2015, Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%%-------------------------------------------------------------------
-module(b_jhn_fsm).
-copyright('Jan Henry Nystrom <JanHenryNystrom@gmail.com>').
-behaviour(jhn_fsm).

%% Management API
-export([start/0, stop/0]).

%% API
-export([call/2, call/3, event/2]).

%% jhn_fsm callbacks
-export([init/1,
         handle_event/3,
         handle_msg/3,
         terminate/3,
         code_change/4
        ]).

%% jhn_fsm state callbacks
-export([first/2, second/2, third/2]).

%% Records
-record(state, {}).

%%====================================================================
%% Management API
%%====================================================================

start() ->
    jhn_fsm:start(?MODULE, [{name, ?MODULE}]).

stop() ->
    jhn_fsm:event(?MODULE, stop).

%%====================================================================
%% API
%%====================================================================

call(Server, Msg) -> jhn_fsm:call(Server, Msg).

call(Server, Msg, Timeout) -> jhn_fsm:call(Server, Msg, Timeout).

event(Server, Msg) -> jhn_fsm:event(Server, Msg).

%%====================================================================
%% jhn_server callbacks
%%====================================================================

init(no_arg) -> {ok, first, #state{}}.
handle_event({all_reply, X}, Name, State) ->
    inform({all_reply, X}, State),
    {ok, Name, State};
handle_event(event_hibernate, Name, State) ->
    jhn_fsm:reply(hibernate),
    {hibernate, Name, State};
handle_event(stop, _Name, _State) ->
    {stop, normal}.

handle_msg({bounce, first}, first, _) ->
    deferred;
handle_msg({bounce, first}, _, State) ->
    {ok, first, State};
handle_msg({reply, X}, Name, State) ->
    inform({reply, X}, State),
    {ok, Name, State};
handle_msg(hibernate, Name, State) ->
    inform(hibernate, State),
    {hibernate, Name, State}.

terminate(_, _, _) -> ok.

code_change(_OldVsn, Name, State, _Extra) ->
    inform(code_change, State),
    {ok, Name, State}.

%%====================================================================
%% jhn_server state callbacks
%%====================================================================

first(get_state, State) ->
    jhn_fsm:reply(first),
    {ok, first, State};
first({bounce, first}, _) ->
    deferred;
first({reply, X}, State) ->
    jhn_fsm:reply({reply, X}),
    {ok, first, State};
first(hibernate, State) ->
    jhn_fsm:reply(hibernate),
    {hibernate, first, State};
first({goto, Name}, State) ->
    {ok, Name, State}.

second(get_state, State) ->
    jhn_fsm:reply(second),
    {ok, second, State};
second({bounce, first}, State) ->
    {ok, first, State};
second({reply, X}, State) ->
    jhn_fsm:reply({reply, X}),
    {ok, second, State};
second(hibernate, State) ->
    jhn_fsm:reply(hibernate),
    {hibernate, second, State};
second({goto, Name}, State) ->
    {ok, Name, State}.

third(get_state, State) ->
    jhn_fsm:reply(third),
    {ok, third, State};
third({bounce, first}, State) ->
    {ok, first, State};
third({reply, X}, State) ->
    jhn_fsm:reply({reply, X}),
    {ok, third, State};
third(hibernate, State) ->
    jhn_fsm:reply(hibernate),
    {hibernate, third, State};
third({goto, Name}, State) ->
    {ok, Name, State}.

%%====================================================================
%% Internal functions
%%====================================================================

inform(What, _State) ->
    tester ! What.
