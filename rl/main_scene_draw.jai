draw_scene :: (using game_scene : Game_Scene) {
	draw_figure :: (cell : Cell, pos : Vector3, using game_scene : Game_Scene) {
		y_offset := 0.;
		draw_layer :: (pos: Vector3, color : Color, using game_scene : Game_Scene) #expand {
			DrawModel(model_cylinder, pos + Vector3.{0, CELL_HEIGHT / 2 + y_offset, 0}, 1, color);
			`y_offset += FIGURE_HEIGHT;
		}
		if board.leveled_upgrade {
			if cell & .KING_BLACK then draw_layer(pos, BLACK, game_scene);
			if cell & .KING_BLUE then draw_layer(pos, BLUE, game_scene);
			if cell & .KING_RED then draw_layer(pos, RED, game_scene);
			if cell & .KING_GREEN then draw_layer(pos, GREEN,game_scene);
		}
		DrawModel(
			model_cylinder,
			pos + Vector3.{0, CELL_HEIGHT / 2 + y_offset + FIGURE_HEIGHT * (1 - FIGURE_INNER_CIRCLE_RATIO) + .01, 0},
			FIGURE_INNER_CIRCLE_RATIO,
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
	draw_cursor_selection_and_collision :: (using game_scene : Game_Scene) {
		if cam_state == .FIXED {
			cursor := board_interface.cursor;
			if cursor != .{-1, -1} then {
				assert(cursor_collision.hit);
				#if DEBUG {
					p1 := cursor_collision.point;
					p2 := p1 + .2 * cursor_collision.normal;
					DrawCube(p1, .05, .05, .05, SKYBLUE);
					DrawLine3D(p1, p2, BLUE);					
				}
				DrawCube(to_vec3(*board, cursor), CELL_SIZE + SELECTION_GAP * 2, CELL_HEIGHT + SELECTION_GAP * 2, CELL_SIZE + SELECTION_GAP * 2, .{0, 255, 0, 30});
			}
		}
		selected := board_interface.selected;
		if selected != .{-1, -1} then {
			DrawCube(to_vec3(*board, selected), CELL_SIZE + SELECTION_GAP, CELL_HEIGHT + SELECTION_GAP, CELL_SIZE + SELECTION_GAP, .{255, 0, 255, 30});
		}
	}
	draw_mooving_figure :: (cell : Cell, from : ivec2, to : ivec2, t : float, using game_scene : Game_Scene) {
		p1, p2 := to_vec3(*board, from), to_vec3(board, to);
		pos := lerp(p1, p2, t);
		draw_figure(at(*board, from), pos, game_scene);
	}
	draw_animation :: (using game_scene : Game_Scene) {
		if current_step.type == {
			case .MOVE; using current_step.data_move;
			t := pow(animation_time, .5);
			draw_mooving_figure(at(*board, from), from, to, t, game_scene);
			case .CAPTURE; using current_step.data_capture;
			t := pow(animation_time, .5);
			draw_mooving_figure(at(*board, from), from, to, t, game_scene);
			delta := to - from;
			L := abs(delta.x) + abs(delta.y);
			if t < 1. - cast(float)over / L {
				killed_pos := to - dir * over;
				draw_figure(at(board, killed_pos), to_vec3(board, killed_pos), game_scene);
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

	camera : Camera = ---;
	if current_step.type == .STEPEND {
		camera = interpolate_cams(
			camera_backups[current_step.data_stepend.player_old],
			camera_backups[current_step.data_stepend.player_new],
			animation_time
		);
	} else {
		camera = camera_backups[board.current_player];
	}

	BeginDrawing(); defer EndDrawing();
	ClearBackground(.{xx background.x, xx background.y, xx background.z, 255});
	BeginMode3D(camera);
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
						draw_figure(cell, pos, game_scene);
					}
				}
			}
		}
		if current_step.type == .NONE {
			for board_interface.shown_steps_capture {
				draw_step_option(game_scene, it, .{255, 0, 0, 100});				
			} 
			for board_interface.shown_steps_move {
				draw_step_option(game_scene, it, .{0, 255, 0, 100});			
			}
		}

		draw_animation(game_scene);
		draw(*particle_system);
		// DrawGrid(xx diam, CELL_SIZE);
		if current_step.type == .NONE {
			draw_cursor_selection_and_collision(game_scene);
		}
		{
			for i : 0..diam-1 {
				draw_text_cell(.{xx diam, xx i}, false);
				draw_text_cell(.{-1, xx i}, false);
				draw_text_cell(.{xx i, xx diam}, true);
				draw_text_cell(.{xx i, -1}, true);
			}
		}
	EndMode3D();

	{
		ss := Vector2.{xx GetScreenWidth(), xx GetScreenHeight()};
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

	#if DEBUG {
		DrawFPS(20, 20);
		DrawText(temp_c_string(tprint(
				"step = %\ntime = %\nuncommited = %\ncursor = %\ncycle_id = %\nalive_count = %\nplayer = %\ncam_state = %\n",
				current_step,
				animation_time,
				board.uncommited_count,
				board_interface.cursor,
				board_interface.step_id,
				board_interface.alive_count,
				board_interface.current_player,
				cam_state
			)),
			20, 40, 20, RED
		);
	}
}
