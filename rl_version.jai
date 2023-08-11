#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";
#import "Raylib";
#import "Hash";

#load "board.jai";
// #load "stream_group.jai";
#load "rl/particle_system.jai";
#load "rl/text3d.jai";
#load "rl/window_and_resources.jai";
#load "rl/main_scene_draw.jai";

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
Game_Scene :: struct {
	#if DEBUG {
		board := Board.{
			// rules = RULES_RUSSIAN
			// rules = RULES_DEBUG
			// rules = .{
			// 	must_capture = true,
			// 	diagonal = false,
			// 	leveled_upgrade = true,
			// 	rows_offset = 1,
			// 	rows = 2,
			// 	diam = 10,
			// 	cutoff = 3,
			// 	enable_border = true,
			// 	border_period = 8,
			// 	must_continue_capture = true
			// }
			rules = .{
				must_capture = true,
				diagonal = false,
				leveled_upgrade = false,
				rows_offset = 1,
				rows = 2,
				diam = 8,
				cutoff = 0,
				enable_border = true,
				border_period = 100,
				must_continue_capture = true,
				two_players = true,
				land_right_behind = false,
				// _180_no_scope = true
			}
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

		caption_angle := 90.;
		animation_time := 0.;
		current_step := Step.{type = .NONE};
		banned_figure_coords : [2]ivec2;
		banned_cell_coords : [1]ivec2;
	};	
	// using audio_data : Audio_Controller;
}

requests_queue : Queue(Board_Request);
add_some_request :: () {
	push(*requests_queue, .{
			sender_id = 2,
			click_pos = .{2, 6},
			new_nodes = .[]
		}
	);
	push(*requests_queue, .{
			sender_id = 2,
			click_pos = .{3, 6},
			new_nodes = array_copy(Step.[
				.{type = .MOVE, data_move = .{from = .{2, 6}, to = .{3, 6}}},
				.{type = .STEPEND, data_stepend = .{player_old = 2, player_new = 0}}
			])
		}
	);
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

init_main_scene :: (using game_scene : *Game_Scene) {
	init(*board);
	board_interface.board = *board;
	init_cameras(game_scene);
}
deinit_main_scene :: (using game_scene : *Game_Scene) {
	deinit(*board_interface);
}
main :: () {
	defer report_memory_leaks(); 
	init_window_and_resources(); defer deinit_window_and_resources();

	using game_scene : Game_Scene;
	init_main_scene(*game_scene); defer deinit_main_scene(*game_scene);
	defer deinit(*requests_queue);

	while !WindowShouldClose() {
		delta_time, time = xx min(GetFrameTime(), 1), xx GetTime();
		process_input(*game_scene);
		if board.uncommited_count == 0 {
			request, ok := pop(*requests_queue);
			if ok {
				process_request(*game_scene, request);
				array_free(request.new_nodes);
			}
		}
		// update(*stream_group_slide);
		// update(*stream_group_crack);
		// update(*stream_group_upgrade);
		simulate(*game_scene);
		draw_scene(game_scene);
		reset_temporary_storage();
	}
}
simulate :: (using game_scene : *Game_Scene) {
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
	background = background * (1 - delta_time) + BACKGROUND_COLORS[board.current_player] * delta_time;
	process_unapplied_steps(game_scene);
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

reset_camera :: (using game_scene : *Game_Scene, id : int) {
	VV :: Vector3.[.{1, 0, 0}, .{0, 0, 1}, .{-1, 0, 0}, .{0, 0, -1}, .{0.01, 1, 0}];
	camera_backups[id] = .{
		(VV[id] + .{0, 1, 0}) * (CELL_SIZE * board.diam),
		(VV[id] * .1 + .{0, 0, 0}) * (CELL_SIZE * board.diam),
		.{0, 1, 0}, 45, 0
	};
}
init_cameras :: (using game_scene : *Game_Scene) {
	for 0..4 reset_camera(game_scene, it);
	camera = camera_backups[board.current_player];	
}
reset_this_camera :: (using game_scene : *Game_Scene) {
	reset_camera(game_scene, board.current_player);
	camera = camera_backups[board.current_player];
}
process_input :: (using game_scene : *Game_Scene) {
	find_intersection(game_scene);
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
			if board_interface.cursor != .{-1, -1} && board.uncommited_count == 0 {
				new_nodes_count := click(*board_interface);
				new_nodes := array_view(board.history, board.history.count - new_nodes_count);
				// log("new nodes:\n");
				// for new_nodes log("%\n", it);
				for 1..new_nodes_count {
					undo_single(*board);
				}
			}
		} else if IsMouseButtonPressed(.RIGHT) {
			cam_state = .MOVE;
			DisableCursor();
		}
	}
	if IsKeyPressed(.R) {
		reset_this_camera(game_scene);
	} else if IsKeyPressed(.S) {
		tmp := copy(board); defer deinit(*tmp);
		ok := save_board(board, "b1.board");
		assert(ok);
		deinit(*board);
		ok = load_board(*board, "b1.board");
		assert(ok);
		assert(tmp == board);
	} else if IsKeyPressed(.N) {
		add_some_request();
	}
}
find_intersection :: (using game_scene : *Game_Scene) {
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

process_unapplied_steps :: (using game_scene : *Game_Scene) {
	try_start_new_animation :: (using game_scene : *Game_Scene) {
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
	update_animation :: (using game_scene : *Game_Scene) -> current_animation_ended:bool {
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
	animation_end :: (using game_scene : *Game_Scene) {
		if current_step.type == {
			case .STEPEND; using current_step.data_stepend;
			if ENABLE_CAMERA_ROTATION {
				camera = camera_backups[player_new];
				cam_state = .FIXED;				
			}
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
	while update_animation(game_scene) {
		animation_end(game_scene);
		redo_single(*board);
		try_start_new_animation(game_scene);
	}
	set_blacklist(game_scene);
}