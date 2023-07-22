#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";
#import,dir "../rfoeraylib/Raylib";
using RL;

#load "board.jai";
#import "Hash";

Game_Data :: struct {
	board := Board.{
		// rules = RULES_RUSSIAN
		// rules = RULES_CLASSIC
		rules = RULES_DEBUG
	};
	board_interface : Board_Interface;

	cursor_collision : RayCollision;

	state : enum u8 {
		FIXED;
		MOVE;
	} = .FIXED;
	mouse_state : enum u8 {
		FREE;
		HOLDING;
	}

	camera : Camera;
	background := BACKGROUND_COLORS[0];
}

using visual_properties : struct {
	BACKGROUND_COLORS :: Vector3.[
		.{150, 150, 150},
		.{200, 200, 255},
		.{255, 200, 200},
		.{200, 255, 200}
	];
	FIGURE_RADIUS :: .2;
	FIGURE_HEIGHT :: FIGURE_RADIUS * .5;
	FIGURE_INNER_CIRCLE_RADIUS :: FIGURE_RADIUS * .75;
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
}
deinit_game :: (using game_data : *Game_Data) {
	deinit(*board);
}

main :: () {
	defer report_memory_leaks();

	using game_data : Game_Data;
	init_game(*game_data); defer deinit_game(*game_data);

	W0, H0 :: 1200, 800;
	SetConfigFlags(.WINDOW_RESIZABLE);
    SetConfigFlags(.MSAA_4X_HINT);
	InitWindow(W0, H0, "c4eckers?"); defer CloseWindow();
	SetTargetFPS(60);

	{
		center := GetWindowPosition() + Vector2.{600, 400};
		SetMousePosition(xx center.x, xx center.y);
	}

	while !WindowShouldClose() {
		process_input(*game_data);
		simulate(*game_data);
		draw_scene(game_data);
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
	dt := min(GetFrameTime(), 1);
	background = background * (1 - dt) + BACKGROUND_COLORS[board.current_player] * dt;
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
			click(*board_interface);
		} else if IsMouseButtonPressed(.RIGHT) {
			if board_interface.selected != .{-1, -1} then {
				board_interface.cursor = board_interface.selected;
				click(*board_interface);
			} else {
				state = .MOVE;
				DisableCursor();
			}
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
			cell := at(*board, .{xx x, xx y});
			pos := to_vec3(*board, x, y);
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

to_vec3 :: (using board : *Board, x : int, y : int) -> Vector3 {
	return (Vector3.{xx x, 0, xx y} - Vector3.{xx(diam - 1), 0, xx(diam - 1)} * .5) * CELL_SIZE;
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

draw_scene :: (using game_data : Game_Data) {
	BeginDrawing(); defer EndDrawing();
	// ClearBackground(GRAY);
	ClearBackground(.{xx background.x, xx background.y, xx background.z, 255});

	draw_figure :: (cell : Cell, pos : Vector3, rules : Rules) {
		y_offset := 0.;
		draw_layer :: (pos: Vector3, color : Color) #expand {
			DrawCylinder(pos + Vector3.{0, CELL_HEIGHT / 2 + y_offset, 0}, FIGURE_RADIUS, FIGURE_RADIUS, FIGURE_HEIGHT, CYLINDER_QUALITY, color);
			`y_offset += FIGURE_HEIGHT;
		}
		if rules.leveled_upgrade {
			if cell & .KING_BLACK then draw_layer(pos, BLACK);
			if cell & .KING_BLUE then draw_layer(pos, BLUE);
			if cell & .KING_RED then draw_layer(pos, RED);
			if cell & .KING_GREEN then draw_layer(pos, GREEN);			
		}
		DrawCylinder(
			pos + Vector3.{0, CELL_HEIGHT / 2 + y_offset, 0},
			FIGURE_INNER_CIRCLE_RADIUS, FIGURE_INNER_CIRCLE_RADIUS, FIGURE_HEIGHT + .01, CYLINDER_QUALITY, 
			ifx !rules.leveled_upgrade && (cell & .KING_ANY) then .{255, 255, 100, 255} else WHITE
		);		

		type := cell & .FIGURE_TYPE;
		color_top : Color;
		if type == {
			case .BLACK; color_top = BLACK;
			case .BLUE; color_top = BLUE;
			case .RED; color_top = RED;
			case .GREEN; color_top = GREEN;
			case; assert(false);
		}
		draw_layer(pos, color_top);
	}

	get_cell_color :: (p : ivec2, using rules : Rules) -> Color {
		factor :: .1;
		if (p.x + p.y) % 2 return WHITE;
		#if COLOR_ZONES {
			if p.y < cutoff return mix(RAYWHITE, GREEN, factor);
			if p.y >= diam - cutoff return mix(RAYWHITE, BLUE, factor);
			if p.x < cutoff return mix(RAYWHITE, RED, factor);
			// if p.x >= diam - cutoff return mix(RAYWHITE, BLACK, factor);			
		}
		return RAYWHITE;
	}
	BeginMode3D(camera);
		using board;
		i := 0;

		#if SHINING_BORDERS {
			time := GetTime();
		}

		for y : 0..diam-1 {
			for x : 0..diam-1 {
				defer i += 1;
				cell := at(*board, .{xx x, xx y});
				pos := to_vec3(*board, x, y);
				if !(cell & .BORDER) {
					cell_color := get_cell_color(.{xx x, xx y}, rules);
					#if SHINING_BORDERS if cell & .BOOSTS {
						h1 := cast(float)get_hash(y + xx get_hash(x)) / U32_MAX;
						h2 := cast(float)get_hash(x + xx get_hash(y)) / U32_MAX;

						factor := (sin(time * (2 + h1 * 2) + h2 * 10) + 1) * .03;
						cell_color = mix(cell_color, MAGENTA, xx factor);
					}
					DrawCube(pos, CELL_SIZE, CELL_HEIGHT, CELL_SIZE, cell_color);
				}
				if cell & .FIGURE then draw_figure(cell, pos, rules);
			}
		}
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
				DrawCube(to_vec3(*board, cursor.x, cursor.y), CELL_SIZE + SELECTION_GAP * 2, CELL_HEIGHT + SELECTION_GAP * 2, CELL_SIZE + SELECTION_GAP * 2, .{0, 255, 0, 30});
			}
		}
		selected := board_interface.selected;
		if selected != .{-1, -1} then {
			DrawCube(to_vec3(*board, selected.x, selected.y), CELL_SIZE + SELECTION_GAP, CELL_HEIGHT + SELECTION_GAP, CELL_SIZE + SELECTION_GAP, .{255, 0, 255, 30});
		} 
	EndMode3D();
	#if DEBUG DrawFPS(20, 20);
}
