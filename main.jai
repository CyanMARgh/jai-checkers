#import "Basic";
// #poke_name Basic operator==;
#import,dir "../kscurses";
#import "Math";

my_array_find :: (array: [] $T, item: T) -> bool, s64 {
	for array if it == item return true, it_index;
	return false, -1;
}

Rules :: struct {
	diam, cutoff : s32 = 16, 4; 
	// must_capture := false;
	// diagonal := true;
	// no_scope_180 := false;
	// upgrade_in_process := true;
	// leveled_upgrade := false;
	// length_by_level := s32.[1, 2, 4, 8];
	// enable_border := false;
	// border_period := 20;
}
Cell :: enum_flags u16 {
	BLACK		:: 0x0001;
	BLUE		:: 0x0002;
	RED			:: 0x0004;
	GREEN		:: 0x0008;

	KING_BLACK	:: 0x0010;
	KING_BLUE	:: 0x0020;
	KING_RED	:: 0x0040;
	KING_GREEN	:: 0x0080;

	BOOST_BLACK	:: 0x0100;
	BOOST_BLUE	:: 0x0200;
	BOOST_RED	:: 0x0400;
	BOOST_GREEN	:: 0x0800;

	BORDER		:: 0x1000;

	EMPTY		:: 0x0000;
	FIGURE_TYPE :: 0x000F;
	KING_ANY	:: 0x00F0;
	BOOSTS		:: 0x0F00;
	FIGURE		:: 0x00FF;
	BOARD_PROPS :: 0xFF00;
	OBSTACLE	:: 0xF0FF;
}

Step :: struct {
	type : enum u8 { MOVE; KILL; STEPEND; UPGRADE; };
	pos, to : ivec2;
	bef, aft : Cell;
}
// 1) MOVE [, UPGRADE] STEPEND
// 2) MOVE & KILL [, UPGRADE], MOVE & KILL [, UPGRADE], MOVE & KILL [, UPGRADE] STEPEND
Board :: struct {
	using rules : *Rules;

	cells : []Cell;
	alive_count : [4]int;
	current_player := 0;

	history : [..]Step;

	active_figure := ivec2.{-1, -1};
	last_capture_dir := ivec2.{0, 0};
}

at_ptr :: (using board : *Board, pos : ivec2) -> *Cell {
	assert(pos.x >= 0 && pos.x < diam && pos.y >= 0 && pos.y < diam);
	return *(cells[pos.x + diam * pos.y]);
}
at :: (using board : *Board, pos : ivec2) -> Cell {
	if pos.x < 0 || pos.x >= diam || pos.y < 0 || pos.y >= diam then return .BORDER;
	return cells[pos.x + diam * pos.y];
}
init :: (using board : *Board, _rules : *Rules) {
	rules = _rules;
	cells = NewArray(diam * diam, Cell);
	i := 0;
	for y : 0..diam-1 {
		for x : 0..diam-1 {
			cell : Cell;
			if (x < cutoff || x >= diam - cutoff) && (y < cutoff || y >= diam - cutoff) {
				cell = .BORDER;
			} else {
				if (x + y) % 2 {
					cell = .EMPTY;
				} else if y >= diam - cutoff {
					cell = .BLUE; alive_count[1] += 1;
				} else if x >= diam - cutoff {
					cell = .BLACK; alive_count[0] += 1;
				} else if y < cutoff {
					cell = .GREEN; alive_count[3] += 1;
				} else if x < cutoff {
					cell = .RED; alive_count[2] += 1;
				}

				if y == diam - 1 {
					cell |= .BOOST_GREEN;
				} else if x == diam - 1 {
					cell |= .BOOST_BLACK;
				} else if y == 0 {
					cell |= .BOOST_BLUE;
				} else if x == 0 {
					cell |= .BOOST_RED;
				}				
			}
			cells[i] = cell;
			i += 1;
		}
	}
}
deinit :: (using board : *Board) {
	array_free(cells);
}
// TODO cell_props :: struct {}
get_properties :: (cell : Cell, rules : *Rules) -> length:s32, capture_dirs:[4]ivec2, dirs:[4]ivec2 {
	capture_dirs, dirs : [4]ivec2 = .[.{1, 1}, .{-1, 1}, .{1, -1}, .{-1, -1}];
	length := ifx cell & .KING_ANY then rules.diam else 1;
	figure := cell & .FIGURE;
	if !figure return 0, .[.{},.{},.{},.{}], .[.{},.{},.{},.{}];
	if !(cell & .KING_ANY) if figure == {
		case .BLACK; dirs[0], dirs[2] = .{}, .{};
		case .BLUE;  dirs[0], dirs[1] = .{}, .{};
		case .RED;   dirs[1], dirs[3] = .{}, .{};
		case .GREEN; dirs[2], dirs[3] = .{}, .{};
		case; assert(false);
	}
	return xx length, capture_dirs, dirs;
}
get_dir_and_length :: (from : ivec2, to : ivec2) -> ivec2, s32 {
	abs_and_sign :: inline (x : s32) -> s32, s32 {
		if x > 0 return x, 1; 
		if x < 0 return -x, -1;
		return 0, 0;
	}
	diff := to - from;
	ax, sx := abs_and_sign(diff.x);
	ay, sy := abs_and_sign(diff.y);
	return (ifx (!ax || !ay || ax == ay) then ivec2.{sx, sy} else ivec2.{}), max(ax, ay);
}
is_obstacle :: inline (cell : Cell) -> bool { return xx(cell & .OBSTACLE); }
is_enemies :: inline (c1 : Cell, c2 : Cell) -> bool { 
	c1 &= .FIGURE_TYPE;
	c2 &= .FIGURE_TYPE;
	return !(c1 & c2) && c1 && c2;
}
is_owned_by :: (cell : Cell, player : int) -> bool { return xx ((0x0001 << player) & cast(int)cell); }
maybe_upgrade :: (using board : *Board, pos : ivec2) {
	cell := at_ptr(board, pos);
	<<cell |= ((<<cell & .BOOSTS) >> 4) & ~((<<cell & .FIGURE_TYPE) << 4);
}
upgrade :: (c : Cell) -> Cell {
	return c | (((c & .BOOSTS) >> 4) & ~((c & .FIGURE_TYPE) << 4));
}
move :: (using board : *Board, from : ivec2, to : ivec2) {
	c1, c2 := at_ptr(board, from), at_ptr(board, to);
	assert(xx (<<c1 & .FIGURE));
	assert(!(<<c2 & .FIGURE));

	<<c2 |= <<c1 & .FIGURE;
	<<c1 &= .BOARD_PROPS;

	<<c2 = upgrade(<<c2);
}
kill :: (using board : *Board, pos : ivec2) {
	c := at_ptr(board, pos);
	assert(xx(<<c & .FIGURE_TYPE));
	<<c &= .BOARD_PROPS;
}

