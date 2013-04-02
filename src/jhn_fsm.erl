%%==============================================================================
%% Copyright 2013 Jan Henry Nystrom <JanHenryNystrom@gmail.com>
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
%%%   A finite state machine.
%%% @end
%%%
%% @author Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%% @copyright (C) 2013, Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%%-------------------------------------------------------------------
-module(jhn_fsm).
-copyright('Jan Henry Nystrom <JanHenryNystrom@gmail.com>').

%% API
-export([start/1, start/2,
         call/2, call/3,
         event/2,
         reply/1, reply/2, from/0
        ]).

%% sys callbacks
-export([system_continue/3,
         system_terminate/4,
         system_code_change/4,
         format_status/2]).

%% Behaviour callbacks
-export([behaviour_info/1]).

%% Internal exports
-export([init/5,
         loop/1, next_loop/2
        ]).

%% Records
-record(opts, {arg = no_arg,
               link = true :: boolean(),
               timeout = infinity :: timeout(),
               name :: atom(),
               errors = [] :: [_]
              }).

-record(state, {parent :: pid(),
                name :: pid() | atom(),
                mod :: atom(),
                state_name :: atom(),
                data,
                hibernated = false :: boolean(),
                deferred = {[], []} :: {[_], [_]},
                handling_deferred = false :: boolean()
               }).

-record('$jhn_fsm_msg', {from :: from(), payload}).

-record('$jhn_fsm_reply', {from ::from(), payload}).

-record(msg_store, {from ::from(), payload, replied = false:: boolean()}).

-record(from, {sender = self():: pid(),
               type = event :: event | call,
               ref :: reference()
              }).

