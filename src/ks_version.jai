using,except(Color) KS :: #import "kscurses";
#load "board.jai";

handle_key_board_interface :: (using board_interface : *Board_Interface, key : Key) {
	if key == {
		case .ENTER;
		if !is_final(board) click(board_interface);

			case #char"i"; #if DEBUG {
				cell := at(board, cursor);
				length, capture_dirs, dirs := get_properties(cell, rules);
				log("%: cell:%, length:%, capture dirs:%, move dirs:%\n", cursor, cell, length, capture_dirs, dirs);			
			}
	}
	dir := arrow_code_to_ivec2(key);
	cursor += dir;
	Clamp(*cursor.x, 0, diam - 1);
	Clamp(*cursor.y, 0, diam - 1);
}
c_draw_board :: (canvas : *Canvas, using board_interface : Board_Interface, offset : ivec2, show_cursor : bool) {
	if canvas.zone.width < diam * 2 || canvas.zone.height < diam + 1 {
		c_fill(canvas, (c, z) => make_char(#run utf8(" "), background = .GREEN));
		return;
	}

	i := 0;
	current_player_color := KS.Color.[.BRIGHT_BLACK, .BLUE, .RED, .GREEN][current_player];

	for y_c : 0..diam-1 {
		for x_c : 0..2*diam-1 {
			x := x_c / 2;
			x_l := x_c % 2;
			y := y_c;

			pos_c := ivec2.{xx x_c, xx y_c};
			pos := ivec2.{xx x, xx y};
			cell := at(board, pos);

			background : KS.Color = 
				ifx pos == cursor && show_cursor then .BRIGHT_YELLOW else 
				ifx pos == selected then .BRIGHT_MAGENTA else 
				ifx cell & .BORDER then current_player_color else
				ifx (x + y) % 2 then .WHITE else
				.BRIGHT_WHITE;
			foreground : KS.Color =
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
	delta : s32 = xx((diam * 2 - 17) / 2); 
	c_draw_line_ascii(canvas, tprint("[%|   |   |   ]", formatInt(alive_count[0], minimum_digits = 3, padding = #char" ")), .{delta, xx diam}, make_graphics_mode(background = .WHITE, foreground = .BLACK));
	c_draw_line_ascii(canvas, tprint("%", formatInt(alive_count[1], minimum_digits = 3, padding = #char" ")), .{5 + delta, xx diam}, make_graphics_mode(background = .WHITE, foreground = .BLUE));
	c_draw_line_ascii(canvas, tprint("%", formatInt(alive_count[2], minimum_digits = 3, padding = #char" ")), .{9 + delta, xx diam}, make_graphics_mode(background = .WHITE, foreground = .RED));
	c_draw_line_ascii(canvas, tprint("%", formatInt(alive_count[3], minimum_digits = 3, padding = #char" ")), .{13 + delta, xx diam}, make_graphics_mode(background = .WHITE, foreground = .GREEN));
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

	draw_game();
	while !stop_main {
		if wait_and_process_events() {
			draw_game();
			reset_temporary_storage();
		}
	}
}

#scope_file
board := Board.{
	rules = .{diam = 12, cutoff = 2, rows = 2, must_capture = .ALWAYS}
	// rules = .{diam = 16, cutoff = 4, rows = 2, rows_offset = 1, must_capture = false, diagonal = false}
};
board_interface : Board_Interface;
main_canvas : Canvas;
stop_main : bool;
blink_state := true;

init_game :: () {
	board_interface.board = *board;

	init(*board);
}
deinit_game :: () {
	#if DEBUG log("%\n", board.history);
	deinit(*board_interface);
	deinit(*main_canvas);
}
draw_game :: () {
	resize_clear(*main_canvas, .{size = terminal_state.size}, make_char(#char" ", background = .BLACK));
	c_draw_board(*main_canvas, *board_interface, .{0, 0}, blink_state);
	ks_draw_canvas(*main_canvas);
}