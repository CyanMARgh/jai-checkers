using visual_properties : struct {
	BACKGROUND_COLORS :: Vector3.[
		.{150, 150, 150},
		.{200, 200, 255},
		.{255, 200, 200},
		.{200, 255, 200},
		.{0, 0, 0}
	];
	FIGURE_RADIUS :: .2;
	FIGURE_HEIGHT :: FIGURE_RADIUS * .5;
	FIGURE_INNER_CIRCLE_RATIO :: .75;
	CELL_SIZE :: .5;
	CELL_HEIGHT :: .3;
	SELECTION_GAP :: .05;
	CYLINDER_QUALITY :: 20;

	SHINING_BORDERS :: true;
	COLOR_ZONES :: true;
	SHOW_CLICKABLE_FIGURES :: true && !AUTO_PLAY;
	SHOW_POSSIBLE_STEPS :: true && !AUTO_PLAY;
}
Game_Scene :: struct {
	board : Board; 
	board_interface : Board_Interface;

	using visual_data : struct {
		cursor_collision : RayCollision;
		background := BACKGROUND_COLORS[0];

		animation_time := 0.;
		current_step := Step.{type = .NONE};
		banned_figure_coords := ivec2.[.{-1, -1}, .{-1, -1}];
		banned_cell_coords := ivec2.[.{-1, -1}];
		caption_angle := 90.;

		immediate_switch := false;

		toatal_translation := Vector3.{0, 0, 0};

		fireworks_timer := 0.;
		FIREWORKS_DELAY :: .2;
	};
}
init_main_scene :: (using game_scene : *Game_Scene) {
	visual_data = .{};
	init(*board_interface, *board);
}
deinit_main_scene :: (using game_scene : *Game_Scene) {
	deinit(*board_interface);
}
simulate :: (using game_scene : *Game_Scene, delta_time : float) {
	background = background * (1 - delta_time) + BACKGROUND_COLORS[board.current_player] * delta_time;
	process_unapplied_steps(game_scene, delta_time);
	if board.final {
		fireworks_timer -= delta_time;
		if fireworks_timer <= 0. {
			color : Color;
			ifx board.current_player == {
				case 0; color = BLACK;
				case 1; color = BLUE;
				case 2; color = RED;
				case 3; color = GREEN;
				case 4; color = WHITE;
				case; assert(false);
			}

			S := Vector3.{xx board.diam * CELL_SIZE, CELL_HEIGHT, xx board.diam * CELL_SIZE};
			point := Vector3.{random_get_within_range(-.5, .5) * S.x, S.y / 2, random_get_within_range(-.5, .5) * S.z};
			emit(*particle_system, toatal_translation + point, base_color = color, new_particles_count = 30);
			fireworks_timer = FIREWORKS_DELAY;
		}
	}
}
process_input :: (using game_scene : *Game_Scene, camera : Camera, cursor_enabled : bool) {
	board_interface.cursor = .{-1, -1};
	if cursor_enabled {
		find_intersection(game_scene, camera);
		if IsMouseButtonPressed(.LEFT) {
			if board_interface.cursor != .{-1, -1} && board.uncommited_count == 0 {
				new_nodes_count := click(*board_interface);
				new_nodes := array_view(board.history, board.history.count - new_nodes_count);
				// log("new nodes:\n");
				// for new_nodes log("%\n", it);
				for 1..new_nodes_count {
					undo_single(*board);
				}
			}
		}
	}

	if IsKeyPressed(.S) {
		tmp := copy(board); defer deinit(*tmp);
		ok := save_board(board, "b1.board");
		assert(ok);
		deinit(*board);
		ok = load_board(*board, "b1.board");
		assert(ok);
		assert(tmp == board);
	}
}
find_intersection :: (using game_scene : *Game_Scene, camera : Camera) {
	ray := GetMouseRay(GetMousePosition(), camera);
	ray.position -= toatal_translation;
	S := Vector3.{xx board.diam * CELL_SIZE, CELL_HEIGHT, xx board.diam * CELL_SIZE};
	c0 := GetRayCollisionBox(ray, .{-.5 * S, .5 * S});

	for y : 0..board.diam-1 {
		for x : 0..board.diam-1 {
			cell_coord := ivec2.{xx x, xx y};
			cell := at(*board, cell_coord);
			pos := to_vec3(*board, cell_coord);
			if cell & .FIGURE {
				level := cell_level(cell);
                size := ifx cell_coord == board_interface.selected then SELECTED_PIECE_SIZE else 1;
				c1 := GetRayCollisionCylinder(ray, pos, pos + Vector3.{0, CELL_HEIGHT / 2 + FIGURE_HEIGHT * (1 + level), 0} * size, FIGURE_RADIUS * size);
				if c1.hit && c1.distance < c0.distance {
					c0 = c1;
				}
			}
		}
	}

	ipos : ivec2;
	if c0.hit {
		pos := c0.point + .5 * S;
		ipos = .{xx (pos.x / CELL_SIZE), xx (pos.z / CELL_SIZE)};
		Clamp(*ipos.x, 0, board.diam - 1);
		Clamp(*ipos.y, 0, board.diam - 1);
	} else {
		ipos = .{-1, -1};
	}
	if (at(*board, ipos) & .BORDER) {
		ipos = .{-1, -1};
	}
	cursor_collision = c0;
	board_interface.cursor = ipos;
}
process_unapplied_steps :: (using game_scene : *Game_Scene, delta_time : float) {
	try_start_new_animation :: (using game_scene : *Game_Scene) {
		current_step = get_step_to_animate(board);
		animation_time = 0;

		if current_step.type == {
			case .UPGRADE; using current_step.data_upgrade;
			point := to_vec3(board, pos) + .{0, CELL_HEIGHT / 2, 0};
			diff := aft & ~bef;
			if diff & .KING_RED emit(*particle_system, toatal_translation + point, base_color = RED);
			if diff & .KING_BLUE emit(*particle_system, toatal_translation + point, base_color = BLUE);
			if diff & .KING_BLACK emit(*particle_system, toatal_translation + point, base_color = BLACK);
			if diff & .KING_GREEN emit(*particle_system, toatal_translation + point, base_color = GREEN);
			play(*sg_upgrade);
			case .MOVE;
			play(*sg_slide);
			case .CAPTURE;
			play(*sg_slide);
			play(*sg_crack);
			case .STEPEND; using current_step.data_stepend;
		}
	}
    ANIMATION_SPEED :: 4;
	update_animation :: (using game_scene : *Game_Scene, delta_time : float) -> current_animation_ended:bool {
		if current_step.type == {
			case .NONE;
			return false;
			case .MOVE;
			animation_time += ANIMATION_SPEED * delta_time;
			case .CAPTURE;
			animation_time += ANIMATION_SPEED * delta_time;
			case .BORDER;
			animation_time += 5 * delta_time;
			case .STEPEND; using current_step.data_stepend;
			if immediate_switch || player_new == player_old {
				animation_time = 1;
			} else {
				animation_time += 2 * delta_time;				
			}
			case;
			return true;
		}
		return animation_time >= 1;
	}
	animation_end :: (using game_scene : *Game_Scene) {
		if current_step.type == {
			case .STEPEND; using current_step.data_stepend;
			caption_angle := 90. * (player_new + 1);
		}
	}
	set_blacklist :: (using game_scene : *Game_Scene) {
		banned_figure_coords = .[.{-1, -1}, .{-1, -1}];
		banned_cell_coords = .[.{-1, -1}];
		if current_step.type == {
			case .MOVE; using current_step.data_move;
			banned_figure_coords[0] = from;
			case .CAPTURE; using current_step.data_capture;
			banned_figure_coords[0] = from;
			banned_figure_coords[1] = to - dir * over;
			case .BORDER; using current_step.data_border;
			banned_figure_coords[0] = pos;
			banned_cell_coords[0] = pos;
		}
	}
	if current_step.type == .NONE {
		try_start_new_animation(game_scene);
	}
	while update_animation(game_scene, delta_time) {
		animation_end(game_scene);
		redo_single(*board);
		try_start_new_animation(game_scene);
	}
	set_blacklist(game_scene);
}
process_request :: (using game_scene : *Game_Scene, request : Board_Request) {
	assert(board.uncommited_count == 0);
	verified, new_nodes_count := click_with_verification(*board_interface, request);
	log("got request: %\n", request);
	if verified {
		log("animation started!\n");
		for 1..new_nodes_count {
			undo_single(*board);
		}
	} else {
		log("invalid request!\n");
	}
}

