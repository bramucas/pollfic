%%%-------------------------------------------------------------------
%%% @author Daniel Gabín.
%%% @copyright (C) 2017.
%%% @doc Practica de AS: Servicio de votaciones.
%%% Nodo de descubrimiento - Primera funcionalidad.
%%% @end
%%% Created : 2017 by the authors.
%%%-------------------------------------------------------------------
 
-module(discover).

%% Public API
-export([start/1]).

-define(KEYFOLDER, "../keys/").


%%--------------------------------------------------------------------
%% @doc Function 'start'
%% @spec start(	Value1 :: Port)
%% @end
%% @doc Start discover node listening service in the giving port.
%% @end
%%--------------------------------------------------------------------

start(Port) ->
	{ok, Socket} = gen_udp:open(Port, [binary, {active,true}]),
	io:format("Server opened socket:~p~n",[Socket]),
	BalancerIP = dicc:get_conf(balancer_dit),
	BalancerPort = dicc:get_conf(balancer_port),
	util:send(Socket, BalancerIP, BalancerPort, erlang:term_to_binary(new_node)),
    {DiscoverIP,DiscoverPort} = receive
                                    {udp, Socket, BalancerIP, BalancerPort, Bin} ->
                                        binary_to_term(Bin)
                                end, 
    receive
        {udp, Socket, DiscoverIP, DiscoverPort, BalancerMsg} -> 
        		{lists,PollList,DiscoverList} = erlang:binary_to_term(BalancerMsg),
        		receive_public_keys(PollList,Socket)
    end,
    spawn(fun() -> loop(Socket,Port,PollList,DiscoverList) end).


%%start()->
%%	DiscoverPort = dicc:get_conf(discover_port),
%%	spawn(fun()-> init(DiscoverPort, []) end).


loop(Socket,L,FilePort,DiscoverList) ->
    inet:setopts(Socket, [{active, once}]),
    receive
        {udp, Socket, _, _, BalancerMsg} ->
        	{IP,Port,Msg} = erlang:binary_to_term(BalancerMsg),
        	case Msg of	
            	poll_request -> util:send(Socket, IP, Port, erlang:term_to_binary(L)),
            					loop(Socket, L, FilePort, DiscoverList);
            	{register, PollName} ->   case check_poll_name(L, PollName) of 
            								true -> 
		            							util:receive_file(PollName, Socket),
		            							util:send(Socket,IP,Port,erlang:term_to_binary({ok,registered})),
		            							loop(Socket, [{IP,Port,PollName}|L], FilePort,DiscoverList);
		            						_ ->  
		            							util:send(Socket, IP, Port, erlang:term_to_binary(name_not_avaliable)),
		            							loop(Socket, L, FilePort,DiscoverList)
		            					  end;
		        {delete, PollName} -> case check_poll_name(L,PollName) of 
		        						false -> 
		        							{PollIP,PollPort,PollName} = lists:keyfind(PollName,3,L),
		        							if IP == PollIP ->
		        									util:send(Socket, IP, Port, erlang:term_to_binary(deleted)),
		        									loop(Socket,lists:delete({PollIP,PollPort,PollName},L),FilePort,DiscoverList);
		        								true -> 
		        									util:send(Socket, IP, Port, erlang:term_to_binary(owner_error)),
		            							  	loop(Socket, L, FilePort,DiscoverList)
		            						end;
		            					_ ->
		            						util:send(Socket, IP, Port, erlang:term_to_binary(non_existing_name)),
		            						loop(Socket, L, FilePort,DiscoverList)
		            				  end;
                {public_key, PollName} -> 
                            util:send_file(IP, Port, ?KEYFOLDER++PollName++".pub"),
                            loop(Socket, L, FilePort,DiscoverList);
		        {renew} ->  
		        			NewL = update(L, IP, Port, []),
		        			util:send(Socket, IP, Port, erlang:term_to_binary(port_changed)),
		        			loop(Socket, NewL, FilePort,DiscoverList);
		        new_node -> 
		        			util:send(Socket,IP,Port,term_to_binary({lists,L,DiscoverList})),
		        			send_public_keys(L, Socket, Port, IP),
		        			new_discover(Socket, DiscoverList, IP, Port),
		        			loop(Socket, L, FilePort,DiscoverList);
		        {new_discover,NewIp, NewPort} -> 
		        			loop(Socket, L, FilePort, [{NewIp, NewPort}|DiscoverList])
        	end
    end.


check_poll_name([], _) -> true;

check_poll_name([{_,_,PollName}|_], PollName) -> false;

check_poll_name([_|T], PollName) -> 
	check_poll_name(T, PollName).


update([], _, _, Acc) -> Acc;

update([{IP,_,PollName}|T], IP, Port, Acc) -> 
	update(T, IP, Port, [{IP,Port,PollName}|Acc]);

update([H|T], IP, Port, Acc) ->
	update(T, IP, Port, [H|Acc]).


send_public_keys([{_,_,PollName}|T],Socket,Port,IP) ->
	util:send_file(IP,Port,"../keys/"++PollName++".pub"),
	receive_public_keys(T,Socket).

receive_public_keys([{_,_,PollName}|T],Socket) ->
	util:receive_file(PollName,Socket),
	receive_public_keys(T,Socket).

new_discover(_,[],_,_) -> ok;

new_discover(Socket, [{DiscIp, DiscPort}|T], Ip, Port) ->
	util:send(Socket, DiscIp, DiscPort, term_to_binary({new_discover, Ip, Port})),
	new_discover(Socket, T, Ip, Port).