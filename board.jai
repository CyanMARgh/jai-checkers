#import "Basic";
#import "Extra_Containers";
#import "Math";

my_array_find :: (array: [] $T, item: T) -> bool, s64 {
	for array if it == item return true, it_index;
	return false, -1;
}

Rules :: struct {
	diam, cutoff, rows, rows_offset : s32 = 16, 4, 4, 0; 
	length_by_level			:= s32.[1, 2, 4, 8];
	// upgrade_in_process := true;
	border_period 			:= 20;

	must_capture			:= false;
	diagonal				:= true;
	_180_no_scope			:= false;
	leveled_upgrade 		:= false;
	backward_capture		:= true;
	enable_border			:= false;
	two_players 			:= false;
	must_continue_capture	:= false;
	land_right_behind		:= true;
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
	type : enum u8 { NONE; INVALID; MOVE; CAPTURE; BORDER; ADDBOOST; STEPEND; SEQEND; UPGRADE; };
	union {
		data_move : struct {
			from, to : ivec2;
		};
		data_capture : struct {
			from, to, dir : ivec2;
			killed : Cell;
			over :s32= 1;
		};
		data_border : struct {
			pos : ivec2;
			bef : Cell;
		};
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
		};
		data_seqend : struct {
			active_figure : ivec2;
			last_capture_dir : ivec2;
		};
	}
}
// 1) MOVE [, UPGRADE] [barrier nodes]STEPEND
// 2) CAPTURE [, UPGRADE], CAPTURE [, UPGRADE], CAPTURE [, UPGRADE] [barrier nodes]STEPEND
Board :: struct {
	using part_on_stack : struct {
		using rules : Rules;
		alive_count : [4]int;
		current_player := 0;
		uncommited_count := 0;
		step_id := 0;
		active_figure := ivec2.{-1, -1};
		last_capture_dir := ivec2.{0, 0};		
	}

	cells : []Cell;
	history : [..]Step;
}
at_ptr :: (using board : *Board, pos : ivec2) -> *Cell {
	assert(pos.x >= 0 && pos.x < diam && pos.y >= 0 && pos.y < diam);
	return *(cells[pos.x + diam * pos.y]);
}
at :: (using board : Board, pos : ivec2) -> Cell {
	if pos.x < 0 || pos.x >= diam || pos.y < 0 || pos.y >= diam then return .BORDER;
	return cells[pos.x + diam * pos.y];
}
is_valid :: (using rules : Rules) -> bool {
	if diam <= 0 || cutoff < 0 {
		log("(0)\n");
		return false;
	}
	if rows_offset < 0 || cutoff * 2 >= diam {
		log("(3)\n");
		return false;
	}
	if two_players {
		if (rows_offset + rows) * 2 >=  diam{
			log("(1)\n");
			return false;
		}
	} else {
		if cutoff == 0 || rows_offset + rows > cutoff {
			log("(2)\n");
			return false;
		}
	}
	return true;
}

