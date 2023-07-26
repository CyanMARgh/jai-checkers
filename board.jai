#import "Basic";
// #poke_name Basic operator==;
using,except(Color) KS :: #import,dir "../kscurses";
#import "Math";

my_array_find :: (array: [] $T, item: T) -> bool, s64 {
	for array if it == item return true, it_index;
	return false, -1;
}

Rules :: struct {
	diam, cutoff, rows, rows_offset : s32 = 16, 4, 4, 0; 
	must_capture := false;
	diagonal := true;
	_180_no_scope := false;
	leveled_upgrade := false;
	backward_capture := true;
	length_by_level := s32.[1, 2, 4, 8];
	// upgrade_in_process := true;
	enable_border := false;
	border_period := 20;
}
RULES_RUSSIAN :: Rules.{must_capture = true};
RULES_CLASSIC :: Rules.{diagonal = false, leveled_upgrade = true, rows_offset = 1, rows = 2};
RULES_DEBUG :: Rules.{must_capture = true, diagonal = false, leveled_upgrade = true, rows_offset = 1, rows = 1, diam = 8, cutoff = 2};

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
	type : enum u8 { NONE; INVALID; MOVE; CAPTURE; BORDER; ADDBOOST; STEPEND; UPGRADE; };
	union {
		data_move : struct {
			from, to : ivec2;
		};
		data_capture : struct {
			from, to, dir : ivec2;
			killed : Cell;
		};
		data_border : struct {
			pos : ivec2;
			bef : Cell;
		}
		data_upgrade : struct {
			pos : ivec2;
			bef, aft : Cell;
		};
		data_stepend : struct {
			player_old, player_new : int;
		};
		data_addboost : struct {
			pos : ivec2;
			bef, aft : Cell;			
		}
	}
}
// 1) MOVE [, UPGRADE] STEPEND
// 2) CAPTURE [, UPGRADE], CAPTURE [, UPGRADE], CAPTURE [, UPGRADE] STEPEND
Board :: struct {
	using rules : Rules;

	cells : []Cell;
	alive_count : [4]int;
	current_player := 0;

	history : [..]Step;
	uncommited_count := 0;

	step_id := 0;

	active_figure := ivec2.{-1, -1};
	last_capture_dir := ivec2.{0, 0};
}
at_ptr :: (using board : *Board, pos : ivec2) -> *Cell {
	assert(pos.x >= 0 && pos.x < diam && pos.y >= 0 && pos.y < diam);
	return *(cells[pos.x + diam * pos.y]);
}
at :: (using board : Board, pos : ivec2) -> Cell {
	if pos.x < 0 || pos.x >= diam || pos.y < 0 || pos.y >= diam then return .BORDER;
	return cells[pos.x + diam * pos.y];
}
init :: (using board : *Board) {
	// check if valid rules
	cells = NewArray(diam * diam, Cell);
	i := 0;

	dist_and_boost_flag :: (using rules : Rules, x : s32, y : s32) -> border_dist:s32, corner_dist:s32, Cell, dir_id:s32 {
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
cell_level :: (cell : Cell) -> u8 {
	assert(!!(cell & .FIGURE_TYPE));
	level_table :: u8.[
		0, 1, 1, 2,
		1, 2, 2, 3,
		1, 2, 2, 3,
		2, 3, 3
	];
	return level_table[(cell & .KING_ANY) >> 4];
}
get_properties :: (cell : Cell, rules : Rules) -> length:s32, capture_dirs:[4]ivec2, dirs:[4]ivec2 {
	figure_type := cell & .FIGURE_TYPE;
	figure_boosts := cell & .KING_ANY;
	if !figure_type return 0, .[.{},.{},.{},.{}], .[.{},.{},.{},.{}];

	length : s32;
	if rules.leveled_upgrade {
		length = rules.length_by_level[cell_level(cell)];
	} else {
		length = ifx cell & .KING_ANY then rules.diam else 1;
	}

	capture_dirs, dirs : [4]ivec2;
	if rules.diagonal {
		capture_dirs, dirs = .[.{1, 1}, .{-1, 1}, .{1, -1}, .{-1, -1}];
		if !figure_boosts if figure_type == {
			case .BLACK; dirs[0], dirs[2] = .{}, .{};
			case .BLUE;  dirs[0], dirs[1] = .{}, .{};
			case .RED;   dirs[1], dirs[3] = .{}, .{};
			case .GREEN; dirs[2], dirs[3] = .{}, .{};
			case; assert(false);
		}
	} else {
		capture_dirs, dirs = .[.{-1, 0}, .{0, -1}, .{1, 0}, .{0, 1}];
		if !figure_boosts if figure_type == {
			case .BLACK; dirs[2] = .{};
			case .BLUE;  dirs[3] = .{};
			case .RED;   dirs[0] = .{};
			case .GREEN; dirs[1] = .{};
			case; assert(false);
		}
	}
	if !rules.backward_capture then capture_dirs = dirs;
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
	c2 := c | (((c & .BOOSTS) >> 4) & ~((c & .FIGURE_TYPE) << 4));
	// if c2 != c log("c = %, c2 = %\n", c, c2);
	return c2;
}
gen_step_move :: (using board : Board, from : ivec2, to : ivec2) -> Step {
	return .{type = .MOVE, data_move = .{from = from, to = to}};
}
gen_step_capture :: (using board : Board, from : ivec2, to : ivec2, dir : ivec2) -> Step {
	killed := at(board, to - dir) & .FIGURE;
	return .{type = .CAPTURE, data_capture = .{from = from, to = to, dir = dir, killed = killed}};
}
gen_step_upgrade :: (using board : Board, pos : ivec2) -> Step {
	c := at(board, pos);
	c_aft := upgrade(c);
	return .{type = ifx c == c_aft then .NONE else .UPGRADE, data_upgrade = .{pos = pos, bef = c, aft = c_aft}};
}

get_next_player :: (using board : Board) -> int {
	for i : 1..4 {
		p := (current_player + i) % 4;
		if alive_count[p] > 0 {
			can_kill, can_move := what_can_do(board, p, true);
			if can_kill || can_move return p;
		}
	}
	return 4;
}

gen_step_end :: (using board : Board) -> Step {
	return .{type = .STEPEND, data_stepend = .{
		player_old = current_player,
		player_new = get_next_player(board)
	}};
}

apply :: (using board : *Board, step : Step) {
	if #complete step.type == {
		case .MOVE; using step.data_move; 
		c1, c2 := at_ptr(board, from), at_ptr(board, to);
		c2.* |= c1.* & .FIGURE;
		c1.* &= .BOARD_PROPS;

		case .CAPTURE; using step.data_capture;
		c1, c2, c3 := at_ptr(board, from), at_ptr(board, to), at_ptr(board, to - dir);
		c2.* |= c1.* & .FIGURE;
		c1.* &= .BOARD_PROPS;

		killed_player := get_player_by_code(c3.*);
		assert(killed_player != 4);
		alive_count[killed_player] -= 1;

		c3.* &= .BOARD_PROPS;
		active_figure = to;
		last_capture_dir = dir;

		case .UPGRADE; using step.data_upgrade;
		at_ptr(board, pos).* = aft;

		case .STEPEND; using step.data_stepend;
		active_figure = .{-1, -1};
		last_capture_dir = .{};
		current_player = player_new;
		step_id += 1;

		case .BORDER; using step.data_border;
		p := get_player_by_code(bef);
		if p != 4 then alive_count[p] -= 1;
		at_ptr(board, pos).* = .BORDER;

		case .ADDBOOST; using step.data_addboost;
		at_ptr(board, pos).* = aft;
		// log("addboost: pos = %, bef = %, aft = %\n", pos, bef, aft);

		case .INVALID; assert(false);
		case .NONE; assert(false);
	}
}

apply_and_write :: (using board : *Board, step : Step) {
	assert(uncommited_count == 0);
	apply(board, step);
	array_add(*(board.history), step);
}

get_last_step_view :: (using board : Board) -> []Step {
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

undo_single :: (using board : *Board) {
	assert(history.count > 0);
	uncommited_count += 1;
	step := history[history.count - uncommited_count];

	update_dir_and_active_figure :: (using board : *Board) {
		if history.count > uncommited_count {			
			prev_step := history[history.count - uncommited_count - 1];
			if prev_step.type == .CAPTURE {
				last_capture_dir = prev_step.data_capture.dir;
				active_figure = prev_step.data_capture.to;				
			}
		}
	}

	if #complete step.type == {
		case .MOVE; using step.data_move; 
		c1, c2 := at_ptr(board, from), at_ptr(board, to);
		c1.* |= c2.* & .FIGURE;
		c2.* &= .BOARD_PROPS;

		case .CAPTURE; using step.data_capture;
		c1, c2, c3 := at_ptr(board, from), at_ptr(board, to), at_ptr(board, to - dir);
		c1.* |= c2.* & .FIGURE;
		c2.* &= .BOARD_PROPS;

		killed_player := get_player_by_code(killed);
		assert(killed_player != 4);
		alive_count[killed_player] += 1;

		c3.* |= killed;
		active_figure = .{-1, -1};
		last_capture_dir = .{0, 0};

		case .UPGRADE; using step.data_upgrade;
		at_ptr(board, pos).* = bef;

		case .STEPEND; using step.data_stepend;
		assert(active_figure == .{-1, -1});
		assert(last_capture_dir == .{0, 0});
		current_player = player_old;
		step_id -= 1;

		case .BORDER; using step.data_border;
		c := at_ptr(board, pos);
		p := get_player_by_code(bef);
		if p != 4 then alive_count[p] += 1;
		c.* = bef;

		case .ADDBOOST; using step.data_addboost;
		at_ptr(board, pos).* = bef;

		case .INVALID; assert(false);
		case .NONE; assert(false);
	} 
	update_dir_and_active_figure(board);
}
redo_single :: (using board : *Board) {
	step := history[history.count - uncommited_count];
	uncommited_count -= 1;
	apply(board, step);
}
get_step_to_animate :: (using board : Board) -> Step {
	assert(uncommited_count <= history.count && uncommited_count >= 0);
	if uncommited_count == 0 return .{type = .NONE};
	return history[history.count - uncommited_count];
}

move :: (using board : *Board, from : ivec2, to : ivec2) -> nodes:int {
	nodes := 1;
	step := gen_step_move(board, from, to);
	apply_and_write(board, step);
	step2 := gen_step_upgrade(board, to);
	if step2.type == .UPGRADE {
		apply_and_write(board, step2);
		nodes += 1;
	}
	return nodes;
}
capture :: (using board : *Board, from : ivec2, to : ivec2, dir : ivec2) -> nodes:int {
	nodes := 1;
	step := gen_step_capture(board, from, to, dir);
	apply_and_write(board, step);
	step2 := gen_step_upgrade(board, to);
	if step2.type == .UPGRADE {
		apply_and_write(board, step2);
		nodes += 1;
	}
	return nodes;
}
Ring :: struct {diam : s32; offset : s32; double_corners : bool; }
for_expansion :: (using ring : Ring, body : Code, flags : For_Flags) #expand {
	`it, `forward : ivec2;
	`it_index := 0; `color_flag : Cell;
	L := diam - 2 * offset - 2 + cast(s32)double_corners;


	`forward = .{-1, 0}; `color_flag = .BLACK;
	for i : 0..L {
		`it = .{diam - offset - 1, offset + i};
		`it_index += 1; #insert body;
	}
	`forward = .{0, -1}; `color_flag = .BLUE;
	for i : 0..L {
		`it = .{diam - offset - 1 - i, diam - offset - 1};
		`it_index += 1; #insert body;
	}
	`forward = .{1, 0}; `color_flag = .RED;
	for i : 0..L {
		`it = .{offset, diam - offset - 1 - i};
		`it_index += 1; #insert body;
	}
	`forward = .{0, 1}; `color_flag = .GREEN;
	for i : 0..L {
		`it = .{offset + i, offset};
		`it_index += 1; #insert body;
	}
}