end_step :: (using board : *Board) {
	current_player = (current_player + 1) % 4;
	active_figure = .{-1, -1};
	last_capture_dir = .{};
}

try_step :: (using board : *Board, from : ivec2, to : ivec2) -> enum u8 {NONE; MOVE; KILL; ENDSEQ;} {
	ready_for_move :: (board : *Board, from : ivec2, length : s32, max_length : s32, dir : ivec2, move_dirs : [4]ivec2) -> bool {
		if length < 1 || length > max_length || !my_array_find(move_dirs, dir) then return false;
		for i : 1..length if is_obstacle(at(board, from + dir * i)) return false;
		return true;
	}
	ready_for_kill :: (board : *Board, from : ivec2, length : s32, max_length : s32, dir : ivec2, capture_dirs : [4]ivec2) -> bool {
		if length <= 1 || length > max_length + 1 || !my_array_find(capture_dirs, dir) then return false;
		for i : 1..length {
			pos := from + dir * i;
			if i == length-1 {
				if !is_enemies(at(board, pos), at(board, from)) return false;
			} else {
				if is_obstacle(at(board, pos)) return false;
			}
		}
		return true;
	}

	dir, length := get_dir_and_length(from, to);
	cell := at(board, from);
	max_length, capture_dirs, move_dirs := get_properties(cell, rules);

	if !is_owned_by(cell, current_player) return .NONE;
	capture :: (using board : *Board, from : ivec2, to : ivec2, dir : ivec2) {
		move(board, from, to);
		kill(board, to - dir);
		active_figure = to;
		last_capture_dir = dir;
	}

	if active_figure != .{-1, -1} then {
		if from != active_figure then return .NONE;

		if length == 0 {
			end_step(board);
			return .ENDSEQ;
		}
		if dir != .{} && dir != -last_capture_dir && ready_for_kill(board, from, length, max_length, dir, capture_dirs) {
			capture(board, from, to, dir);
			return .KILL;
		}
	} else {
		if dir == .{} return .NONE;
		if ready_for_move(board, from, length, max_length, dir, move_dirs) {
			move(board, from, to);
			end_step(board);
			return .MOVE;
		}
		if ready_for_kill(board, from, length, max_length, dir, capture_dirs) {
			capture(board, from, to, dir);
			return .KILL;
		}
	}
	return .NONE;
}