-define(EVENT(Msg), #'$jhn_fsm_msg'{from = #from{}, payload = Msg}).
-define(CALL(MRef, Msg),
        #'$jhn_fsm_msg'{from = #from{type = call, ref = MRef}, payload = Msg}).
-define(REPLY(From, Msg), #'$jhn_fsm_reply'{from = From, payload = Msg}).

%% Defines
-define(DEFAULT_TIMEOUT, 5000).

%% Types
-type opt() :: {atom(), _}.
-type opts() :: [opt()].
-type fsm_ref() :: atom() | {atom(), node()} | pid().
-opaque from() :: #from{}.

%% Exported Types
-export_type([from/0]).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% Function: start(CallbackModule) -> Result.
%% @doc
%%   Starts a jhn_fsm.
%% @end
%%--------------------------------------------------------------------
-spec start(atom()) -> {ok, pid()} | ignore | {error, _}.
%%--------------------------------------------------------------------
start(Mod) -> start(Mod, []).

%%--------------------------------------------------------------------
%% Function: start(CallbackModule, Options) -> Result.
%% @doc
%%   Starts a jhn_fsm with options.
%%   Options are:
%%     {link, Boolean} -> if the server is linked to the parent, default true
%%     {timeout, infinity | Integer} -> Time in ms for the server to start and
%%         initialise, after that an exception is generated, default 5000.
%%     {name, Atom} -> name that the server is registered under.
%%     {arg, Term} -> argument provided to the init/1 callback function,
%%         default is 'no_arg'.
%% @end
%%--------------------------------------------------------------------
-spec start(atom(),  opts()) -> {ok, pid()} | ignore | {error, _}.
%%--------------------------------------------------------------------
start(Mod, Options) ->
    Ref = make_ref(),
    case opts(Options, #opts{}) of
        #opts{errors = Errors} when Errors /= [] -> {error, Errors};
        Opts = #opts{link = true, arg = Arg} ->
            Pid = spawn_link(?MODULE, init, [Mod, Arg, Opts, self(), Ref]),
            wait_ack(Pid, Ref, Opts, undefined);
        Opts = #opts{arg = Arg}->
            Pid = spawn(?MODULE, init, [Mod, Arg, Opts, self(), Ref]),
            MRef = erlang:monitor(process, Pid),
            wait_ack(Pid, Ref, Opts, MRef)
    end.

%%--------------------------------------------------------------------
%% Function: event(FSM, Message) -> ok.
%% @doc
%%   A event is made to the FSM, allways retuns ok.
%% @end
%%--------------------------------------------------------------------
-spec event(fsm_ref(), _) -> ok.
%%--------------------------------------------------------------------
event(FSM, Msg) when is_atom(FSM) -> do_event(FSM, Msg);
event(FSM, Msg) when is_pid(FSM)-> do_event(FSM, Msg);
event(FSM = {Name, Node}, Msg) when is_atom(Name), is_atom(Node) ->
    do_event(FSM, Msg);
event(FSM, Msg) ->
    erlang:error(badarg, [FSM, Msg]).

%%--------------------------------------------------------------------
%% Function: call(FSM, Message) -> Term.
%% @doc
%%   A call is made to FSM with default timeout 5000ms.
%% @end
%%--------------------------------------------------------------------
-spec call(fsm_ref(), _) -> _.
%%--------------------------------------------------------------------
call(FSM, Msg) -> call(FSM, Msg, ?DEFAULT_TIMEOUT).

%%--------------------------------------------------------------------
%% Function: call(FSM, Message, Timeout) -> Term.
%% @doc
%%   A call is made to FSM with Timeout. Will generate a timeout
%%   exception if the FSM takes more than Timeout time to answer.
%%   Generates an exception if the process is dead, dies, or no process
%%   registered under that name. If the FSM returns that is returned
%%   from the call.
%% @end
%%--------------------------------------------------------------------
-spec call(fsm_ref(), _, timeout()) -> _.
%%--------------------------------------------------------------------
call(FSM, Msg, Timeout)
  when is_pid(FSM), Timeout == infinity;
       is_pid(FSM), is_integer(Timeout), Timeout > 0;
       is_atom(FSM), Timeout == infinity;
       is_atom(FSM), is_integer(Timeout), Timeout > 0
       ->
    do_call(FSM, Msg, Timeout);
call({Name, Node}, Msg, Timeout)
  when is_atom(Name), Node == node(), Timeout == infinity;
       is_atom(Name), Node == node(), is_integer(Timeout), Timeout > 0
       ->
    do_call(Name, Msg, Timeout);
call(FSM = {Name, Node}, Msg, Timeout)
  when is_atom(Name), is_atom(Node), Timeout == infinity;
       is_atom(Name), is_atom(Node), is_integer(Timeout), Timeout > 0
       ->
    do_call(FSM, Msg, Timeout);
call(FSM, Msg, Timeout) ->
    erlang:error(badarg, [FSM, Msg, Timeout]).

%%--------------------------------------------------------------------
%% Function: reply(Message) -> ok.
%% @doc
%%   Called inside call back function to provide reply to a call or event.
%%   If called twice will cause the fsm to crash.
%% @end
%%--------------------------------------------------------------------
-spec reply(_) -> ok.
%%--------------------------------------------------------------------
reply(Msg) ->
    case read() of
        M  = #msg_store{from = #from{type = call}, replied = true} ->
            throw({stop, {multiple_replies, M#msg_store.payload}});
        M = #msg_store{from = #from{type = call} = From} ->
            write(M#msg_store{replied = true}),
            reply(From, Msg);
        #msg_store{from = From} ->
            reply(From, Msg)
    end.

%%--------------------------------------------------------------------
%% Function: reply(From, Message) -> ok.
%% @doc
%%   Called by any process will send a reply to the one that sent the
%%   request to the fsm, the From argument is the result from a call
%%   to from/1 inside a state function, handle_event/3 or handle_msg/2
%%   callback function.
%% @end
%%--------------------------------------------------------------------
-spec reply(from(), _) -> ok.
%%--------------------------------------------------------------------
reply(#from{type = event, sender = Sender}, Msg) ->
    Sender ! Msg,
    ok;
reply(From = #from{type = call, sender = Sender}, Msg) ->
    Sender ! ?REPLY(From, Msg),
    ok.

%%--------------------------------------------------------------------
%% Function: from() -> From.
%% @doc
%%   Called inside a state function, handle_req/2 or handle_msg/2 callback
%%   function it will provide an opaque data data enables a reply to the
%%   call or event outside the scope of the callback function.
%% @end
%%--------------------------------------------------------------------
-spec from() -> from().
%%--------------------------------------------------------------------
from() ->
    #msg_store{from = From} = read(),
    From.

%%====================================================================
%% sys callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: system_continue(Parent, Debug, State) ->
%% @private
%%--------------------------------------------------------------------
-spec system_continue(pid(), _, #state{}) -> none().
%%--------------------------------------------------------------------
system_continue(_, _, State = #state{state_name = Name}) ->
    next_loop(Name, State).

%%--------------------------------------------------------------------
%% Function: system_terminate(Reason, Parent, Debug, State) ->
%% @private
%%--------------------------------------------------------------------
-spec system_terminate(_, pid(), _, #state{}) -> none().
%%--------------------------------------------------------------------
system_terminate(Reason, _, _, State) -> terminate(Reason, [], State).


%%--------------------------------------------------------------------
%% Function: system_code_change(State, Module, OldVsn, Extra) ->
%% @private
%%--------------------------------------------------------------------
-spec system_code_change(#state{}, _, _, _) -> none().
%%--------------------------------------------------------------------
system_code_change(State, _, OldVsn, Extra) ->
    #state{data = Data, mod = Mod, state_name = StateName} = State,
    case catch Mod:code_change(OldVsn, StateName, Data, Extra) of
        {ok, NewStateName, NewData} ->
            {ok, State#state{state_name = NewStateName, data = NewData}};
        Else -> Else
    end.

%%--------------------------------------------------------------------
%% Function: format_status(Opt, StatusData) -> Status.
%% @private
%%--------------------------------------------------------------------
-spec format_status(_, _) -> [{atom(), _}].
%%--------------------------------------------------------------------
format_status(Opt, StatusData) ->
    [PDict, SysState, Parent, _Debug, State] = StatusData,
    #state{mod = Mod, state_name = StateName, data = Data} = State,
    NameTag =
        case State#state.name of
            Name when is_pid(Name) -> pid_to_list(Name);
            Name when is_atom(Name) -> Name
        end,
    Header = lists:concat(["Status for jhn fsm ", NameTag]),
    Specfic =
        case erlang:function_exported(Mod, format_status, 2) of
            true ->
                case catch Mod:format_status(Opt, [PDict, Data]) of
                    {'EXIT', _} -> [{data, [{"State", Data}]}];
                    Else -> Else
                end;
            _ ->
                [{data, [{"State", State}]}]
        end,
    [{header, Header},
     {data, [{"Status", SysState},
             {"Parent", Parent},
             {"StateName", StateName}]} |
     Specfic].

%%====================================================================
%% Behaviour callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: behaviour_info(callbacks) -> Callbacks.
%% @private
%%--------------------------------------------------------------------
-spec behaviour_info(atom()) -> undefined | [{atom(), arity()}].
%%--------------------------------------------------------------------
behaviour_info(callbacks) ->
    [{init, 1},
     {handle_event, 3},
     {handle_msg, 3},
     {terminate, 3},
     {code_change, 4}
    ];
behaviour_info(_) ->
    undefined.

%%====================================================================
%% Internal exports
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Module, Arguments, Opts, Parent, MonitorRef) ->
%% @private
%%--------------------------------------------------------------------
-spec init(atom(), _, #opts{}, pid(), reference()) -> _.
%%--------------------------------------------------------------------
init(Mod, Arg, Opts, Parent, Ref) ->
    write(behaviour),
    State = #state{parent = Parent, mod = Mod},
    case name(Opts, State) of
        {ok, State1} ->
            case catch Mod:init(Arg) of
                {ok, StateName, Data} ->
                    Parent ! {ack, Ref},
                    loop(State1#state{state_name = StateName, data = Data});
                {hibernate, StateName, Data} ->
                    Parent ! {ack, Ref},
                    erlang:hibernate(?MODULE,
                                     loop,
                                     [State1#state{state_name = StateName,
                                                   data = Data}]);
                ignore ->
                    Parent ! {ignore, Ref};
                {stop, Reason} ->
                    Parent ! {nack, Ref, Reason};
                Reason = {'EXIT', _} ->
                    Parent ! {nack, Ref, Reason};
                Other ->
                    Parent ! {nack, Ref, {bad_return_value, Other}}
            end;
        {error, Error} ->
            Parent ! {nack, Ref, Error}
    end.

%%--------------------------------------------------------------------
%% Function: loop(State) ->
%% @private
%%--------------------------------------------------------------------
-spec loop(#state{}) -> none().
%%--------------------------------------------------------------------
loop(State = #state{parent = Parent}) ->
    receive
        {system, From, Req} ->
            sys:handle_system_msg(Req, From, Parent, ?MODULE, [], State);
        Msg = {'EXIT', Parent, Reason} ->
            terminate(Reason, Msg, State);
        Msg ->
            handle_msg(Msg, State)
    end.

handle_msg(Item = #'$jhn_fsm_msg'{from = From, payload = Msg}, State) ->
    write(#msg_store{from = From, payload = Msg}),
    #state{mod = Mod,
           state_name = StateName,
           data = Data
          } = State,
    case catch Mod:StateName(Msg, Data) of
        {ok, NewStateName, NewData} ->
            write(clear),
            NewState = State#state{state_name = NewStateName,
                                   data = NewData,
                                   hibernated = false},
            next_loop(StateName, NewState);
        {hibernate, NewStateName, NewData} ->
            write(clear),
            NewState = State#state{state_name = NewStateName,
                                   data = NewData,
                                   hibernated = true},
            next_loop(StateName, NewState);
        deferred ->
            write(clear),
            next_loop(StateName, insert(Item, State));
        {stop, Reason} ->
            terminate(Reason, Msg, State);
%%        {'EXIT', {function_clause, [{Mod, StateName, _} | _]}} ->
        {'EXIT', {function_clause, [{Mod, StateName, _, _} | _]}} ->
            case catch Mod:handle_event(Msg, StateName, Data) of
                {ok, NewStateName, NewData} ->
                    write(clear),
                    NewState = State#state{state_name = NewStateName,
                                           data = NewData,
                                           hibernated = false},
                    next_loop(StateName, NewState);
                {hibernate, NewStateName, NewData} ->
                    write(clear),
                    NewState = State#state{state_name = NewStateName,
                                           data = NewData,
                                           hibernated = true},
                    next_loop(StateName, NewState);
                deferred ->
                    write(clear),
                    next_loop(StateName, insert(Item, State));
                {stop, Reason} ->
                    terminate(Reason, Msg, State);
%%                {'EXIT', {function_clause, [{Mod, handle_event,[_,_,_]}| _]}} ->
                {'EXIT', {function_clause, [{Mod, handle_event,[_,_,_], _}| _]}} ->
                    unexpected(event, Mod, Msg),
                    next_loop(StateName, State);
%%                {'EXIT', {undef, [{Mod, handle_event, [_, _, _]}| _]}} ->
                {'EXIT', {undef, [{Mod, handle_event, [_, _, _], _}| _]}} ->
                    unexpected(event, Mod, Msg),
                    next_loop(StateName, State);
                Other ->
                    terminate({bad_return_value, Other}, Msg, State)
            end;
        Other ->
            terminate({bad_return_value, Other}, Msg, State)
    end;
handle_msg(Info, State) ->
    #state{mod = Mod,
           state_name = StateName,
           data = Data
          } = State,
    case catch Mod:handle_msg(Info, StateName, Data) of
        {ok, NewStateName, NewData} ->
            NewState = State#state{state_name = NewStateName,
                                   data = NewData,
                                   hibernated = false},
            next_loop(StateName, NewState);
        {hibernate, NewStateName, NewData} ->
            NewState = State#state{state_name = NewStateName,
                                   data = NewData,
                                   hibernated = true},
            next_loop(StateName, NewState);
        deferred ->
            next_loop(StateName, insert(Info, State));
        {stop, Reason} ->
            terminate(Reason, Info, State);
%%        {'EXIT', {function_clause, [{Mod, handle_msg, [_, _, _]}| _]}} ->
        {'EXIT', {function_clause, [{Mod, handle_msg, [_, _, _], _}| _]}} ->
            unexpected(message, Mod, Info),
            next_loop(StateName, State);
%%        {'EXIT', {undef, [{Mod, handle_msg, [_, _, _]}| _]}} ->
        {'EXIT', {undef, [{Mod, handle_msg, [_, _, _], _}| _]}} ->
            unexpected(message, Mod, Info),
            next_loop(StateName, State);
        Other ->
            terminate({bad_return_value, Other}, Info, State)
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%%--------------------------------------------------------------------
wait_ack(Pid, Ref, Opts, MRef) ->
    receive
        {ack, Ref} ->
            unmonitor(MRef),
            {ok, Pid};
        {ignore, Ref} ->
            unmonitor(MRef),
            flush_exit(Pid),
            ignore;
        {nack, Ref, Reason} ->
            unmonitor(MRef),
            {error, Reason};
        {'EXIT', Pid, Reason} ->
            unmonitor(MRef),
            {error, Reason};
        {'DOWN', MRef, process, Pid, Reason} ->
            {error, Reason}
    after Opts#opts.timeout ->
            unmonitor(MRef),
            unlink(Pid),
            exit(Pid, kill),
            flush_exit(Pid),
            {error, timeout}
    end.

unmonitor(undefined) -> ok;
unmonitor(Mref) when is_reference(Mref) -> erlang:demonitor(Mref, [flush]).

flush_exit(Pid) ->
    receive {'EXIT', Pid, _} -> ok
    after 0 -> ok
    end.

%%--------------------------------------------------------------------
opts([], Opts) -> Opts;
opts([{link, Value} | T], Opts) when is_boolean(Value) ->
    opts(T, Opts#opts{link = Value});
opts([{timeout, infinity} | T], Opts) ->
    opts(T, Opts#opts{timeout = infinity});
opts([{timeout, Value} | T], Opts) when is_integer(Value), Value > 0 ->
    opts(T, Opts#opts{timeout = Value});
opts([{name, Value} | T], Opts) when is_atom(Value) ->
    opts(T, Opts#opts{name = Value});
opts([{arg, Value} | T], Opts) ->
    opts(T, Opts#opts{arg = Value});
opts([H | T], Opts = #opts{errors = Errors}) ->
    opts(T, Opts#opts{errors = [H | Errors]}).

%%--------------------------------------------------------------------
name(#opts{name = undefined}, State) ->
    {ok, State#state{name = self()}};
name(#opts{name = Name}, State) ->
    case catch register(Name, self()) of
        true ->
            {ok, State#state{name = Name}};
        _ ->
            {error, {already_started, Name, whereis(Name)}}
    end.

%%--------------------------------------------------------------------
terminate(Reason, Msg, State) ->
    #state{mod = Mod, state_name = StateName, data = Data} = State,
    case catch {ok, Mod:terminate(Reason, StateName, Data)} of
        {ok, _} ->
            case Reason of
                normal ->
                    exit(normal);
                shutdown ->
                    exit(shutdown);
                {shutdown, _}=Shutdown ->
                    exit(Shutdown);
                _ ->
                    error_info(Reason, Msg, State),
                    exit(Reason)
            end;
        {'EXIT', Reason1} ->
            error_info(Reason1, Msg, State),
            exit(Reason1);
        Reason2 ->
            error_info(Reason2, Msg, State),
            exit(Reason2)
    end.

error_info(Reason, [], #state{data = Data, name = Name}) ->
    error_logger:format("** JHN fsm ~p terminating \n"
                        "** When fsm state == ~p~n"
                        "** Reason for termination == ~n** ~p~n",
                        [Name, Data, Reason]);
error_info(Reason, Msg, #state{data = Data, name = Name}) ->
    error_logger:format("** JHN fsm ~p terminating \n"
                        "** Last message in was ~p~n"
                        "** When fsm state == ~p~n"
                        "** Reason for termination == ~n** ~p~n",
                        [Name, Msg, Data, Reason]).

%%--------------------------------------------------------------------
do_event(FSM, Msg) ->
    case catch erlang:send(FSM, ?EVENT(Msg), [noconnect]) of
        noconnect ->
            % Wait for autoconnect in separate process.
            spawn(erlang, send, [FSM, ?EVENT(Msg)]);
        _ ->
            ok
    end.

%%--------------------------------------------------------------------
do_call(FSM, Msg, Timeout) ->
    Node = case FSM of
               {_, Node0} when is_atom(Node0) -> Node0;
               Name when is_atom(Name) -> node();
               _ when is_pid(FSM) -> node(FSM)
           end,
    case catch erlang:monitor(process, FSM) of
        MRef when is_reference(MRef) ->
            % The monitor will do any autoconnect.
            case catch erlang:send(FSM, ?CALL(MRef, Msg), [noconnect]) of
                ok ->
                    wait_call(Node, MRef, Timeout);
                noconnect ->
                    erlang:demonitor(MRef, [flush]),
                    exit({nodedown, Node});
                _ ->
                    exit(noproc)
            end;
        _ ->
            exit(internal_error)
    end.

%%--------------------------------------------------------------------
wait_call(Node, MRef, Timeout) ->
    receive
        #'$jhn_fsm_reply'{from = #from{ref = MRef}, payload = Reply} ->
            erlang:demonitor(MRef, [flush]),
            Reply;
        {'DOWN', MRef, process, _, noconnection} ->
            exit({nodedown, Node});
        {'DOWN', MRef, process, _, Reason} ->
            exit(Reason)
    after Timeout ->
            erlang:demonitor(MRef, [flush]),
            exit(timeout)
    end.

%%--------------------------------------------------------------------
next_loop(Name, State = #state{state_name = Name,
                               handling_deferred = false,
                               hibernated = true}) ->
    erlang:hibernate(?MODULE, loop, [State]);
next_loop(Name, State = #state{state_name = Name, handling_deferred = false}) ->
    loop(State);
next_loop(Name, State = #state{state_name = Name}) ->
    case remove(State, continue) of
        State1 = #state{} -> loop(State1);
        {Msg, State1} -> handle_msg(Msg, State1)
    end;
next_loop(_, State) ->
    case remove(State, restart) of
        State1 = #state{} -> loop(State1);
        {Msg, State1} -> handle_msg(Msg, State1)
    end.

%%--------------------------------------------------------------------
read() ->
    case erlang:get('$jhn_behaviour') of
        fsm -> case erlang:get('$jhn_msg_store') of
                      Msg = #msg_store{} ->
                          Msg;
                      _ ->
                          erlang:error({not_in_request_context, ?MODULE})
                  end;
        undefined -> erlang:error({not_behaviour_context, ?MODULE});
        _ -> erlang:error({wrong_behaviour_context, ?MODULE})
    end.

%%--------------------------------------------------------------------
write(behaviour) -> erlang:put('$jhn_behaviour', fsm);
write(clear) -> erlang:put('$jhn_msg_store', undefined);
write(Message = #msg_store{}) -> erlang:put('$jhn_msg_store', Message).


%%--------------------------------------------------------------------
unexpected(Type, Mod, Msg) ->
    error_logger:format("JHN FSM ~p(~p) received unexpected ~p: ~p~n",
                        [Mod, self(), Type, Msg]).

%%--------------------------------------------------------------------
insert(Elt, State  = #state{handling_deferred = true}) ->
    {Deferred, New} = State#state.deferred,
    State#state{deferred = {Deferred, [Elt | New]}};
insert(Elt, State = #state{deferred = {Deferred, []}}) ->
    State#state{deferred = {[Elt | Deferred], []}}.

%%--------------------------------------------------------------------
remove(State = #state{deferred = {[], New}}, restart) ->
    remove(State#state{deferred = {lists:reverse(New), []}}, continue);
remove(State = #state{deferred = {[], New}}, continue) ->
    State#state{deferred = {New, []}, handling_deferred = false};
remove(State = #state{deferred = {Tail, []}, handling_deferred = false}, _) ->
    [Elt | Head] = lists:reverse(Tail),
    {Elt, State#state{deferred = {Head, []}, handling_deferred = true}};
remove(State = #state{deferred = {Head, New}}, restart) ->
    remove(State#state{deferred = {lists:reverse(New) ++ Head, []}}, continue);
remove(State = #state{deferred = {[Elt | Head], New}}, continue) ->
    {Elt, State#state{deferred = {Head, New}}}.