gen_apply_and_write_board_nodes :: (using board : *Board) -> nodes:int {
	assert(enable_border);
	nodes := 0;	
	si := step_id + 1;

	if si % border_period == 0 {
		H := si / border_period - 1;
		assert(H * 2 <= diam);
		for Ring.{xx diam, xx H, false} {
			cell := at(board, it);
			if cell != .BORDER {
				apply_and_write(board, .{type = .BORDER, data_border = .{pos = it, bef = cell}});
				nodes += 1;
			}
		}
		for Ring.{xx diam, xx (H + 1), true} {
			cell := at(board, it);
			if cell != .BORDER {
				apply_and_write(board, .{type = .ADDBOOST, data_addboost = .{pos = it, bef = cell, aft = cell | (color_flag << 8)}});
				nodes += 1;
				if at(board, it) & .FIGURE {
					step_upgrade := gen_step_upgrade(board, it);
					if step_upgrade.type != .NONE {
						apply_and_write(board, step_upgrade);
						nodes += 1;
					}					
				}
			}
		}
	}
	return nodes;
}

end_step :: (using board : *Board) -> nodes:int {
	nodes := 1;
	if enable_border {
		nodes += gen_apply_and_write_board_nodes(board);
	}
	s := gen_step_end(board);
	apply_and_write(board, s);
	return nodes;
}

