#run {
	// set_build_options_dc(.{ do_output = false });
}

init_networking :: (using game_data: *Game_Data) {
	ok := socket_init();
	assert(ok);

	// context.logger = (message: string, data: *void, info: Log_Info) {
	// 	if !message return;
	// 	using info.location;
	// 	print("\e[32m[%:%:%] %\e[0m\n",
	// 		fully_pathed_filename, line_number, character_number,
	// 		message);
	// };

	if am_server {
		ok = false;
		defer if !ok {
			log_error("Failed to start up networking: %", get_error_string(get_last_socket_error()));
			if listen_socket != INVALID_SOCKET {
				close_and_reset(*listen_socket);
			}
			assert(false);
		}

		if !init_socket(*listen_socket) return;
		if bind(listen_socket, 0, port, AF_INET) != 0 return;
		if listen(listen_socket, 1) != 0 return;

		ok = true;
		log("Waiting for a client on port %", port);

		for *conn : client_connections {
			init_buffers(conn);
		}
	} else /* am client */ {
		hints := addrinfo.{ ai_family = AF_INET, ai_socktype = .SOCK_STREAM, ai_protocol = .TCP };
		assert(server_address.data[server_address.count] == 0);
		rc := getaddrinfo(server_address.data, tprint("%\0", port).data, *hints, *server_addrinfo);
		if rc {
			log_error("Failed to start up networking: %", get_error_string(get_last_socket_error()));
			assert(false);
		}

		log("Connecting to the server at %:%", server_address, port);

		server_connection.state = .CONNECTING;
		server_connection.socket = INVALID_SOCKET;
		init_buffers(*server_connection);
	}
}

do_networking :: (using game_data: *Game_Data) {
	if am_server {
		maybe_accept_new_connections(*networking_data);

		for *client_connection, client_index : client_connections {
			using client_connection;
			if state == .CONNECTING continue;
			defer if state == .CONNECTING {
				log_error("Lost connection to client %", client_index);
				close_and_reset(*socket);
				buffer_out.back.pending.count = 0;
				buffer_in.front.pending.count = 0;
			}

			if !buffer_out.front.pending {
				if state == {
					case .INITIALIZING;
						// FIXME: this works for simple cases, but it will fail if clients start falling off and reconnecting.
						// For example
						// 1. Client 1 connects -> gets player index 1.
						// 3. Client 2 connects -> gets player index 2.
						// 5. Client 1 disconnects.
						// 6. Client 2 disconnects.
						// 7. Client 2 connects -> maybe_accept_new_connections puts it in the first client's slot.
						// *. Now server thinks that client 2 is client 1.
						//
						// To make this more robust the protocol should be more involved.
						// For example upon a new connection/reconnection the server should ask the client if they know their
						// player index. If no, then give them a new player index, otherwise keep calm and carry on.
						//
						message : Networking_Message;
						message.type = .ASSIGN_PLAYER_INDEX;
						// Add 1 to client_index, because player 0 is always server.
						message.assign_player_index.player_index = xx (client_index + 1);
						buffer_out.front.pending = encode_message(buffer_out.front.capacity, *message);
						state = .CONNECTED;

					case .CONNECTED;
						// TODO: encode new steps
				}
			} else {
				// Still have an unsent packet from last time.
			}

			handle_outgoing_packets(game_data, client_connection);
			if state == .CONNECTING continue;
			handle_incomming_packets(game_data, client_connection);
			if state == .CONNECTING continue;
		}
	} else /* am client */ {
		using server_connection;
		maybe_connect_to_server(*networking_data);

		if state == .CONNECTING return;
		defer if state == .CONNECTING {
			log_error("Lost connection to server, will retry connecting...");
			close_and_reset(*socket);
			buffer_out.back.pending.count = 0;
			buffer_in.front.pending.count = 0;
		}

		if !buffer_out.front.pending {
			// TODO: encode outgoing messages
		} else {
			// Still have an unsent packet from last time.
		}

		handle_outgoing_packets(game_data, *server_connection);
		if state == .CONNECTING return;
		handle_incomming_packets(game_data, *server_connection);
		if state == .CONNECTING return;
	}
}