init :: (using board : *Board) {
	assert(is_valid(rules));
	cells = NewArray(diam * diam, Cell);

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

	if two_players {
		i := 0;
		for y : 0..diam-1 {
			for x : 0..diam-1 {
				cell : Cell;
				if x == diam-1 then cell = .BOOST_BLACK;
				if x == 0 then cell = .BOOST_RED;

				if (!diagonal || (x % y) % 2 == 0) {
					if x >= rows_offset && x < rows + rows_offset {
						cell |= .RED;
						alive_count[2] += 1;
					} else if x < diam - rows_offset && x >= diam - rows - rows_offset {
						cell |= .BLACK;
						alive_count[0] += 1;
					}					
				}

				cells[i] = cell;
				i += 1;
			}
		}
	} else {
		i := 0;
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
gen_step_capture :: (using board : Board, from : ivec2, to : ivec2, dir : ivec2, over : s32) -> Step {
	killed := at(board, to - dir * over) & .FIGURE;
	// log("gen_step_capture: from = %, to = %, over = %, dir = %, killed = %\n", from, to, over, dir, killed);
	return .{type = .CAPTURE, data_capture = .{from = from, to = to, dir = dir, killed = killed, over = over}};
}
gen_step_upgrade :: (using board : Board, pos : ivec2) -> Step {
	c := at(board, pos);
	c_aft := upgrade(c);
	return .{type = ifx c == c_aft then .NONE else .UPGRADE, data_upgrade = .{pos = pos, bef = c, aft = c_aft}};
}

get_next_player :: (using board : Board) -> int {
	for i : 1..4 {
		p := (current_player + i) % 4;
		can_kill, can_move := what_player_can_do(board, p);
		if can_kill || can_move return p;
	}
	return 4;
}
gen_step_end :: (using board : Board) -> Step {
	assert(active_figure == .{-1 ,-1} && last_capture_dir == .{0, 0});
	return .{type = .STEPEND, data_stepend = .{
		player_old = current_player,
		player_new = get_next_player(board)
	}};
}
gen_sequence_end :: (using board : Board) -> Step {
	assert(active_figure != .{-1 ,-1} && last_capture_dir != .{0, 0});
	return .{type = .SEQEND, data_seqend = .{
		active_figure = active_figure,
		last_capture_dir = last_capture_dir
	}};
}

apply :: (using board : *Board, step : Step) {
	if #complete step.type == {
		case .MOVE; using step.data_move; 
		c1, c2 := at_ptr(board, from), at_ptr(board, to);
		c2.* |= c1.* & .FIGURE;
		c1.* &= .BOARD_PROPS;

		case .CAPTURE; using step.data_capture;

		c1, c2, c3 := at_ptr(board, from), at_ptr(board, to), at_ptr(board, to - dir * over);
		c2.* |= c1.* & .FIGURE;
		c1.* &= .BOARD_PROPS;

		killed_player := get_player_by_code(c3.*);
		assert(killed_player != 4);
		alive_count[killed_player] -= 1;
		// log("apply: from = %, to = %, over = %, dir = %, killed = %; c3 = %\n", from, to, over, dir, killed, c3.*);

		c3.* &= .BOARD_PROPS;
		active_figure = to;
		last_capture_dir = dir;

		case .UPGRADE; using step.data_upgrade;
		at_ptr(board, pos).* = aft;

		case .SEQEND;
		active_figure = .{-1, -1};
		last_capture_dir = .{};

		case .STEPEND; using step.data_stepend;
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

	if #complete step.type == {
		case .MOVE; using step.data_move; 
		c1, c2 := at_ptr(board, from), at_ptr(board, to);
		c1.* |= c2.* & .FIGURE;
		c2.* &= .BOARD_PROPS;

		case .CAPTURE; using step.data_capture;
		c1, c2, c3 := at_ptr(board, from), at_ptr(board, to), at_ptr(board, to - dir * over);
		c1.* |= c2.* & .FIGURE;
		c2.* &= .BOARD_PROPS;

		killed_player := get_player_by_code(killed);
		assert(killed_player != 4, "from = %, to = %, over = %, dir = %, killed = %\n", from, to, over, dir, killed);
		alive_count[killed_player] += 1;

		c3.* |= killed;
		active_figure = .{-1, -1};
		last_capture_dir = .{0, 0};

		case .UPGRADE; using step.data_upgrade;
		at_ptr(board, pos).* = bef;

		case .SEQEND;
		active_figure = step.data_seqend.active_figure;
		last_capture_dir = step.data_seqend.last_capture_dir;

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
capture :: (using board : *Board, from : ivec2, to : ivec2, dir : ivec2, over : s32) -> nodes:int {
	nodes := 1;
	step := gen_step_capture(board, from, to, dir, over);
	apply_and_write(board, step);
	step2 := gen_step_upgrade(board, to);
	if step2.type == .UPGRADE {
		apply_and_write(board, step2);
		nodes += 1;
	}
	return nodes;
}
Ring :: struct {diam : s32; offset : s32; sync : bool; type : enum u8 { DEFAULT; DOUBLE_CORNER; TWO_ROWS; }; }
for_expansion :: (using ring : Ring, body : Code, $flags : For_Flags) #expand {
	`it, `forward : ivec2;
	`it_index := 0; `color_flag : Cell;

	L : s32;
	directions_fwd, directions_left, corners : []ivec2;
	colors : []Cell;

	h0, h1, h2, h3 : s32 = 0, offset, diam - offset - 1, diam - 1;
	if type == .TWO_ROWS {
		directions_fwd  = .[.{-1, 0}, .{1, 0},];
		directions_left = .[.{0, 1}, .{0, -1},];
		colors = .[.BLACK, .RED];
		corners =.[.{h2, h0}, .{h1, h3}];
	} else {
		directions_fwd  = .[.{-1, 0}, .{0, -1}, .{1, 0}, .{0, 1}];
		directions_left = .[.{0, 1}, .{-1, 0}, .{0, -1}, .{1, 0}];
		colors = .[.BLACK, .BLUE, .RED, .GREEN];
		corners =.[.{h2, h1}, .{h2, h2}, .{h1, h2}, .{h1, h1}];
	}
	if type == {
		case .DEFAULT;
		L = diam - 2 * offset - 2;
		case .DOUBLE_CORNER;
		L = diam - 2 * offset - 1;
		case .TWO_ROWS;
		L = diam;
	}

	if sync {
		for i : 0..L {	
			for j : 0..directions_fwd.count-1 {
				`forward = directions_fwd[j];
				`color_flag = colors[j];
				left := directions_left[j];
				`it = corners[j] + left * i;
				`it_index += 1;
				#insert body;
			}
		}
	} else {
		for j : 0..directions_fwd.count-1 {
			`forward = directions_fwd[j];
			`color_flag = colors[j];
			left := directions_left[j];
			for i : 0..L {
				`it = corners[j] + left * i;
				`it_index += 1;
				#insert body;
			}
		}
	}
}
gen_apply_and_write_board_nodes :: (using board : *Board) -> nodes:int {
	assert(enable_border);
	nodes := 0;	
	si := step_id + 1;

	if si % border_period == 0 {
		H := si / border_period - 1;
		assert(H * 2 <= diam);
		// push
		if !diagonal {
			for Ring.{diam = xx diam, offset = xx (H + 1), sync = true, type = ifx two_players then .TWO_ROWS else .DEFAULT} {
				cell := at(board, it);
				to := it + forward;
				cell_next := at(board, to);
				if (cell & .FIGURE_TYPE) && !is_obstacle(cell_next) {
					apply_and_write(board, .{type = .MOVE, data_move = .{from = it, to = to}});
					nodes += 1;
				}
			}
		}
		// add borders
		for Ring.{diam = xx diam, offset = xx H, sync = false, type = ifx two_players then .TWO_ROWS else .DEFAULT} {
			cell := at(board, it);
			if cell != .BORDER {
				apply_and_write(board, .{type = .BORDER, data_border = .{pos = it, bef = cell}});
				nodes += 1;
			}
		}
		// addbost & upgrade
		for Ring.{diam = xx diam, offset = xx (H + 1), sync = false, type = ifx two_players then .TWO_ROWS else .DOUBLE_CORNER} {
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
end_sequence :: (using board : *Board) -> nodes:int {
	apply_and_write(board, gen_sequence_end(board));
	return 1;
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
	ready_for_capture :: (board : *Board, from : ivec2, length : s32, max_length : s32, dir : ivec2, capture_dirs : [4]ivec2) -> ready:bool, over:s32 {
		if length <= 1 || length > max_length + 1 || !my_array_find(capture_dirs, dir) then return false, -1;
		over :s32= -1;
		enemies_count := 0;
		cell_from := at(board, from);

		for i : 1..length {
			cell := at(board, from + dir * i);
			if is_obstacle(cell) {
				if is_enemies(cell, cell_from) {
					enemies_count += 1;
					over = length - i;
				} else {
					return false, -1;
				}
			}
		}
		return over == 1 || (!board.land_right_behind && over > 1), over;
	}

	nodes := 0;

	dir, length := get_dir_and_length(from, to);
	cell := at(board, from);
	max_length, capture_dirs, move_dirs := get_properties(cell, rules);

	if !is_owned_by(cell, current_player) return .NONE, nodes;

	if active_figure != .{-1, -1} then {
		if from != active_figure then return .NONE, nodes;
		// end sequence
		if (length == 0) && (!must_continue_capture || !can_continue_capture(board)) {
			nodes += end_sequence(board);
			nodes += end_step(board);
			return .ENDSEQ, nodes;
		}
		// continue sequence
		if dir != .{} && (_180_no_scope || dir != -last_capture_dir) {
			ready, over := ready_for_capture(board, from, length, max_length, dir, capture_dirs);
			if ready {
				nodes += capture(board, from, to, dir, over);
				return .CAPTURE, nodes;				
			}
		}
		return .NONE, nodes;
	}

	// move
	// if dir == .{} return .NONE, nodes;
	if !should_current_player_capture(board) && ready_for_move(board, from, length, max_length, dir, move_dirs) {
		nodes += move(board, from, to);
		nodes += end_step(board);
		return .MOVE, nodes;
	}
	// start sequence
	ready, over := ready_for_capture(board, from, length, max_length, dir, capture_dirs);
	if ready {
		// log("over = %\n", over);
		nodes += capture(board, from, to, dir, over);
		return .CAPTURE, nodes;
	}
	return .NONE, nodes;
}
should_current_player_capture :: (using board : *Board) -> bool {
	if !must_capture return false;
	can_capture, can_move := what_player_can_do(board, current_player);
	return can_capture;
}
is_final :: (using board : *Board) -> bool, winner:int {
	if active_figure != .{-1, -1} then return false, 4;
	if current_player == 4 then return true, 4;
	alive, winner := 0, 4;
	for p : 0..3 {
		can_capture, can_move := what_player_can_do(board, p);
		if can_capture || can_move {
			winner = p;
			alive += 1;
		}
	}
	return alive <= 1, winner;
}
Board_Interface :: struct {
	using board : *Board;

	selected := ivec2.{-1, -1};
	cursor := ivec2.{0, 0};

	shown_steps_move : []ivec2;
	shown_steps_capture : []ivec2;

	clickable_figures_move : []ivec2;
	clickable_figures_capture : []ivec2;
}
init :: (board_interface : *Board_Interface, board : *Board) {
	init(board);
	board_interface.board = board;
	refresh_possible_moves(board_interface);
}
what_figure_can_do :: (using board : Board, pos : ivec2, banned_capture_direction : ivec2) -> can_capture:bool, can_move:bool {
	can_capture, can_move := get_possible_steps(board, pos, false, banned_capture_direction, false);
	return can_capture, can_move;
}
what_player_can_do :: (using board : Board, player_id : int, $FIND_ALL := false) -> can_capture:bool, can_move:bool, list_capture:[]ivec2, list_move:[]ivec2 {
	//TODO maybe check only one player
	list_capture, list_move : [..]ivec2;
	// list_move_or_capture
	can_capture, can_move : bool;

	if active_figure == .{-1, -1} then {
		i := 0;
		for y : 0..diam-1 {
			for x : 0..diam-1 {
				defer i += 1;
				cell := cells[i];
				p := get_player_by_code(cell);
				if p != player_id continue;
				pos := ivec2.{xx x, xx y};
				can_capture_f, can_move_f := what_figure_can_do(board, pos, .{});
				can_capture |= can_capture_f;
				can_move |= can_move_f;

				#if FIND_ALL {
					if can_capture_f then array_add(*list_capture, pos);
					if can_move_f then array_add(*list_move, pos);
				} else {
					if can_capture && can_move break y;
				}
			}
		}		
	} else {
		//TODO
		//asert p == player_id
		//TODO
		can_capture_f, _ := what_figure_can_do(board, active_figure, -last_capture_dir);
		can_move_f := true;

		can_capture = can_capture_f;
		can_move = can_move_f;
		#if FIND_ALL {			
			if can_capture_f array_add(*list_capture, active_figure);
			if can_move_f array_add(*list_move, active_figure);
		}
	}
	if can_capture && must_capture {
		array_reset(*list_move);
		can_move = false;
	}
	return can_capture, can_move, list_capture, list_move;
}
can_continue_capture :: (using board : Board) -> bool {
	assert(active_figure != .{-1, -1});
	cell := at(board, active_figure);
	assert(!!(cell & .FIGURE_TYPE), "cell = %", cell);
	assert(get_player_by_code(cell) == current_player);
	length, capture_dirs, move_dirs := get_properties(cell, rules);
	assert(length > 0);

	for dir : capture_dirs {
		if (dir == .{} || (!_180_no_scope && dir == -last_capture_dir)) continue;
		obstacle : Cell;
		for i : 1..length {
			obstacle = at(board, active_figure + dir * i);
			if is_obstacle(obstacle) {
				if is_enemies(cell, obstacle) && !is_obstacle(at(board, active_figure + dir * (i + 1))) {
					return true;
				}
				break i;
			}
		}
	}
	return false;
}
click :: (using board_interface : *Board_Interface, sender_id := 4) -> nodes:int {
	// log("(0)\n");
	if sender_id != 4 && sender_id != current_player return 0;
	// log("(1)\n");
	assert(uncommited_count >= 0);
	if uncommited_count return 0;
	assert(cursor.x >= 0 && cursor.y >= 0 && cursor.x < diam && cursor.y < diam);
	// log("(2)\n");
	defer refresh_possible_moves(board_interface);
	is_clickable :: (using board : *Board, pos : ivec2) -> bool {
		if !is_owned_by(at(board, pos), current_player) return false;
		can_capture, can_move := what_figure_can_do(board, pos, .{});
		if (should_current_player_capture(board) || !can_move) && !can_capture return false;
		return true;
	}
	// log("(3)\n");
	if selected == .{-1, -1} then {
		if active_figure != .{-1, -1} then {
			if active_figure == cursor {
				selected = cursor;
			}
		} else {
			if is_clickable(board, cursor) {
				selected = cursor;
			}
		}
		return 0;
	} else {
		// log("(4)\n");
		result, nodes := try_step(board, selected,	cursor);
		// log("(5)\n");
		if #complete result == {
			case .NONE;
			if active_figure == .{-1, -1} {
				if selected == cursor {
					selected = .{-1, -1};
				} else if is_clickable(board, cursor) {
					selected = cursor;
				}
			}

			case .MOVE;
			selected = .{-1, -1};

			case .ENDSEQ;
			selected = .{-1, -1};

			case .CAPTURE;
			selected = cursor;
			if !can_continue_capture(board) {
				// log("automatic end!\n");
				result2, nodes2 := try_step(board, selected, selected);
				assert(result2 == .ENDSEQ);
				nodes += nodes2;
				selected = .{-1, -1};
			}
		}
		// log("(6)\n");
		return nodes;
	}
}
get_possible_steps :: (using board : Board, pos : ivec2, should_capture : bool, banned_capture_direction : ivec2, $FIND_ALL : bool) -> can_capture:bool, can_move:bool, steps_capture:[]ivec2, steps_move:[]ivec2 {
	cell := at(board, pos);
	length, capture_dirs, move_dirs := get_properties(cell, rules);

	steps_capture : [..]ivec2;
	steps_move : [..]ivec2;

	can_capture, can_move := false;

	process_step :: (to : ivec2, is_capture : bool) #expand {
		can_capture ||= is_capture;
		can_move ||= !is_capture;
		#if FIND_ALL {
			if is_capture {
				array_add(*steps_capture, to);
			} else {
				array_add(*steps_move, to);
			}			
		}
	}

	for dir : capture_dirs {
		if dir == .{0, 0} || dir == banned_capture_direction continue;

		enemies_count := 0;
		last_enemy_pos := -1;
		for l : 1..length+1 {
			to := pos + dir * l;
			cell_to := at(board, to);
			if is_obstacle(cell_to) {
				if is_enemies(cell, cell_to) {
					enemies_count += 1;
					last_enemy_pos = l;
					if enemies_count > 1 break l;
				} else {
					break l;
				}
			} else {
				if enemies_count == 1 && (last_enemy_pos == l - 1 || !land_right_behind) {
					process_step(to, true);
					#if !FIND_ALL { break dir; }					
				}
			}
		}
	}
	if !should_capture {
		for dir : move_dirs {
			if dir == .{0, 0} continue;
			to := pos;
			for l : 1..length {
				to += dir;
				cell_to := at(board, to);
				if is_obstacle(cell_to) break l;
				process_step(to, false);
				#if !FIND_ALL { break dir; }
			}
		}
	}
	return can_capture, can_move, steps_capture, steps_move;
}
// get_clickable_figures :: (using board : Board) -> list_capture:[]ivec2, list_move:[]ivec2 {
// 	list_capture, list_move : [..]ivec2;
// 	// 	i := 0;
// 	// 	for y : 0..diam-1 {
// 	// 		for x : 0..diam-1 {
// 	// 			defer i += 1;
// 	// 			cell := cells[i];
// 	// 			p := get_player_by_code(cell);
// 	// 			if p == 4 continue;
// 	// 			if can_capture[p] && can_move[p] continue;
// 	// 			can_capture_f, can_move_f := what_figure_can_do(board, .{xx x, xx y}, .{});

