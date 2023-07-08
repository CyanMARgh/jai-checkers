#import "Basic";
// #poke_name Basic operator==;
#import,dir "../kscurses";
#import "Math";
#load "2diMatrix.jai";

// Rotations: 90, 180, 270, 0; with a shift to keep coords positive
player_rotations :: iMatrix3x2.[.{0,1,0,-1,0,1},.{-1,0,1,0,-1,1},.{0,-1,1,1,0,0},.{1,0,0,0,1,0}];

FOLLOW_PLAYERS :: 1;
rotate_to_player :: (using board_int : *Board_Interface, v : ivec2) -> ivec2 {
    player := player_me;
    if player == 4 #if !FOLLOW_PLAYERS {return v;} else {player = current_player;}
    return player_rotations[player] * ivec3.{v.x, v.y, diam-1};
}

rotate_to_board :: (using board_int : *Board_Interface, v : ivec2) -> ivec2 {
    player := player_me;
    if player == 4 #if !FOLLOW_PLAYERS {return v;} else {player = current_player;}
    return player_rotations[ifx player%2 then player else 2-player] * ivec3.{v.x, v.y, diam-1}; // same for 0 and 180, swapped for 90 and 270.
}


my_array_find :: (array: [] $T, item: T) -> bool, s64 {
	for array if it == item return true, it_index;
	return false, -1;
}