handle_outgoing_packets :: (game_data: *Game_Data, using connection: *Network_Connection) {
	// This loop is kinda confusing. It will only ever do at most 2 iterations:
	// 1st for packets not completely sent on the previous attempt, and
	// 2nd for the newly encoded packets.
	while true {
		if !buffer_out.back.pending { // No more pending outgoing packets.
			Swap(*buffer_out.front, *buffer_out.back); // Now sending the newly encoded packets.
			if !buffer_out.back.pending break;
		}

		n_bytes_sent := send_pending_slice(connection);
		// if n_bytes_sent {
		// 	Setup_Mem_Dump_Printer();
		// 	view : [] u8 = ---;
		// 	view.data = buffer_out.back.pending.data - n_bytes_sent;
		// 	view.count = n_bytes_sent;
		// 	log(#string END

// >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
// sent packet:
// %
// >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
		// 	END, cast(Mem_Dump) view);
		// }


		if connection.buffer_out.back.pending {
			// We were trying to send these packets but failed to send them completely for some reason.
			// We'll just try sending them next time around.
			break;
		}
	}
}

handle_incomming_packets :: (game_data: *Game_Data, connection: *Network_Connection) {
	should_be_receiving_packets := true;
	while should_be_receiving_packets {
		using connection.buffer_in;

		received_slice := receive_slice(connection);
		// if received_slice {
		// 	Setup_Mem_Dump_Printer();
		// 	log(#string END

// <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
// received data:
// %
// <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		// 	END, cast(Mem_Dump) received_slice);
		// }

		// Didn't fill up the buffer -> received all there was to receive for now.
		if received_slice.count != back.capacity.count then should_be_receiving_packets = false;

		while received_slice {
			packet_size := read_packet_header(front.pending);

			size_to_copy_wanted := 0;
			ifx packet_size < 0 // Not enough data in pending.
				size_to_copy_wanted = size_of(Packet_Header) - front.pending.count;
			else
				size_to_copy_wanted = packet_size - front.pending.count;

			size_to_copy := min(size_to_copy_wanted, xx received_slice.count);
			memcpy(front.pending.data + front.pending.count, received_slice.data, size_to_copy);
			front.pending.count += size_to_copy;
			advance(*received_slice, size_to_copy);

			if packet_size < 0 continue; // Retry reading packet header.

			if front.pending.count < packet_size break; // Not enough data received.
			assert(front.pending.count == packet_size);

			message : Networking_Message = ---;
			decode_message(front.pending, *message);
			handle_message(game_data, *message);
			front.pending.count = 0;
		}
	}
}

handle_message :: (game_data: *Game_Data, _message: *Networking_Message) {
	if _message.type == {
		case .ASSIGN_PLAYER_INDEX;
			message := *_message.assign_player_index;
			assert(game_data.board_interface.player_me == 4, "received player index reassignment");
			assert(!game_data.am_server, "only server can send ASSIGN_PLAYER_INDEX messages");
			game_data.board_interface.player_me = message.player_index;
	}
}

#scope_module

MAGIC :: cast([8] u8) "checkers";

Packet_Header :: struct {
	// Just usefull for debugging.
	magic := MAGIC;
	packet_size : s32;
} #no_padding // Needs to be packed, we rely on it in a couple of places.

Networking_Message :: struct {
	header: Packet_Header;
	type: enum u8 {
		ASSIGN_PLAYER_INDEX :: 1;
		STEPS :: 2;
	};
	union {
		assign_player_index : struct {
			player_index : s8;
		};
	}
}

read_packet_header :: (buffer: [] u8) -> packet_size: s32 {
	slice := buffer;
	header : Packet_Header = ---;
	if !code_struct(*slice, *header, .DECODE) return -1;
	assert(is_equal(header.magic, MAGIC));
	return header.packet_size;
}