try_step :: (using board : *Board, from : ivec2, to : ivec2) -> enum u8 {NONE; MOVE; CAPTURE; ENDSEQ;}, nodes : int {
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

	nodes := 0;

	dir, length := get_dir_and_length(from, to);
	cell := at(board, from);
	max_length, capture_dirs, move_dirs := get_properties(cell, rules);

	if !is_owned_by(cell, current_player) return .NONE, nodes;

	if active_figure != .{-1, -1} then {
		if from != active_figure then return .NONE, nodes;

		if length == 0 {
			nodes += end_step(board);
			return .ENDSEQ, nodes;
		}
		if dir != .{} && (_180_no_scope || dir != -last_capture_dir) && ready_for_capture(board, from, length, max_length, dir, capture_dirs) {
			nodes += capture(board, from, to, dir);
			return .CAPTURE, nodes;
		}
	} else {
		if dir == .{} return .NONE, nodes;
		if !should_current_player_capture(board) && ready_for_move(board, from, length, max_length, dir, move_dirs) {
			nodes += move(board, from, to);
			nodes += end_step(board);
			return .MOVE, nodes;
		}
		if ready_for_capture(board, from, length, max_length, dir, capture_dirs) {
			nodes += capture(board, from, to, dir);
			return .CAPTURE, nodes;
		}
	}
	return .NONE, nodes;
}

