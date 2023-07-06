#import "Basic";
// #poke_name Basic operator==;
#import,dir "../kscurses";
#import "Math";

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
kill :: (using board : *Board, pos : ivec2) {
	c := at_ptr(board, pos);
	player := get_player_by_code(<<c);
	assert(player != 4);
	alive_count[player] -= 1;
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
		if !should_current_player_kill(board) && ready_for_move(board, from, length, max_length, dir, move_dirs) {
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

can_kill :: (using board : *Board, pos : ivec2) -> bool {
	// log("can_kill:\n");
	cell := at(board, pos);
	assert(!!(cell & .FIGURE_TYPE));
	length, capture_dirs, dirs := get_properties(cell, rules);
	assert(length > 0);

	for dir : capture_dirs {
		// log("dir = %\n", dir);
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
		if is_enemies(obstacle, cell) && !is_obstacle(at(board, pos + dir * cast(s32)(obstacle_dist + 1))) then return true;
	}
	return false;
}
// check_possible_steps :: (using board : *Board, pos : ivec2, $check_move : bool, $check_kill : bool) -> kill:bool, move:bool {
// 	//======
// }
can_kill :: (using board : *Board, player : int) -> bool {
	player_flag : Cell = xx(0x0001 << player);
	i := 0;
	for y : 0..diam-1 {
		for x : 0..diam-1 {
			defer i += 1;
			cell := cells[i];
			if !(cell & player_flag) continue;
			if can_kill(board, .{xx x, xx y}) return true;
		}
	}
	return false;
}
should_current_player_kill :: (using board : *Board) -> bool {
	return must_capture && can_kill(board, current_player);
}
// undo_single :: (board : *Board) {
// 	//===
// }
// undo_full :: (board : *Board) {
// 	//===
// }
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