decode_message :: (buffer: [] u8, message: *Networking_Message) {
	slice := buffer;

	assert(code_struct(*slice, *message.header, .DECODE));
	assert(is_equal(message.header.magic, MAGIC));
	assert(message.header.packet_size == buffer.count);

	assert(code_polymorphic(*slice, *message.type, .DECODE));
	if message.type == {
		case .ASSIGN_PLAYER_INDEX;
			assert(code_polymorphic(*slice, *message.assign_player_index.player_index, .DECODE));
	}

	assert(!slice);
}

encode_message :: (buffer: [] u8, message: *Networking_Message) -> [] u8 {
	slice := buffer;

	assert(code_struct(*slice, *message.header, .ENCODE));

	assert(code_polymorphic(*slice, *message.type, .ENCODE));
	if message.type == {
		case .ASSIGN_PLAYER_INDEX;
			assert(code_polymorphic(*slice, *message.assign_player_index.player_index, .ENCODE));
	}

	packet_size : s32 = xx (slice.data - buffer.data);
	packet_size_offset_in_header :: #run member_offset_in_bytes(Packet_Header, "packet_size");
	memcpy(buffer.data + packet_size_offset_in_header, *packet_size, size_of(type_of(packet_size)));

	return array_view(buffer, 0, packet_size);
}

maybe_accept_new_connections :: (using networking_data: *Networking_Data) {
	new_conn : *Network_Connection = null;
	for * client_connections if it.socket == INVALID_SOCKET {
		new_conn = it;
		break;
	}
	if new_conn == null return;

	new_socket := accept(listen_socket, null, null);
	if new_socket == INVALID_SOCKET {
		error := get_last_socket_error();
		if error != SOCKET_WOULDBLOCK {
			log_error("Failed accepting a connection: #%, %", error, get_error_string(error));
		} else {
			// Connection not ready yet, will retry next time.
		}
		return;
	}

	log("Accepted a connection!");
	new_conn.socket = new_socket;
	new_conn.state = .INITIALIZING;
}

maybe_connect_to_server :: (using networking_data: *Networking_Data) {
	using server_connection;
	if socket == INVALID_SOCKET assert(init_socket(*socket));

	if state == .CONNECTING {
		rc := connect(socket, server_addrinfo.ai_addr, xx server_addrinfo.ai_addrlen);
		if rc {
			error := get_last_socket_error();
			if error == SOCKET_WOULDBLOCK return; // Connection not ready yet, will retry next time.
			#if OS == .WINDOWS {
				if error == EALREADY || error == EINPROGRESS return;
				if error == EISCONN {
					log("Connected to server!");
					state = .CONNECTED;
					return;
				}
			}
			log_error("Failed connecting to server: #% %", error, get_error_string(error));
			return;
		}
		log("Connected to server!");
		state = .CONNECTED;
	}
}

init_socket :: (s: *Socket) -> ok: bool {
	s.* = socket(AF_INET, .SOCK_STREAM, .TCP);
	if s.* == INVALID_SOCKET {
		log_error("Failed creating a socket: %", get_error_string(get_last_socket_error()));
		return false;
	}

	if !set_blocking(s.*, blocking = false) {
		log_error("Failed setting socket to non blocking mode: %", get_error_string(get_last_socket_error()));
		s.* = INVALID_SOCKET;
		return false;
	}
	return true;
}

init_buffers :: (using conn: *Network_Connection) {
	// These are supposed to live for the whole lifetime of the program,
	// so we don't bother freeing them.
	buffer_in.front.capacity  = New([IO_BUFFER_SIZE] u8).*;
	buffer_in.back.capacity   = New([IO_BUFFER_SIZE] u8).*;
	buffer_out.front.capacity = New([IO_BUFFER_SIZE] u8).*;
	buffer_out.back.capacity  = New([IO_BUFFER_SIZE] u8).*;

	buffer_in.front.pending  = array_view(buffer_in.front.capacity, 0, 0);
	buffer_in.back.pending   = array_view(buffer_in.back.capacity, 0, 0);
	buffer_out.front.pending = array_view(buffer_out.front.capacity, 0, 0);
	buffer_out.back.pending  = array_view(buffer_out.back.capacity, 0, 0);
}