Rules :: struct {
	diam, cutoff, rows, rows_offset : s32 = 16, 4, 4, 0; 
	must_capture := false;
	diagonal := true;
	// _180_no_scope := false;
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
	type : enum u8 { NONE; INVALID; MOVE; CAPTURE; STEPEND; UPGRADE; };
	union {
		data_move : struct {
			from, to : ivec2;
		};
		data_capture : struct {
			from, to, dir : ivec2;
			killed : Cell;
		};
		data_upgrade : struct {
			pos : ivec2;
			bef, aft : Cell;
		};
		data_stepend : struct {
			player_old, player_new : int;
		};
	}
}
// 1) MOVE [, UPGRADE] STEPEND
// 2) CAPTURE [, UPGRADE], CAPTURE [, UPGRADE], CAPTURE [, UPGRADE] STEPEND
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
	// check if valid rules
	rules = _rules;
	cells = NewArray(diam * diam, Cell);
	i := 0;

	dist_and_boost_flag :: (using rules : *Rules, x : s32, y : s32) -> border_dist:s32, corner_dist:s32, Cell, dir_id:s32 {
		border_dist, dir_id : s32 = diam - 1 - x, 0;
		if diam - 1 - y < border_dist then border_dist, dir_id = diam - 1 - y, 1;
		if x < border_dist then border_dist, dir_id = x, 2;
		if y < border_dist then border_dist, dir_id = y, 3;
		
		corner_dist := max(min(x, diam - x - 1), min(y, diam - y - 1));
		
		boost := Cell.FIGURE_TYPE;
		if y >= x then boost &= .BLUE | .RED;
		if y <= x then boost &= .GREEN | .BLACK;
		if y + x >= diam - 1 then boost &= .BLUE | .BLACK;
		if x + y <= diam - 1 then boost &= .GREEN | .RED;

		return border_dist, corner_dist, boost, dir_id;
	}

	for y : 0..diam-1 {
		for x : 0..diam-1 {
			border_dist, corner_dist, flag, dir_id := dist_and_boost_flag(rules, x, y);
			cell : Cell; defer {
				cells[i] = cell;
				i += 1;
			}
			if corner_dist < cutoff {
				cell = .BORDER;
				continue;
			}
			if border_dist == 0 {
				cell |= flag << 8;
			}
			if border_dist >= rows_offset && border_dist < rows_offset + rows {
				if !diagonal || (x + y) % 2 == 0 {
					assert(flag == .BLACK || flag == .BLUE || flag == .RED || flag == .GREEN, tprint("flag = %, x = %, y = %\n", flag, x, y));
					cell |= flag;
					alive_count[dir_id] += 1;
				}
			}
		}
	}
}
deinit :: (using board : *Board) {
	array_free(cells);
	array_free(history);
}
// TODO cell_props :: struct {}
get_properties :: (cell : Cell, rules : *Rules) -> length:s32, capture_dirs:[4]ivec2, dirs:[4]ivec2 {
	length := ifx cell & .KING_ANY then rules.diam else 1;
	figure := cell & .FIGURE;
	if !figure return 0, .[.{},.{},.{},.{}], .[.{},.{},.{},.{}];

	capture_dirs, dirs : [4]ivec2;
	if rules.diagonal {
		capture_dirs, dirs = .[.{1, 1}, .{-1, 1}, .{1, -1}, .{-1, -1}];
		if !(cell & .KING_ANY) if figure == {
			case .BLACK; dirs[0], dirs[2] = .{}, .{};
			case .BLUE;  dirs[0], dirs[1] = .{}, .{};
			case .RED;   dirs[1], dirs[3] = .{}, .{};
			case .GREEN; dirs[2], dirs[3] = .{}, .{};
			case; assert(false);
		}
	} else {
		capture_dirs, dirs = .[.{-1, 0}, .{0, -1}, .{1, 0}, .{0, 1}];
		if !(cell & .KING_ANY) if figure == {
			case .BLACK; dirs[2] = .{};
			case .BLUE;  dirs[3] = .{};
			case .RED;   dirs[0] = .{};
			case .GREEN; dirs[1] = .{};
			case; assert(false);
		}
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
get_player_by_code :: (cell : Cell) -> int {
	if cell & .FIGURE_TYPE == {
		case .BLACK; return 0;
		case .BLUE; return 1;
		case .RED; return 2;
		case .GREEN; return 3;
		case .EMPTY; return 4;
	}
	assert(false);
	return 5;
}
upgrade :: (c : Cell) -> Cell {
	return c | (((c & .BOOSTS) >> 4) & ~((c & .FIGURE_TYPE) << 4));
}

gen_step_move :: (using board : *Board, from : ivec2, to : ivec2) -> Step {
	return .{type = .MOVE, data_move = .{from = from, to = to}};
}

gen_step_capture :: (using board : *Board, from : ivec2, to : ivec2, dir : ivec2) -> Step {
	killed := at(board, to - dir);
	return .{type = .CAPTURE, data_capture = .{from = from, to = to, dir = dir, killed = killed}};
}
gen_step_upgrade :: (using board : *Board, pos : ivec2) -> Step {
	c := at(board, pos);
	c_aft := upgrade(c);
	return .{type = ifx c == c_aft then .NONE else .UPGRADE, data_upgrade = .{pos = pos, bef = c, aft = c_aft}};
}
gen_step_end :: (using board : *Board) -> Step {
	player_old, player_new := current_player;
	while 1 {
		player_new = (player_new + 1) % 4;
		if alive_count[player_new] break;
	}
	return .{type = .STEPEND, data_stepend = .{player_old = player_old, player_new = player_new}};
}

apply :: (using board : *Board, step : Step) {
	if #complete step.type == {
		case .MOVE; using step.data_move; 
		c1, c2 := at_ptr(board, from), at_ptr(board, to);
		<<c2 |= <<c1 & .FIGURE;
		<<c1 &= .BOARD_PROPS;

		case .CAPTURE; using step.data_capture;
		c1, c2, c3 := at_ptr(board, from), at_ptr(board, to), at_ptr(board, to - dir);
		<<c2 |= <<c1 & .FIGURE;
		<<c1 &= .BOARD_PROPS;

		killed_player := get_player_by_code(<<c3);
		assert(killed_player != 4);
		alive_count[killed_player] -= 1;

		<<c3 &= .BOARD_PROPS;
		active_figure = to;
		last_capture_dir = dir;

		case .UPGRADE; using step.data_upgrade;
		<<at_ptr(board, pos) = aft;

		case .STEPEND; using step.data_stepend;
		active_figure = .{-1, -1};
		last_capture_dir = .{};
		current_player = player_new;

		case .INVALID;
		assert(false);
		case .NONE;
		assert(false);
	}
	array_add(*(board.history), step);
}

get_last_step_view :: (using board : *Board) -> []Step {
	tail_count := history.count;
	if !tail_count return .[];
	tail_count -= 1;
	while true {
		if tail_count == 0 || history[tail_count - 1].type == .STEPEND break;
		tail_count -= 1;
	}

	view : []Step;
	view.count = history.count - tail_count;
	view.data = history.data + tail_count;
	return view;
}

// undo_single :: (using board : *Board) {
// 	// step := pop(history);
// 	//===
// }
// undo_full :: (board : *Board) {
// 	//===
// }

move :: (using board : *Board, from : ivec2, to : ivec2) {
	step := gen_step_move(board, from, to);
	apply(board, step);
	step2 := gen_step_upgrade(board, to);
	if step2.type == .UPGRADE then apply(board, step2);
}
capture :: (using board : *Board, from : ivec2, to : ivec2, dir : ivec2) {
	step := gen_step_capture(board, from, to, dir);
	apply(board, step);
	step2 := gen_step_upgrade(board, to);
	if step2.type == .UPGRADE then apply(board, step2);
}

end_step :: (using board : *Board) {
	step := gen_step_end(board);
	apply(board, step);
}

try_step :: (using board : *Board, from : ivec2, to : ivec2) -> enum u8 {NONE; MOVE; CAPTURE; ENDSEQ;} {
	ready_for_move :: (board : *Board, from : ivec2, length : s32, max_length : s32, dir : ivec2, move_dirs : [4]ivec2) -> bool {
		if length < 1 || length > max_length || !my_array_find(move_dirs, dir) then return false;
		for i : 1..length if is_obstacle(at(board, from + dir * i)) return false;
		return true;
	}
	ready_for_capture :: (board : *Board, from : ivec2, length : s32, max_length : s32, dir : ivec2, capture_dirs : [4]ivec2) -> bool {
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

	if active_figure != .{-1, -1} then {
		if from != active_figure then return .NONE;

		if length == 0 {
			end_step(board);
			return .ENDSEQ;
		}
		if dir != .{} && dir != -last_capture_dir && ready_for_capture(board, from, length, max_length, dir, capture_dirs) {
			capture(board, from, to, dir);
			return .CAPTURE;
		}
	} else {
		if dir == .{} return .NONE;
		if !should_current_player_capture(board) && ready_for_move(board, from, length, max_length, dir, move_dirs) {
			move(board, from, to);
			end_step(board);
			return .MOVE;
		}
		if ready_for_capture(board, from, length, max_length, dir, capture_dirs) {
			capture(board, from, to, dir);
			return .CAPTURE;
		}
	}
	return .NONE;
}

what_can_do :: (using board : *Board, pos : ivec2) -> can_capture:bool, can_move:bool {
	cell := at(board, pos);
	assert(!!(cell & .FIGURE_TYPE));
	length, capture_dirs, move_dirs := get_properties(cell, rules);
	assert(length > 0);

	can_capture := false;
	can_move := false;

	for dir : capture_dirs {
		if dir == .{} || dir == -last_capture_dir continue;
		obstacle_dist := -1;
		obstacle : Cell;
		for i : 1..length {
			obstacle = at(board, pos + dir * i);
			if is_obstacle(obstacle) {
				obstacle_dist = i;
				break;
			}
		}
		if obstacle_dist == -1 continue;
		if is_enemies(obstacle, cell) && !is_obstacle(at(board, pos + dir * cast(s32)(obstacle_dist + 1))) {
			can_capture = true;
			break;
		}
	}
	for dir : move_dirs {
		if !is_obstacle(at(board, pos + dir)) {
			can_move = true;
			break;
		}
	}

	return can_capture, can_move;
}
what_can_do :: (using board : *Board, player : int) -> can_capture:bool, can_move:bool {
	player_flag : Cell = xx(0x0001 << player);

	can_capture, can_move : bool;
	i := 0;
	for y : 0..diam-1 {
		for x : 0..diam-1 {
			defer i += 1;
			cell := cells[i];
			if !(cell & player_flag) continue;
			can_capture_f, can_move_f := what_can_do(board, .{xx x, xx y});
			can_capture |= can_capture_f;
			can_move |= can_move_f;

			if can_move && can_capture return true, true;
		}
	}
	return can_capture, can_move;
}
should_current_player_capture :: (using board : *Board) -> bool {
	can_capture, can_move := what_can_do(board, current_player);
	return must_capture && can_capture;
}
is_final :: (using board : *Board) -> bool, winner:int {
	alive, winner := 0, 4;
	for alive_count {
		if it > 0 {
			winner = it;
			alive += 1;
		}
	}
	assert(alive > 0);
	return alive == 1, winner;
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
		can_capture, can_move := what_can_do(board, cursor);
		if (should_current_player_capture(board) || !can_move) && !can_capture return;
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

			case .CAPTURE;
			selected = cursor;
			can_capture, can_move := what_can_do(board, selected);
			if !can_capture {
				click(board_interface);
			}
		}
	}
}