what_can_do :: (using board : Board, pos : ivec2, ignore_active_figure := false) -> can_capture:bool, can_move:bool {
	cell := at(board, pos);
	assert(ignore_active_figure || active_figure == .{-1, -1} || active_figure == pos, "pos = %, active_figure = %", pos, active_figure);
	assert(!!(cell & .FIGURE_TYPE), "cell = %", cell);

	length, capture_dirs, move_dirs := get_properties(cell, rules);

	assert(length > 0);

	can_capture := false;
	can_move := false;

	for dir : capture_dirs {
		if !ignore_active_figure && (dir == .{} || dir == -last_capture_dir) continue;
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
what_can_do :: (using board : Board, player : int, ignore_active_figure := false) -> can_capture:bool, can_move:bool {
	player_flag : Cell = xx(0x0001 << player);

	can_capture, can_move : bool;
	i := 0;
	for y : 0..diam-1 {
		for x : 0..diam-1 {
			defer i += 1;
			cell := cells[i];
			if !(cell & player_flag) continue;
			can_capture_f, can_move_f := what_can_do(board, .{xx x, xx y}, ignore_active_figure);
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
	// assert(alive > 0);
	return alive <= 1, winner;
}

Board_Interface :: struct {
	using board : *Board;
	player_me := 4;

	selected := ivec2.{-1, -1};
	cursor := ivec2.{0, 0};
}
click :: (using board_interface : *Board_Interface) -> nodes:int {
	if player_me != 4 && player_me != current_player return 0;
	assert(uncommited_count >= 0);
	if uncommited_count return 0;
	assert(cursor.x >= 0 && cursor.y >= 0 && cursor.x < diam && cursor.y < diam);
	is_clickable :: (using board : *Board, pos : ivec2) -> bool {
		if !is_owned_by(at(board, pos), current_player) return false;
		can_capture, can_move := what_can_do(board, pos);
		if (should_current_player_capture(board) || !can_move) && !can_capture return false;
		return true;
	}
	if selected == .{-1, -1} then {
		if is_clickable(board, cursor) selected = cursor;
		return 0;
	} else {
		result, nodes := try_step(board, selected,	cursor);
		if result == {
			case .NONE;
			if selected == cursor {
				selected = .{-1, -1};
			} else if is_clickable(board, cursor) {
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
				result2, nodes2 := try_step(board, selected, selected);
				assert(result2 == .ENDSEQ);
				nodes += nodes2;
				selected = .{-1, -1};
				// click(board_interface);
			}
		}
		return nodes;
	}
}