send_pending_slice :: (using conn: *Network_Connection) -> n_bytes_sent: s32 {
	buf := *buffer_out.back.pending;
	rc := send(socket, buf.data, xx buf.count, 0);
	Handle_IO_Error(rc, "sending to socket");
	if rc < 0 return 0;
	advance(buf, rc);
	return xx rc;
}

receive_slice :: (using conn: *Network_Connection) -> [] u8 {
	buf := buffer_in.back.capacity;
	rc := recv(socket, buf.data, xx buf.count, 0);
	Handle_IO_Error(rc, "receiving from socket");
	if rc < 0 return .[];
	return array_view(buf, 0, rc);
}

Handle_IO_Error :: (rc: s64, when: string) #expand {
	if rc < 0 {
		error := get_last_socket_error();
		if error == SOCKET_WOULDBLOCK return;

		log_error("Failed %: #% %", when, error, get_error_string(error));
		if error == ECONNRESET {
			`state = .CONNECTING;
		}
	}
}

Networking_Data :: struct {
	// Player 0 is always server.
	player_is_remote : [3] bool;
	am_server := false;
	union {
		using server_data : struct {
			listen_socket: Socket = INVALID_SOCKET;
			client_connections: [3] Network_Connection;
		};
		using client_data : struct {
			server_connection: Network_Connection;
			server_address: string;
			server_addrinfo: *addrinfo;
		}
	}
	port: u16 = 13370;
};

Network_Connection :: struct {
	state: enum u8 { CONNECTING; INITIALIZING; CONNECTED; } = .CONNECTING;
	socket: Socket = INVALID_SOCKET;
	buffer_in: IO_Buffer_Pair;
	buffer_out: IO_Buffer_Pair;
}

IO_BUFFER_SIZE :: 4 * 1024;

IO_Buffer_Pair :: struct {
	// Front buffer is the one we decode from / encode into.
	front: IO_Buffer;
	// Back buffer is the one we read from socket / write into socket.
	back: IO_Buffer;
}

IO_Buffer :: struct {
    capacity: [] u8;
    pending: [] u8;
}

//
// encoding/decoding {{{
//
// All numbers are encoded in native endianness, which is almost always little
// endian. If you want to communicate with big endian machines for some reason
// you'll have to implement that.
//

Coding_Mode :: enum { ENCODE; DECODE; }

// Encode/decode a single value (in native endianness).
code_polymorphic :: (slice: *[] u8, value: *$T, $mode: Coding_Mode) -> ok: bool {
	#if #run (cast(*Type_Info) T).type != .STRUCT {

		if slice.count < size_of(T) return false;
		if mode == {
			case .ENCODE; memcpy(slice.data, value, size_of(T));
			case .DECODE; memcpy(value, slice.data, size_of(T));
		}
		advance(slice, size_of(T));
		return true;

	} else #if #run is_specialization_of(T, Variable_Length_Array) {
		return code_variable_length_array(slice, value, mode);
	} else {
		return code_struct(slice, value, mode);
	}
}

// Encode/decode all of struct's fields contiguously in memory. No padding is
// added between fields even if `#no_padding` is not specified for the struct.
code_struct :: (slice: *[] u8, value: *$T, $mode: Coding_Mode) -> ok: bool
#modify { return (cast(*Type_Info) T).type == .STRUCT; }
{
	#insert #run -> string {
		sb: String_Builder;
		ti := cast(*Type_Info_Struct) T;
		for member: ti.members {
			// TODO: filter out const fields.
			print_to_builder(*sb, #string END

	if !code_polymorphic(slice, *value.%, mode) return false;

			END, member.name);
		}
		return builder_to_string(*sb);
	};

	return true;
}

// Encode/decode an array of variable length. First a 32 bit `count` is encoded
// (in native endianness) and immediately after that `count` elements of the array
// are encoded contiguously.
code_variable_length_array :: (slice: *[] u8, value: *Variable_Length_Array, $mode: Coding_Mode) -> ok: bool {
	size_of_count :: size_of(type_of(value.count));
	if slice.count < size_of_count return false;
	if mode == {
		case .ENCODE; memcpy(slice.data, *value.count, size_of_count);
		case .DECODE; memcpy(*value.count, slice.data, size_of_count);
	}
	advance(slice, size_of_count);

	size_of_elem :: size_of(type_of(value).T);
	if slice.count < value.count * size_of_elem return false;

	for 0..value.count-1 {
		if !code_polymorphic(slice, *value.data[it], mode) return false;
	}

	return true;
}

Variable_Length_Array :: struct(max_count: s32, T: Type) {
    count: s32;
    data: [max_count] T;
}

//
// }}} encoding/decoding
//

//
// array utils {{{
//

advance :: inline (a: *[] $T, count: s64) {
    assert(count >= 0);
    assert(a.count >= count);
    a.count -= count;
    a.data  += count;
}

is_equal :: inline (a: [$N] $T, b: [N] T) -> bool {
	for a {
		if b[it_index] != it return false;
	}
	return true;
}

//
// }}} array utils
//

//
// Reflection {{{
//

is_specialization_of :: (specific: Type, generic: Type) -> bool {
	ti_specific := cast(*Type_Info) specific;
	ti_generic := cast(*Type_Info) generic;
	if ti_specific.type != ti_generic.type || ti_specific.type != .STRUCT return false;

	tis_specific := cast(*Type_Info_Struct) specific;
	if tis_specific.polymorph_source_struct != xx generic return false;

	return true;
}

member_offset_in_bytes :: (type: Type, member: string) -> s32 {
	ti := cast(*Type_Info) type;
	assert(ti.type == .STRUCT);

	tis := cast(*Type_Info_Struct) type;
	for tis.members if it.name == member return xx it.offset_in_bytes;
	assert(false);
	return -1;
}

//
// }}} Reflection
//

//
// Mem_Dump {{{
//

Setup_Mem_Dump_Printer :: () #expand {
    old_struct_printer := context.print_style.struct_printer;
    `defer context.print_style.struct_printer = old_struct_printer;
    context.print_style.struct_printer = mem_dump_printer;
}

Mem_Dump :: #type,distinct [] u8;
mem_dump_printer :: (builder: *String_Builder, any: Any, data: *void) -> handled: bool {
    if any.type != type_info(Mem_Dump) return false;

    data := << cast(*[] u8) any.value_pointer;
    mem_dump_to_builder(builder, data);
    return true;
}

mem_dump_to_builder :: (builder: *String_Builder, data: [] u8) {
    old_default_format_int := context.print_style.default_format_int;
    defer context.print_style.default_format_int = old_default_format_int;
    context.print_style.default_format_int = FormatInt.{ base = 16, minimum_digits = 2 };

    leading_spaces := cast(s64) (cast(u64) data.data) % 16;
    start_addr := cast(* u8) (cast(u64) data.data) & 0xffff_ffff_ffff_fff0;

    print_to_builder(builder, "%: ", start_addr);
    for 0..(data.count + leading_spaces - 1) {
        if it < leading_spaces then
            append(builder, "  ");
        else
            print_to_builder(builder, "%", data[it - leading_spaces]);

        if (it + 1) % 16 == 0 && it + 1 != data.count + leading_spaces
            print_to_builder(builder, "\n%: ", start_addr + it + 1);
        else if (it + 1) % 4 == 0
            append(builder, " ");
    }
}

//
// }}} Mem_Dump
//

#scope_file
#if OS == .WINDOWS {
    ECONNRESET :: WSAECONNRESET;
    EISCONN :: WSAEISCONN;
    EALREADY :: WSAEALREADY;
    EINPROGRESS :: WSAEINPROGRESS;
} else {
    #import "POSIX";
}

#import "Socket";
#import "System";
