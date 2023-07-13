#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";
#import,dir "../rfoeraylib/Raylib";
using RL;

#load "board.jai";

Game_Data :: struct {
	rules := Rules.{diam = 12, cutoff = 2, rows = 2, must_capture = true};
	board : Board;
	board_interface : Board_Interface;

	cursor_collision : RayCollision;

	state : enum u8 {
		FIXED;
		MOVE;
	} = .FIXED;

	camera := Camera.{.{7, 5, 0}, .{0, 0, 0}, .{0, 1, 0}, 45, 0};

	BACKGROUND_COLORS :: Vector3.[
		.{100, 100, 100},
		.{200, 200, 255},
		.{255, 200, 200},
		.{200, 255, 200}
	];

	background := BACKGROUND_COLORS[0];
}

init_game :: (using game_data : *Game_Data) {
	init(*board, *rules);
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
		UpdateCamera(*camera, .FIRST_PERSON);
	}
	dt := min(GetFrameTime(), 1);
	background = background * (1 - dt) + BACKGROUND_COLORS[board.current_player] * dt;
}

process_input :: (using game_data : *Game_Data) {
	find_intersection(game_data);
	if state ==  {
		case .MOVE;
		if IsKeyPressed(.SPACE) || IsMouseButtonPressed(.LEFT) {
			state = .FIXED;
			center := GetWindowPosition() + Vector2.{600, 400};
			SetMousePosition(xx center.x, xx center.y);
			EnableCursor();
		}
		case .FIXED;
		if IsKeyPressed(.SPACE) {
			state = .MOVE;
			DisableCursor();			
		} else if IsMouseButtonPressed(.LEFT) {
			click(*board_interface);
		}
	}
}

find_intersection :: (using game_data : *Game_Data) {
	ray := GetMouseRay(GetMousePosition(), camera);
	S := Vector3.{xx board.diam, 1, xx board.diam} * .5;
	c0 := GetRayCollisionBox(ray, .{-.5 * S, .5 * S});
	ipos : ivec2;
	if c0.hit {
		pos := c0.point + .5 * S;
		ipos = .{xx (pos.x * 2), xx (pos.z * 2)};
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

draw_scene :: (using game_data : Game_Data) {
	BeginDrawing(); defer EndDrawing();
	// ClearBackground(GRAY);
	ClearBackground(.{xx background.x, xx background.y, xx background.z, 255});

	to_vec3 :: (x : int, y : int) -> Vector3 #expand {
		return (Vector3.{xx x, 0, xx y} - Vector3.{xx(diam - 1), 0, xx(diam - 1)} * .5) * .5;
	};
	BeginMode3D(camera);
		// DrawGrid(10, 1.0);
		using,except(rules) board;
		i := 0;
		for y : 0..diam-1 {
			for x : 0..diam-1 {
				defer i += 1;
				cell := at(*board, .{xx x, xx y});
				pos := to_vec3(x, y);
				if !(cell & .BORDER) {
					DrawCube(pos, .5, .3, .5, ifx (y + x) % 2 then WHITE else RAYWHITE);
				}
				if cell & .FIGURE {
					type := cell & .FIGURE_TYPE;
					color : Color;
					if type == {
						case .BLACK; color = BLACK;
						case .BLUE; color = BLUE;
						case .RED; color = RED;
						case .GREEN; color = GREEN;
						case; assert(false);
					}
					DrawCylinder(pos + Vector3.{0, .15, 0}, .2, .2, .1, 12, color);
					DrawCylinder(pos + Vector3.{0, .15, 0}, .15, .15, .11, 12, ifx cell & .KING_ANY then .{255, 255, 100, 255} else WHITE);
				}
			}
		}
		if state == .FIXED {
			cursor := board_interface.cursor;
			if cursor != .{-1, -1} then {
				assert(cursor_collision.hit);
				DrawCube(to_vec3(cursor.x, cursor.y), .6, .4, .6, .{0, 255, 0, 30});

				p1 := cursor_collision.point;
				p2 := p1 + .2 * cursor_collision.normal;
				DrawCube(p1, .05, .05, .05, SKYBLUE);
				DrawLine3D(p1, p2, BLUE);
			}
		}
		selected := board_interface.selected;
		if selected != .{-1, -1} then {
			DrawCube(to_vec3(selected.x, selected.y), .55, .35, .55, .{255, 0, 255, 30});
		} 
	EndMode3D();
	DrawFPS(20, 20);
}
