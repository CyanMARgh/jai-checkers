#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";
#import,dir "../rfoeraylib/Raylib";
using RL;

#load "board.jai";
#import "Hash";
#load "particle_system.jai";

Game_Data :: struct {
	#if DEBUG {
		board := Board.{
			// rules = RULES_RUSSIAN
			// rules = RULES_DEBUG
			rules = .{
				must_capture = true,
				diagonal = false,
				leveled_upgrade = true,
				rows_offset = 1,
				rows = 1,
				diam = 8,
				cutoff = 2,
				enable_border = true,
				border_period = 4
			}
		};
	} else {
		board := Board.{
			rules = RULES_CLASSIC
		};
	}
	board_interface : Board_Interface;

	cursor_collision : RayCollision;

	state : enum u8 {
		FIXED;
		MOVE;
	} = .FIXED;

	camera : Camera;
	background := BACKGROUND_COLORS[0];
	delta_time, time := 0.;
	animation_time := 0.;

	particle_system := Particle_System.{particles_count = 10000};
	model_cell : Model;
	model_cylinder : Model;
}

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
}

init_game :: (using game_data : *Game_Data) {
	reset_camera(game_data);
	init(*board);
	board_interface.board = *board;

	init(*particle_system);
	model_cell = LoadModelFromMesh(GenMeshCube(CELL_SIZE, CELL_HEIGHT, CELL_SIZE));
	model_cylinder = LoadModelFromMesh(GenMeshCylinder(FIGURE_RADIUS, FIGURE_HEIGHT, 16));
}
deinit_game :: (using game_data : *Game_Data) {
	UnloadModel(model_cylinder);
	UnloadModel(model_cell);
	deinit(*particle_system);
	deinit(*board);
}
main :: () {
	defer report_memory_leaks();

	W0, H0 :: 1200, 800;
	SetConfigFlags(.WINDOW_RESIZABLE);
	SetConfigFlags(.MSAA_4X_HINT);
	InitWindow(W0, H0, "c4eckers?"); defer CloseWindow();
	gl_load(*gl);
	SetTargetFPS(60);
	{
		center := GetWindowPosition() + Vector2.{W0 / 2, H0 / 2};
		SetMousePosition(xx center.x, xx center.y);
	}

	using game_data : Game_Data;
	init_game(*game_data); defer deinit_game(*game_data);

	while !WindowShouldClose() {
		delta_time, time = xx min(GetFrameTime(), 1), xx GetTime();
		process_input(*game_data);
		simulate(*game_data);
		draw_scene(*game_data);
		reset_temporary_storage();
	}
}
simulate :: (using game_data : *Game_Data) {
	if state == .MOVE {
		R1 := CELL_SIZE * board.diam * 1.3;
		R2 := CELL_SIZE + FIGURE_HEIGHT * 4 + .1;
		R3 := R2 + CELL_SIZE * max(board.diam, 8) * 1.25;
		camera_bounds := BoundingBox.{
			.{-R1, R2, -R1},
			.{R1, R3, R1}
		};
		move_camera(*camera, camera_bounds, 1.);
	}
	background = background * (1 - delta_time) + BACKGROUND_COLORS[board.current_player] * delta_time;
	simulate(*particle_system, delta_time);
}
move_camera :: (camera : *Camera, bounds : BoundingBox, speed_factor : float) {
	update_camera_free_move(camera, speed_factor);

	clamp :: (v : Vector3, a : Vector3, b : Vector3) -> Vector3 {
		return .{
			clamp(v.x, a.x, b.x),
			clamp(v.y, a.y, b.y),
			clamp(v.z, a.z, b.z)
		};
	}

	clamped_position := clamp(camera.position, bounds.min, bounds.max);
	camera.target += clamped_position - camera.position;
	camera.position = clamped_position;
}
reset_camera :: (using game_data : *Game_Data) {
	camera = Camera.{Vector3.{8, 6, 0} * (cast(float)board.diam / 16), .{0, 0, 0}, .{0, 1, 0}, 45, 0};
}
process_input :: (using game_data : *Game_Data) {
	find_intersection(game_data);
	if state ==  {
		case .MOVE;
		if IsMouseButtonPressed(.LEFT) || IsMouseButtonPressed(.RIGHT) {
			state = .FIXED;
			center := GetWindowPosition() + Vector2.{600, 400};
			SetMousePosition(xx center.x, xx center.y);
			EnableCursor();
		}
		case .FIXED;
		if IsMouseButtonPressed(.LEFT) {
			if board_interface.cursor != .{-1, -1} {
				nodes := click(*board_interface);
				for 1..nodes {
					undo_single(*board);
				}				
			}
		} else if IsMouseButtonPressed(.RIGHT) {
			state = .MOVE;
			DisableCursor();
		}
	}
	if IsKeyPressed(.R) {
		reset_camera(game_data);
	}
}
find_intersection :: (using game_data : *Game_Data) {
	ray := GetMouseRay(GetMousePosition(), camera);
	S := Vector3.{xx board.diam * CELL_SIZE, CELL_HEIGHT, xx board.diam * CELL_SIZE};
	c0 := GetRayCollisionBox(ray, .{-.5 * S, .5 * S});

	for y : 0..board.diam-1 {
		for x : 0..board.diam-1 {
			cell_coord := ivec2.{xx x, xx y};
			cell := at(*board, cell_coord);
			pos := to_vec3(*board, cell_coord);
			if cell & .FIGURE {
				level := cell_level(cell);
				c1 := GetRayCollisionCylinder(ray, pos, pos + Vector3.{0, CELL_HEIGHT / 2 + FIGURE_HEIGHT * (1 + level), 0}, FIGURE_RADIUS);
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
to_vec3 :: (using board : Board, cell_coord : ivec2) -> Vector3 {
	return (Vector3.{xx cell_coord.x, 0, xx cell_coord.y} - Vector3.{xx(diam - 1), 0, xx(diam - 1)} * .5) * CELL_SIZE;
}
mix :: (c1 : Color, c2 : Color, x : float) -> Color {
	mix :: (a : u8, b : u8, x : float) -> u8 {
		return cast(u8)(a * (1 - x) + b * x);
	}
	return .{
		mix(c1.r, c2.r, x),
		mix(c1.g, c2.g, x),
		mix(c1.b, c2.b, x),
		mix(c1.a, c2.a, x)
	};
}
draw_scene :: (using game_data : *Game_Data) {
	draw_figure :: (cell : Cell, pos : Vector3, using game_data : Game_Data) {
		y_offset := 0.;
		draw_layer :: (pos: Vector3, color : Color, using game_data : Game_Data) #expand {
			DrawModel(model_cylinder, pos + Vector3.{0, CELL_HEIGHT / 2 + y_offset, 0}, 1, color);
			`y_offset += FIGURE_HEIGHT;
		}
		if board.leveled_upgrade {
			if cell & .KING_BLACK then draw_layer(pos, BLACK, game_data);
			if cell & .KING_BLUE then draw_layer(pos, BLUE, game_data);
			if cell & .KING_RED then draw_layer(pos, RED, game_data);
			if cell & .KING_GREEN then draw_layer(pos, GREEN,game_data);
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
		draw_layer(pos, color_top, game_data);
	}
	get_cell_color :: (p : ivec2, cell : Cell, time : float, using rules : Rules) -> Color {
		factor :: .1;
		cell_color := RAYWHITE;
		if (p.x + p.y) % 2 {
			cell_color = WHITE;
		} else #if COLOR_ZONES {
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
	draw_cursor_selection_and_collision :: (using game_data : Game_Data) {
		if state == .FIXED {
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
	update_animation_time :: (using game_data : *Game_Data, speed : float) -> continue_animation:bool {
		animation_time += delta_time * speed;
		if animation_time > 1 {
			redo_single(*board);
			animation_time = 0;
			return false;			
		} else {
			return true;
		}
	}
	draw_mooving_figure :: (cell : Cell, from : ivec2, to : ivec2, t : float, using game_data : Game_Data) {
		p1, p2 := to_vec3(*board, from), to_vec3(board, to);
		pos := lerp(p1, p2, t);
		draw_figure(at(*board, from), pos, game_data);
	}
	draw_animation :: () -> bool #expand {
		main_draw_cycle_blacklist = .[.{-1, -1}, .{-1 ,-1}];
		step = get_step_to_animate(board);
		if step.type == {
			case .MOVE; using step.data_move;
			if update_animation_time(game_data, 8) {
				main_draw_cycle_blacklist[0] = from;
				t := pow(animation_time, .5);
				draw_mooving_figure(at(*board, from), from, to, t, game_data);
			} else {
				return true;
			}
			case .CAPTURE; using step.data_capture;
			if update_animation_time(game_data, 8) {
				main_draw_cycle_blacklist[0] = from;
				main_draw_cycle_blacklist[1] = to - dir;
				t := pow(animation_time, .5);				
				draw_mooving_figure(at(*board, from), from, to, t, game_data);
				delta := to - from;
				L := abs(delta.x) + abs(delta.y);
				if t < 1. - 1. / L {
					draw_figure(at(board, to - dir), to_vec3(board, to - dir), game_data);
				}
			} else {
				return true;
			}
			case .BORDER; using step.data_border;
			if !update_animation_time(game_data, 8) return true;
			case .UPGRADE; using step.data_upgrade;
			point := to_vec3(board, pos) + .{0, CELL_HEIGHT / 2, 0};
			diff := aft & ~bef;
			if diff & .KING_RED emit(*particle_system, point, base_color = RED);
			if diff & .KING_BLUE emit(*particle_system, point, base_color = BLUE);
			if diff & .KING_BLACK emit(*particle_system, point, base_color = BLACK);
			if diff & .KING_GREEN emit(*particle_system, point, base_color = GREEN);

			redo_single(*board);
			case .NONE;
			case;
			redo_single(*board);
			return true;
		}
		return false;
	}

	BeginDrawing(); defer EndDrawing();
	ClearBackground(.{xx background.x, xx background.y, xx background.z, 255});
	BeginMode3D(camera);
		using board;
		main_draw_cycle_blacklist : [2]ivec2;
		step : Step;
		while draw_animation() {
			// log("(4)\n");
		}
		i := 0;
		for y : 0..diam-1 {
			for x : 0..diam-1 {
				defer i += 1;
				cell_coord := ivec2.{xx x, xx y};
				cell := at(*board, cell_coord);
				pos := to_vec3(*board, cell_coord);
				if !(cell & .BORDER) {
					cell_color := get_cell_color(cell_coord, cell, time, rules);
					DrawModel(model_cell, pos, 1, cell_color);
				}
				if (cell & .FIGURE) {
					if !my_array_find(main_draw_cycle_blacklist, cell_coord) {
						draw_figure(cell, pos, game_data);
					}
				}
			}
		}
		draw(*particle_system);
		draw_cursor_selection_and_collision(game_data);
	EndMode3D();
	#if DEBUG {
		DrawFPS(20, 20);
		DrawText(temp_c_string(tprint(
				"step = %\ntime = %\nuncommited = %\ncursor = %\ncycle_id = %\nalive_count = %\nplayer = %\n",
				step,
				animation_time,
				board.uncommited_count,
				board_interface.cursor,
				board_interface.step_id,
				board_interface.alive_count,
				board_interface.current_player
			)),
			20, 40, 20, RED
		);
	}
}