to_vec3 :: (using board : Board, cell_coord : ivec2) -> Vector3 {
	return (Vector3.{xx cell_coord.x, 0, xx cell_coord.y} - Vector3.{xx(diam - 1), 0, xx(diam - 1)} * .5) * CELL_SIZE;
}

Draw_Parts :: enum_flags u16 {
	MINIMUM			:: 0x0000;

	HINTS 			:: 0x0001;
	CAPTIONS		:: 0x0002;
	BACKGROUND		:: 0x0004;
	ROSE			:: 0x0008;
	DEBUG_INFO		:: 0x0010;
	RAY_COLLISION	:: 0x0020;
	CURSOR			:: 0x0040;

	ALL				:: 0xFFFF;
}

SELECTED_PIECE_SIZE :: 1.05;
draw_scene :: (using game_scene : Game_Scene, camera : Camera, time : float, parts := Draw_Parts.ALL) {
	draw_figure :: (cell : Cell, pos : Vector3, using game_scene : Game_Scene, size : float = 1) {
		y_offset := 0.;
		draw_layer :: (pos: Vector3, color : Color, using game_scene : Game_Scene) #expand {
			DrawModel(model_cylinder, pos + Vector3.{0, CELL_HEIGHT / 2 + y_offset, 0}, size, color);
			`y_offset += FIGURE_HEIGHT * size;
		}
		if board.leveled_upgrade {
			if cell & .KING_BLACK then draw_layer(pos, BLACK, game_scene);
			if cell & .KING_BLUE then draw_layer(pos, BLUE, game_scene);
			if cell & .KING_RED then draw_layer(pos, RED, game_scene);
			if cell & .KING_GREEN then draw_layer(pos, GREEN,game_scene);
		}
		DrawModel(
			model_cylinder,
			pos + Vector3.{0, y_offset + CELL_HEIGHT / 2 + (FIGURE_HEIGHT * (1 - FIGURE_INNER_CIRCLE_RATIO) + .01) * size, 0},
			FIGURE_INNER_CIRCLE_RATIO * size,
			ifx !board.leveled_upgrade && (cell & .KING_ANY) then .{255, 255, 100, 255} else WHITE		
		);
		type := cell & .FIGURE_TYPE;
		color_top : Color;
		if type == {
			case .BLACK; color_top = BLACK;
			case .BLUE; color_top = BLUE;
			case .RED; color_top = RED;
			case .GREEN; color_top = GREEN;
			case; assert(false, "type = %, cell = %\n", type, cell);
		}
		draw_layer(pos, color_top, game_scene);
	}
	get_cell_color :: (p : ivec2, cell : Cell, time : float, using rules : Rules) -> Color {
		factor :: .1;
		cell_color := RAYWHITE;
		if (p.x + p.y) % 2 {
			cell_color = WHITE;
		} else #if COLOR_ZONES if !rules.two_players {
			if p.y < cutoff {
				cell_color = mix(RAYWHITE, GREEN, factor);
			} else if p.y >= diam - cutoff {
				cell_color = mix(RAYWHITE, BLUE, factor);
			} else if p.x < cutoff {
				cell_color = mix(RAYWHITE, RED, factor);
			}
			// else if p.x >= diam - cutoff {
			// 	cell_color = mix(RAYWHITE, BLACK, factor);
			// }
		}
		#if SHINING_BORDERS if cell & .BOOSTS {
			h1 := cast(float)knuth_hash((cast(u64)p.y) ^ knuth_hash(cast(u64)p.x)) / U64_MAX;
			h2 := cast(float)knuth_hash((cast(u64)p.x) ^ knuth_hash(cast(u64)p.y)) / U64_MAX;
			factor := (sin(time * (2 + h1 * 2) + h2 * 10) + 1) * .03;
			cell_color = mix(cell_color, MAGENTA, xx factor);
		}
		return cell_color;
	}
	draw_cursor_selection_and_collision :: (using game_scene : Game_Scene, parts : Draw_Parts) {
		cursor := board_interface.cursor;
		if !board.final && cursor != .{-1, -1} && parts & .CURSOR then {
			// assert(cursor_collision.hit);
			#if DEBUG if parts & .RAY_COLLISION {
				p1 := cursor_collision.point;
				p2 := p1 + .2 * cursor_collision.normal;
				DrawCube(p1, .05, .05, .05, SKYBLUE);
				DrawLine3D(p1, p2, BLUE);					
			}
			DrawCube(to_vec3(*board, cursor), CELL_SIZE + SELECTION_GAP * 2, CELL_HEIGHT + SELECTION_GAP * 2, CELL_SIZE + SELECTION_GAP * 2, .{0, 255, 0, 30});
		}
		selected := board_interface.selected;
		if selected != .{-1, -1} then {
			DrawCube(to_vec3(*board, selected), CELL_SIZE + SELECTION_GAP, CELL_HEIGHT + SELECTION_GAP, CELL_SIZE + SELECTION_GAP, .{255, 0, 255, 30});
		}
	}
	draw_mooving_figure :: (cell : Cell, from : ivec2, to : ivec2, t : float, using game_scene : Game_Scene) {
		p1, p2 := to_vec3(*board, from), to_vec3(board, to);
		pos := lerp(p1, p2, t);
        size := 1.1; 
        dp := to-from; distance := dp.x+dp.y; if distance < 0 then distance = -distance; 
        if distance > 0 {
            t_edge := .25/distance;
            if t > 1 - t_edge then size = lerp(size, 1, (t + t_edge - 1)/t_edge);
            else if t < t_edge then size = lerp(SELECTED_PIECE_SIZE, size, t/t_edge);
        }
		draw_figure(at(*board, from), pos, game_scene, size);
	}
    draw_shrinking_figure :: (cell : Cell, pos : ivec2, t : float, using game_scene : Game_Scene) {
        draw_figure(cell, to_vec3(board, pos), game_scene, 1-t);
    }

	draw_animation :: (using game_scene : Game_Scene, time : float) {
		if current_step.type == {
			case .MOVE; using current_step.data_move;
			t := pow(animation_time, .5);
			draw_mooving_figure(at(*board, from), from, to, t, game_scene);
			case .CAPTURE; using current_step.data_capture;
			t := pow(animation_time, .5);
			draw_mooving_figure(at(*board, from), from, to, t, game_scene);
			delta := to - from;
			L := abs(delta.x) + abs(delta.y);
            killed_pos := to - dir * over;
            t_over := 1. - cast(float)over / L;
			if t <= t_over {
				draw_figure(at(board, killed_pos), to_vec3(board, killed_pos), game_scene);
			} else {
                draw_shrinking_figure(at(board, killed_pos), killed_pos, (t-t_over)/(1-t_over), game_scene);
            }
			case .BORDER; using current_step.data_border;
			pos_3 := to_vec3(*board, pos);
			cell := at(*board, pos);
			base_color := get_cell_color(pos, cell, time, board.rules);

			ease :: t => t * t * t;
			t := ease(animation_time);

			result_color := mix(base_color, BLACK, t);
			DrawModel(model_cell, pos_3, lerp(1, .1, t), result_color); 
		}
	}
	draw_click_option :: (using game_scene : Game_Scene, at : ivec2, color : Color) {
		pos := to_vec3(board, at);
		DrawModel(model_cylinder, pos + Vector3.{0, CELL_HEIGHT / 4, 0}, 1.2, color);	
	}
	draw_step_option :: (using game_scene : Game_Scene, at : ivec2, color : Color) {
		pos := to_vec3(board, at) + .{0, CELL_HEIGHT, 0};
		DrawModel(model_sphere, pos, .1, color);
	}
	draw_text_cell :: (using game_scene : Game_Scene, at : ivec2, src : *u8, angle : float, color : Color) {
		PushMatrix();
			ts := MeasureText3D(font, src, 1, .3, 0);
			scale := .8 * CELL_SIZE / max(ts.x, ts.z, 0.05);

			pos := to_vec3(board, at);
			Translatef(pos.x, pos.y, pos.z);

			Translatef(0, CELL_HEIGHT / 2 + 0.01, 0);

			Scalef(scale, scale, scale);
			Rotatef(angle, 0, 1, 0);
			Translatef(-ts.x / 2, 0, -ts.z / 2);

			DrawText3D(font, src, .{0, 0, 0}, 1, .3, 0, false, color);
		PopMatrix();
	}
	draw_text_cell :: (at : ivec2, as_char : bool) #expand {
		src : *u8;
		if as_char {
			c := cast(u16)cast(u8)#char"A" + at.x;
			src = xx *c;
		} else {
			src = tprint("%\0", at.y + 1).data;
		}
		draw_text_cell(game_scene, at, src, caption_angle, BLACK);
	}

	if parts & .BACKGROUND {
		ClearBackground(.{xx background.x, xx background.y, xx background.z, 255});
	}
	BeginMode3D(camera);
	PushMatrix(); Translatef(toatal_translation.x, toatal_translation.y, toatal_translation.z);
		using board;
		i := 0;
		for y : 0..diam-1 {
			for x : 0..diam-1 {
				defer i += 1;
				cell_coord := ivec2.{xx x, xx y};
				cell := at(*board, cell_coord);
				pos := to_vec3(*board, cell_coord);
				if !my_array_find(banned_cell_coords, cell_coord) {
					if cell & .BORDER {
						DrawModel(model_cell, pos, .1, BLACK);					
					} else {
						cell_color := get_cell_color(cell_coord, cell, time, rules);
						DrawModel(model_cell, pos, 1, cell_color);
					}
				}
				if (cell & .FIGURE) {
					if !my_array_find(banned_figure_coords, cell_coord) {
						draw_figure(cell, pos, game_scene, ifx cell_coord == board_interface.selected then SELECTED_PIECE_SIZE else 1);
					}
				}
			}
		}
		if current_step.type == .NONE {
			if SHOW_POSSIBLE_STEPS && (parts & .HINTS) {
				for board_interface.shown_steps_capture {
					draw_step_option(game_scene, it, .{255, 0, 0, 100});
				} 
				for board_interface.shown_steps_move {
					draw_step_option(game_scene, it, .{0, 255, 0, 100});
				}
			}
			if SHOW_CLICKABLE_FIGURES && (parts & .HINTS) {
				figure_flag :Cell= xx(1 << current_player);
				for board_interface.clickable_figures_capture {
					if at(board, it) & figure_flag {
						draw_click_option(game_scene, it, .{255, 0, 0, 100});
					}
				}
				for board_interface.clickable_figures_move {
					if at(board, it) & figure_flag {
						draw_click_option(game_scene, it, .{0, 255, 0, 100});
					}
				}				
			}
		}

		draw_animation(game_scene, time);
		// DrawGrid(xx diam, CELL_SIZE);
		if current_step.type == .NONE {
			draw_cursor_selection_and_collision(game_scene, parts);
		}
		if parts & .CAPTIONS {
			for i : 0..diam-1 {
				draw_text_cell(.{xx diam, xx i}, false);
				draw_text_cell(.{-1, xx i}, false);
				draw_text_cell(.{xx i, xx diam}, true);
				draw_text_cell(.{xx i, -1}, true);
			}
		}
	PopMatrix();
	EndMode3D();

	if parts & .ROSE {
		ss := Vector2.{xx GetScreenWidth(), xx GetScreenHeight()};
		print("ss = %\n", ss);
		rs := ss.y * .25;
		yaw, pitch, r := to_yaw_pitch_r(camera.target - camera.position);
		DrawTexturePro(texture_rose,
			.{0, 0, xx texture_rose.width, xx texture_rose.height},
			.{ss.x - rs / 2, rs / 2, rs, rs},
			.{rs / 2, rs / 2},
			-yaw * 180 / PI,
			WHITE
		);
	}
	// DrawText("W", 0, 0, 100, MAGENTA);
	// DrawTextCodepoint(font, #char"W", .{0, 0}, 100, MAGENTA);

	#if DEBUG if parts & .DEBUG_INFO  {
		DrawFPS(20, 20);
		DrawText(temp_c_string(tprint(
				"step = %\ntime = %\nuncommited = %\ncursor = %\ncycle_id = %\nalive_count = %\nplayer = %\nis fina; = %\n",
				current_step,
				animation_time,
				board.uncommited_count,
				board_interface.cursor,
				board_interface.step_id,
				board_interface.alive_count,
				board_interface.current_player,
				board_interface.final
			)),
			20, 40, 20, RED
		);
	}
}
get_camera_bounds :: (using game_scene : Game_Scene) -> BoundingBox {
	R1 := CELL_SIZE * board.diam * 1.3;
	R2 := CELL_SIZE + FIGURE_HEIGHT * 4 + .1;
	R3 := R2 + CELL_SIZE * max(board.diam, 8) * 1.25;
	return .{
		.{-R1, R2, -R1},
		.{R1, R3, R1}
	};
}