// 	// 			can_capture[p] |= can_capture_f;
// 	// 			can_move[p] |= can_move_f;
// 	// 		}
// 	// 	}
// 	// 	return can_capture, can_move;
// 	// }
// }
refresh_possible_moves :: (using board_interface : *Board_Interface) {
	array_reset(*shown_steps_move);
	array_reset(*shown_steps_capture);

	array_reset(*clickable_figures_move);
	array_reset(*clickable_figures_capture);

	_, _, clickable_figures_capture, clickable_figures_move = what_player_can_do(board, current_player, true);

	if selected != .{-1, -1} {
		_, _, shown_steps_capture, shown_steps_move = get_possible_steps(
			board,
			selected,
			active_figure != .{-1 ,-1} || should_current_player_capture(board),
			ifx _180_no_scope then .{} else -last_capture_dir,
			true
		);
	}
}
deinit :: (using board_interface : *Board_Interface) {
	deinit(board);
	array_free(shown_steps_move);
	array_free(shown_steps_capture);
	array_free(clickable_figures_move);
	array_free(clickable_figures_capture);
}

#load "serialization.jai";
#import "File";
save_board :: (using board : Board, path : string) -> bool {
	bytes : [..]u8; bytes.allocator = temp;
	write_data(*bytes, part_on_stack);
	write_array(*bytes, cells);
	write_array(*bytes, history);
	return write_entire_file(path, bytes.data, bytes.count);	
}
load_board :: (using board : *Board, path : string) -> bool {
	src, ok := read_entire_file(path); defer free(src);
	if !ok return false;
	src_u8 := (cast(*[]u8)*src).*;
	if !cut_data_move(*part_on_stack, *src_u8) return false;
	if !cut_array_move(*cells, *src_u8) return false;
	if !cut_array_move(*history, *src_u8) return false;
	history.allocated = history.count;
	return src_u8.count == 0;
}
copy :: (using src : Board) -> Board {
	result := src;
	result.cells = array_copy(cells);
	H : [..]Step;
	array_add(*H, ..history);
	result.history = H;
	return result;
}
operator== :: (b1 : Board, b2 : Board) -> bool {
	posa1 := to_byte_array_view(*b1.part_on_stack);
	posa2 := to_byte_array_view(*b2.part_on_stack);
	if !is_same_array(posa1, posa2) return false;
	if !is_same_array(b1.cells, b2.cells) return false;
	if !is_same_array(b1.history, b2.history) return false;
	return true;
}
is_same_fields :: (o1 : $T, o2 : T) -> bool 
#modify {
	ti := cast(*Type_Info) T;
	return ti.type == .STRUCT;
} {
	ptr1, ptr2 : *u8 = xx *o1, xx *o2;
	tis := cast(*Type_Info_Struct)type_info(T);
	for tis.members {
		offset, size := it.offset_in_bytes, it.type.runtime_size;
		if memcmp(ptr1 + offset, ptr2 + offset, size) return false;
	}
	return true;
}
operator== :: (s1 : Step, s2 : Step) -> bool {
	if s1.type != s2.type return false;
	if #complete s1.type == {
		case .NONE; return true;
		case .INVALID; return true;
		case .MOVE; return is_same_fields(s1.data_move, s2.data_move);
		case .CAPTURE; return is_same_fields(s1.data_capture, s2.data_capture);
		case .BORDER; return is_same_fields(s1.data_border, s2.data_border);
		case .UPGRADE; return is_same_fields(s1.data_upgrade, s2.data_upgrade);
		case .STEPEND; return is_same_fields(s1.data_stepend, s2.data_stepend);
		case .ADDBOOST; return is_same_fields(s1.data_addboost, s2.data_addboost);
		case .SEQEND; return is_same_fields(s1.data_seqend, s2.data_seqend);
	}
	return false;
}

Board_Request :: struct {
	sender_id : int; // 4 if moderator mode
	click_pos : ivec2;
	new_nodes : []Step;
}
click_with_verification :: (using board_interface : *Board_Interface, request : Board_Request) -> verified:bool, new_nodes_count:int {
	assert(uncommited_count >= 0);
	tmp := board_interface.cursor;

	board_interface.cursor = request.click_pos;
	new_nodes_count := click(board_interface, request.sender_id);
	// log("new_nodes_count(real) : %\n", new_nodes_count);
	new_nodes_real := array_view(history, history.count - new_nodes_count);
	if is_same_array(new_nodes_real, request.new_nodes) {
		return true, new_nodes_count;
	} else {
		for 1..new_nodes_count undo_single(board);
		history.count -= uncommited_count;
		uncommited_count = 0;
		board_interface.cursor = tmp;
		return false, 0;
	}
}