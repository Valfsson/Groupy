-module(gms3).
-export([start/1, start/2]).
-define(timeout, 5000).
-define(arghh, 100).


%% Starts the 1st Node
start(Id) ->
    Rnd = random:uniform(1000),
    Self= self(),
    {ok, spawn_link(fun()-> init(Id, Rnd, Self) end)}.


init(Id, Rnd, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    leader(Id, Master, 1, [], [Master]).


%% Sends requests for other Nodes to join the Group
start(Id, Grp) ->
    Rnd = random:uniform(1000),
    Self= self(),
    {ok, spawn_link(fun()-> init(Id, Grp, Rnd, Self) end)}.


%%
init(Id, Grp, Rnd, Master)->

    random:seed(Rnd, Rnd, Rnd),
    Self= self(),
    Grp ! {join, Master, Self},
    receive
        {view, N, [Leader|Slaves], Group} ->
            Master ! {view, Group},
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group}, Slaves, Group)

    end.


leader(Id, Master, N, Slaves, Group) ->
    receive

        %% Msg multicasted to all peers and send to application lever (Master)
        {mcast,Msg} ->
            bcast(Id,{msg, N, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, N+1, Slaves, Group);

        %% Handles request to join the group
        {join, Wrk, Peer} ->
            Slaves2 = lists:append(Slaves, [Peer]),    %%ordered
            Group2 = lists:append(Group,[Wrk]),
            bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
            Master ! {view, Group2},
            leader(Id, Master, N+1, Slaves2, Group2);

        stop ->
            ok
    end.

%% Sends message to each of the processes in a list
bcast(Id, Msg, Nodes)->
    lists:foreach(fun(Node)-> Node! Msg, crash(Id) end, Nodes).

crash(Id) ->
    case random:uniform(?arghh) of
          ?arghh ->
              io:format("leader ~w: crash~n", [Id]),
              exit(no_luck);
          _ ->
                ok
    end.


%% forwarding messages from Master to the leader and vice verse
%% state is the same as it´s leader but keeps explicit track of the leader

slave(Id, Master, Leader, N, Last, Slaves, Group) ->
    receive

        %% Handles request from master to multicast msg. Forwards to Leader
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, N, Last, Slaves, Group);

        %% Handles request from Master to allow new Node to join the group
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, N, Last, Slaves, Group);

        %% Forwards message to the Leader
        {msg, N, Msg} ->
            Master! Msg,
            slave(Id, Master, Leader, N+1, {msg, N, Msg}, Slaves, Group);

        %% Detects old messages
        {msg, I, _ } when I < N ->
            slave(Id, Master, Leader, N, Last, Slaves, Group);

        %% Gets view from the Leader. Delivers vie to Master process
        {view, N, [Leader|Slaves2], Group2} ->
            Master ! {view, Group2},
            slave(Id, Master, Leader, N+1, {view, N,[Leader|Slaves2], Group2}, Slaves2, Group2);

        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Id, Master, N, Last, Slaves, Group);

        stop ->
            ok

        after ?timeout ->
            Master ! {error, "no reply from leader"}

    end.

%% Elects new Leader node (1st Node in the Slaves/ Peers list)
election(Id, Master, N, Last, Slaves, [_|Group])->
    Self=self(),
    case Slaves of
        %%process itself is first in the list. New leader.
        [Self| Rest] ->
            bcast(Id, Last, Rest),
            bcast(Id, {view, N, Slaves, Group}, Rest),
            Master !{view, Group},
            leader(Id, Master, N+1, Rest, Group);

        [Leader|Rest]->
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, N, Last, Rest, Group)
    end.
