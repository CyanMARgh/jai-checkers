#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";
#import,dir "../raylib-jai-universal/Raylib";
#import "Hash";

#load "networking.jai";
#load "board.jai";
// #load "stream_group.jai";
#load "particle_system.jai";
#load "text3d.jai";

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

	ENABLE_CAMERA_ROTATION :: true;
}
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
				rows = 2,
				diam = 10,
				cutoff = 3,
				enable_border = true,
				border_period = 8,
				must_continue_capture = true
			}
			// rules = .{
			// 	must_capture = true,
			// 	diagonal = false,
			// 	leveled_upgrade = false,
			// 	rows_offset = 1,
			// 	rows = 2,
			// 	diam = 8,
			// 	cutoff = 0,
			// 	enable_border = true,
			// 	border_period = 100,
			// 	must_continue_capture = true,
			// 	two_players = true,
			// 	// _180_no_scope = true
			// }
		};
	} else {
		board := Board.{
			rules = RULES_CLASSIC
		};
	}
	board_interface : Board_Interface;

	cam_state : enum u8 {
		FIXED;
		MOVE;
		RAIL;
	} = .FIXED;

	camera : Camera;
	camera_backups : [5]Camera;

	cursor_collision : RayCollision;
	delta_time, time := 0.;

	using visual_data : struct {
		background := BACKGROUND_COLORS[0];

		particle_system := Particle_System.{particles_count = 10000};
		model_cell : Model;
		model_cylinder : Model;
		model_sphere : Model;

		texture_rose : Texture;

		caption_angle := 90.;
		animation_time := 0.;
		current_step := Step.{type = .NONE};
		banned_figure_coords : [2]ivec2;
		banned_cell_coords : [1]ivec2;

		font : Font;
	};	
	// using audio_data : Audio_Controller;

	using networking_data : Networking_Data;
}
// Audio_Controller :: struct {
// 	Sound_Type :: enum u8 {
// 		SLIDE;
// 		CRACK;
// 		UPGRADE;
// 	}
// 	stream_group_slide : Stream_Group;
// 	stream_group_crack : Stream_Group;
// 	stream_group_upgrade : Stream_Group;
// };

parse_command_line_arguments :: (using game_data: *Game_Data) {
	args := get_command_line_arguments();
	if args.count > 1 {
		am_server = false;
		client_data = .{ server_address = args[1] };
	} else {
		am_server = true;
		server_data = .{};
	}
}