// can_kill :: (board : *Board, at : ivec2) -> bool {
// 	//===
// }
// can_kill :: (board : *Board, player : int) -> bool {
// 	//===
// }
// undo_single :: (board : *Board) {
// 	//===
// }
// undo_full :: (board : *Board) {
// 	//===
// }
is_final :: (using board : *Board) -> bool {
	alive := 0;
	for alive_count { alive += xx!!it;}
	assert(alive > 0);
	return alive == 1;
}

Board_Interface :: struct {
	using board : *Board;
	player_me := 4;

	selected := ivec2.{-1, -1};
	cursor := ivec2.{0, 0};
}
click :: (using board_interface : *Board_Interface) {
	if player_me != 4 && player_me != current_player return;

	if selected == .{-1, -1} then {
		if !is_owned_by(at(board, cursor), current_player) return;
		selected = cursor;
	} else {
		result := try_step(board, selected,	cursor);
		if result == {
			case .NONE;
			if selected == cursor {
				selected = .{-1, -1};
			} else if is_owned_by(at(board, cursor), current_player) {
				selected = cursor;
			}

			case .MOVE;
			selected = .{-1, -1};

			case .ENDSEQ;
			selected = .{-1, -1};

			case .KILL;
			selected = cursor;
		}
	}
}
handle_key_board_interface :: (using board_interface : *Board_Interface, key : Key) {
	if key == {
		case .ENTER;
		if !is_final(board) click(board_interface);

		case #char"i";
		cell := at(board, cursor);
		length, capture_dirs, dirs := get_properties(cell, rules);
		log("%: cell:%, length:%, capture dirs:%, move dirs:%\n", cursor, cell, length, capture_dirs, dirs);
	}
	dir := arrow_code_to_ivec2(key);
	cursor += dir;
	Clamp(*cursor.x, 0, diam - 1);
	Clamp(*cursor.y, 0, diam - 1);
}

c_draw_board :: (canvas : *Canvas, using board_interface : Board_Interface, offset : ivec2, show_cursor : bool) {
	i := 0;
	for y_c : 0..diam-1 {
		for x_c : 0..2*diam-1 {
			x := x_c / 2;
			x_l := x_c % 2;
			y := y_c;

			pos_c := ivec2.{xx x_c, xx y_c};
			pos := ivec2.{xx x, xx y};
			cell := at(board, pos);

			background : Color = 
				ifx pos == cursor && show_cursor then .BRIGHT_YELLOW else 
				ifx pos == selected then .BRIGHT_MAGENTA else 
				ifx cell & .BORDER then .BLACK else
				ifx (x + y) % 2 then .WHITE else
				.BRIGHT_WHITE;
			foreground : Color =
				ifx cell & .BLACK then .BLACK else
				ifx cell & .BLUE then .BRIGHT_BLUE else
				ifx cell & .RED then .RED else
				ifx cell & .GREEN then .GREEN else 
				.BRIGHT_MAGENTA;
			code :=
				ifx x_l != 0 then #run utf8(" ") else
				ifx cell & .KING_ANY then #run utf8("@") else
				ifx cell & .FIGURE then #run utf8("*") else
				#run utf8(" ");

			c_putchar(canvas, make_char(code, background = background, foreground = foreground), offset + pos_c);
			i += 1;
		}
	}
}

main :: () {
	init_game(); defer deinit_game();
	__event_handler.proc = (e : Event, __data : *void) {
		if e.type == {
			case .KEY;
			if e.key == {
				case .ESCAPE; stop_main = true;
			}
			handle_key_board_interface(*board_interface, e.key);
			blink_state = true;
			restart_clock_cycle();

			case .TICK;		
			blink_state = !blink_state;
		}
	};

	use_ks_curses();
	use_events(tick_duration_ms = 530);

	// log("%", board);

	draw_game();
	while !stop_main {
		if wait_and_process_events() {
			draw_game();
			reset_temporary_storage();
		}
	}
}

#scope_file

rules := Rules.{diam = 12, cutoff = 2};
board : Board;
board_interface : Board_Interface;
main_canvas : Canvas;
stop_main : bool;
blink_state := true;

init_game :: () {
	board_interface.board = *board;
	board.rules = *rules;

	init(*board, *rules);
}
deinit_game :: () {
	deinit(*board);
	deinit(*main_canvas);
}
draw_game :: () {
	resize_clear(*main_canvas, .{size = terminal_state.size}, make_char(#char" ", background = .BLACK));
	c_draw_board(*main_canvas, *board_interface, .{0, 0}, blink_state);
	ks_draw_canvas(*main_canvas);
}