init_game :: (using game_data : *Game_Data) {
	// logic
		init(*board);
		board_interface.board = *board;
		board_interface.player_me = ifx am_server then 0 else 4;
		init_cameras(game_data);
	// visual
		W0, H0 :: 1200, 800;
		SetConfigFlags(.WINDOW_RESIZABLE);
		SetConfigFlags(.MSAA_4X_HINT);
		InitWindow(W0, H0, "c4eckers!");
		gl_load(*gl);
		SetTargetFPS(60);

		font = GetFontDefault();
		texture_rose = LoadTexture("res/rose.png");
	
		model_cell = LoadModelFromMesh(GenMeshCube(CELL_SIZE, CELL_HEIGHT, CELL_SIZE));
		model_cylinder = LoadModelFromMesh(GenMeshCylinder(FIGURE_RADIUS, FIGURE_HEIGHT, 16));
		model_sphere = LoadModelFromMesh(GenMeshSphere(1, 16, 16));

		init(*particle_system);
	// audio
		// InitAudioDevice();
		// stream_group_slide = make_stream_group("res/slide2.mp3");
		// stream_group_crack = make_stream_group("res/crack.wav");
		// stream_group_upgrade = make_stream_group("res/upgrade.wav");
}
deinit_game :: (using game_data : *Game_Data) {
	// audio
		// deinit(*stream_group_upgrade);
		// deinit(*stream_group_crack);
		// deinit(*stream_group_slide);
		// CloseAudioDevice();
	// visual_data
		deinit(*particle_system);
		
		UnloadModel(model_sphere);
		UnloadModel(model_cylinder);
		UnloadModel(model_cell);

		UnloadTexture(texture_rose);
		
		CloseWindow();
	// logic
		deinit(*board_interface);
}
main :: () {
	defer report_memory_leaks();
 

	using game_data : Game_Data;
	parse_command_line_arguments(*game_data);
	init_networking(*game_data);
	init_game(*game_data); defer deinit_game(*game_data);

	while !WindowShouldClose() {
		delta_time, time = xx min(GetFrameTime(), 1), xx GetTime();
		process_input(*game_data);
		// update(*stream_group_slide);
		// update(*stream_group_crack);
		// update(*stream_group_upgrade);
		simulate(*game_data);
		draw_scene(game_data);
		do_networking(*game_data);
		reset_temporary_storage();
	}
}
simulate :: (using game_data : *Game_Data) {
	if cam_state == .MOVE {
		R1 := CELL_SIZE * board.diam * 1.3;
		R2 := CELL_SIZE + FIGURE_HEIGHT * 4 + .1;
		R3 := R2 + CELL_SIZE * max(board.diam, 8) * 1.25;
		camera_bounds := BoundingBox.{
			.{-R1, R2, -R1},
			.{R1, R3, R1}
		};
		move_camera(*camera, camera_bounds, 1.);
	}
	background = background * (1 - delta_time) + BACKGROUND_COLORS[board.current_player] * delta_time
		// * (ifx am_server then 1.0 else 0.3)
		;
	process_unapplied_steps(game_data);
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

reset_camera :: (using game_data : *Game_Data, id : int) {
	VV :: Vector3.[.{1, 0, 0}, .{0, 0, 1}, .{-1, 0, 0}, .{0, 0, -1}, .{0.01, 1, 0}];
	camera_backups[id] = .{
		(VV[id] + .{0, 1, 0}) * (CELL_SIZE * board.diam),
		(VV[id] * .1 + .{0, 0, 0}) * (CELL_SIZE * board.diam),
		.{0, 1, 0}, 45, 0
	};
}
init_cameras :: (using game_data : *Game_Data) {
	for 0..4 reset_camera(game_data, it);
	camera = camera_backups[board.current_player];	
}
reset_this_camera :: (using game_data : *Game_Data) {
	reset_camera(game_data, board.current_player);
	camera = camera_backups[board.current_player];
}
process_input :: (using game_data : *Game_Data) {
	find_intersection(game_data);
	if cam_state ==  {
		case .MOVE;
		if IsMouseButtonPressed(.LEFT) || IsMouseButtonPressed(.RIGHT) {
			cam_state = .FIXED;
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
			cam_state = .MOVE;
			DisableCursor();
		}
	}
	if IsKeyPressed(.R) {
		reset_this_camera(game_data);
	} else if IsKeyPressed(.S) {
		tmp := copy(board); defer deinit(*tmp);
		ok := save_board(board, "b1.board");
		assert(ok);
		deinit(*board);
		ok = load_board(*board, "b1.board");
		assert(ok);
		assert(is_same(tmp, board));
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

to_yaw_pitch_r :: (using v : Vector3) -> yaw:float, pitch:float, r:float {
	rxz := sqrt(x * x + z * z);
	return atan2(z, x), atan2(y, rxz), sqrt(x * x + y * y + z * z);
}
from_yaw_pitch_r :: (yaw : float, pitch : float, r : float) -> Vector3 {
	return r * Vector3.{cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw)};
}
interpolate_cams :: (cam_a : Camera, cam_b : Camera, t : float) -> Camera {
	to_local_direction :: (d0 : Vector3, d1 : Vector3) -> Vector3 {
		d2x := d0.x * d1.x + d0.z * d1.z;
		d2z := d0.x * d1.z - d0.z * d1.x;
		r1 := sqrt(d1.x * d1.x + d1.z * d1.z);
		r2 := sqrt(d2x * d2x + d2z * d2z);
		d2x *= r1 / r2;
		d2z *= r1 / r2;
		return .{d2x, d1.y, d2z};
	}
	to_global_direction :: (d0 : Vector3, d1 : Vector3) -> Vector3 {
		d2x := d0.x * d1.x - d0.z * d1.z;
		d2z := d0.x * d1.z + d0.z * d1.x;
		r1 := sqrt(d1.x * d1.x + d1.z * d1.z);
		r2 := sqrt(d2x * d2x + d2z * d2z);
		d2x *= r1 / r2;
		d2z *= r1 / r2;
		return .{d2x, d1.y, d2z};
	}
	interpolate_cyclic :: (a : float, b : float, t : float, M : float) -> float {
		if b < a then a, b, t = b, a, 1 - t;
		if abs(b - a) < M * .5 {
			return lerp(a, b, t);
		} else {
			return fmod_cycling(lerp(a + M, b, t), M);
		}
	}
	interpolade_dir :: (a : Vector3, b : Vector3, t : float) -> Vector3 {
		yaw_a, pitch_a, r_a := to_yaw_pitch_r(a);
		yaw_b, pitch_b, r_b := to_yaw_pitch_r(b);
		pitch := lerp(pitch_a, pitch_b, t);
		yaw := interpolate_cyclic(yaw_a + PI, yaw_b + PI, t, TAU) - PI;
		// print("%, % --(%)--> %\n", yaw_a, yaw_b, t, yaw);
		r := lerp(r_a, r_b, t);
		return from_yaw_pitch_r(yaw, pitch, r);
	}
	pos_a := cam_a.position;
	pos_b := cam_b.position;

	dir_a := normalize(cam_a.target - cam_a.position);
	dir_b := normalize(cam_b.target - cam_b.position);
	dir_a = to_local_direction(-pos_a, dir_a);
	dir_b = to_local_direction(-pos_b, dir_b);

	pos := interpolade_dir(pos_a, pos_b, t);
	dir := interpolade_dir(dir_a, dir_b, t);
	dir = to_global_direction(-pos, dir);

	return .{
		pos,
		pos + dir,
		// target,
		cam_a.up,
		cam_a.fovy,
		cam_a.projection
	};
}

process_unapplied_steps :: (using game_data : *Game_Data) {
	try_start_new_animation :: (using game_data : *Game_Data) {
		current_step = get_step_to_animate(board);
		animation_time = 0;

		if current_step.type == {
			case .UPGRADE; using current_step.data_upgrade;
			point := to_vec3(board, pos) + .{0, CELL_HEIGHT / 2, 0};
			diff := aft & ~bef;
			if diff & .KING_RED emit(*particle_system, point, base_color = RED);
			if diff & .KING_BLUE emit(*particle_system, point, base_color = BLUE);
			if diff & .KING_BLACK emit(*particle_system, point, base_color = BLACK);
			if diff & .KING_GREEN emit(*particle_system, point, base_color = GREEN);
			case .MOVE;
			// play(*stream_group_slide);
			case .CAPTURE;
			// play(*stream_group_slide);
			// play(*stream_group_crack);
			case .STEPEND; using current_step.data_stepend;
			caption_angle = (1 - player_new) * 90.; 
			if ENABLE_CAMERA_ROTATION {
				camera_backups[player_old] = camera;
				cam_state = .RAIL;				
			}
			// camera = camera_backups[player_new];
		}
	}
	update_animation :: (using game_data : *Game_Data) -> current_animation_ended:bool {
		if current_step.type == {
			case .NONE;
			return false;
			case .MOVE;
			animation_time += 5 * delta_time;
			case .CAPTURE;
			animation_time += 5 * delta_time;
			case .BORDER;
			animation_time += 5 * delta_time;
			case .STEPEND; using current_step.data_stepend;
			if ENABLE_CAMERA_ROTATION {
				animation_time += 2 * delta_time;
				smoothstep :: t => 3 * t * t - 2 * t * t * t;
				camera = interpolate_cams(camera_backups[player_old], camera_backups[player_new], smoothstep(animation_time));				
			} else {
				return true;
			}
			case;
			return true;
		}
		return animation_time >= 1;
	}
	animation_end :: (using game_data : *Game_Data) {
		if current_step.type == {
			case .STEPEND; using current_step.data_stepend;
			if ENABLE_CAMERA_ROTATION {
				camera = camera_backups[player_new];
				cam_state = .FIXED;				
			}
		}
	}
	set_blacklist :: (using game_data : *Game_Data) {
		banned_figure_coords = .[.{-1, -1}, .{-1, -1}];
		banned_cell_coords = .[.{-1, -1}];
		if current_step.type == {
			case .MOVE; using current_step.data_move;
			banned_figure_coords[0] = from;
			case .CAPTURE; using current_step.data_capture;
			banned_figure_coords[0] = from;
			banned_figure_coords[1] = to - dir;
			case .BORDER; using current_step.data_border;
			banned_figure_coords[0] = pos;
			banned_cell_coords[0] = pos;
		}
	}
	if current_step.type == .NONE {
		try_start_new_animation(game_data);
	}
	while update_animation(game_data) {
		animation_end(game_data);
		redo_single(*board);
		try_start_new_animation(game_data);
	}
	set_blacklist(game_data);
}
draw_scene :: (using game_data : Game_Data) {
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
	draw_cursor_selection_and_collision :: (using game_data : Game_Data) {
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
	draw_mooving_figure :: (cell : Cell, from : ivec2, to : ivec2, t : float, using game_data : Game_Data) {
		p1, p2 := to_vec3(*board, from), to_vec3(board, to);
		pos := lerp(p1, p2, t);
		draw_figure(at(*board, from), pos, game_data);
	}
	draw_animation :: (using game_data : Game_Data) {
		if current_step.type == {
			case .MOVE; using current_step.data_move;
			t := pow(animation_time, .5);
			draw_mooving_figure(at(*board, from), from, to, t, game_data);
			case .CAPTURE; using current_step.data_capture;
			t := pow(animation_time, .5);
			draw_mooving_figure(at(*board, from), from, to, t, game_data);
			delta := to - from;
			L := abs(delta.x) + abs(delta.y);
			if t < 1. - 1. / L {
				draw_figure(at(board, to - dir), to_vec3(board, to - dir), game_data);
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
	draw_step_option :: (using game_data : Game_Data, at : ivec2, color : Color) {
		pos := to_vec3(board, at) + .{0, CELL_HEIGHT, 0};
		DrawModel(model_sphere, pos, .1, color);
	}
	draw_text_cell :: (using game_data : Game_Data, at : ivec2, src : *u8, angle : float, color : Color) {
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
		draw_text_cell(game_data, at, src, caption_angle, BLACK);
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
						draw_figure(cell, pos, game_data);
					}
				}
			}
		}
		if current_step.type == .NONE {
			for board_interface.shown_steps_capture {
				draw_step_option(game_data, it, .{255, 0, 0, 100});				
			} 
			for board_interface.shown_steps_move {
				draw_step_option(game_data, it, .{0, 255, 0, 100});			
			}
		}

		draw_animation(game_data);
		draw(*particle_system);
		// DrawGrid(xx diam, CELL_SIZE);
		draw_cursor_selection_and_collision(game_data);
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
		builder: String_Builder;
		builder.allocator = temporary_allocator;
		print_to_builder(*builder, #string END
step = %
time = %
uncommited = %
cursor = %
cycle_id = %
alive_count = %
player = %
cam_state = %
player_me = %
END,
			current_step,
			animation_time,
			board.uncommited_count,
			board_interface.cursor,
			board_interface.step_id,
			board_interface.alive_count,
			board_interface.current_player,
			cam_state,
			board_interface.player_me,
		);
		if am_server {
			for client_connections {
				print_to_builder(*builder, "client %: %\n", it_index + 1, it.state);
			}
		} else {
			print_to_builder(*builder, "server: %\n", server_connection.state);
		}
		append(*builder, "\0");
		DrawText(builder_to_string(*builder).data, 20, 40, 20, RED);
	}
}
