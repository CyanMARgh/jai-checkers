#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";
#import "Raylib";
#import "Hash";

#load "board.jai";
#load "rl/stream_group.jai";
#load "rl/particle_system.jai";
#load "rl/text3d.jai";
#load "rl/window_and_resources.jai";
#load "rl/main_scene.jai";
#load "rl/utils.jai";
#load "rl/ui.jai";
// #load "networking.jai";

AUTO_PLAY :: true;
play_game := false;
BOARDS_COUNT :: 5;

main :: () {
	defer report_memory_leaks();
	init_window_and_resources(); defer deinit_window_and_resources();


	game_scenes : [BOARDS_COUNT * BOARDS_COUNT]Game_Scene;
	for * game_scenes {
		it.* = .{
			board = .{
				rules = .{
					must_capture = true,
					diagonal = false,
					leveled_upgrade = true,
					rows_offset = 1,
					rows = 2,
					diam = 12,
					cutoff = 3,
					enable_border = true,
					border_period = 40,
					must_continue_capture = true,
					// two_players = false,
					land_right_behind = false,
					// _180_no_scope = true
				}
			},
			immediate_switch = true
		};
		init_main_scene(it);
	}
	defer {
		for * game_scenes  deinit_main_scene(it);
	}

	_camera = default_camera(game_scenes[0], 0);
	{
		i := 0;
		for y : 0..BOARDS_COUNT-1 {
			for x : 0..BOARDS_COUNT-1 {
				game_scenes[i].toatal_translation = .{
					CELL_SIZE * (game_scenes[0].board.diam + 1) * x,
					0,
					CELL_SIZE * (game_scenes[0].board.diam + 1) * y
				};
				i += 1;
			}
		}
	}

	while !WindowShouldClose() {
		if IsWindowFullscreen() {
			SetWindowSize(1920, 1080);
		} else {
		 	ToggleFullscreen();
		}

		delta_time, time :float= xx min(GetFrameTime(), 1), xx GetTime();
		// delta_time *= .4;
		// time *= .4;
		if IsKeyPressed(.P) play_game ^= true;
		process_input_camera(game_scenes[0]);

		if play_game {
			for * game_scenes {
				if it.board_interface.uncommited_count == 0 {
					random_click(*(it.board_interface));
				}
				if at(it.board_interface.board, it.board_interface.cursor) & .BORDER {
					it.board_interface.cursor = .{-1, -1};
				}
			}

			//process incoming messages
			for * game_scenes {
				simulate(it, delta_time);
			}
			simulate(*particle_system, delta_time);
		}

		BeginDrawing();
			ClearBackground(GRAY);
			for game_scenes {
				draw_scene(it, _camera, time,
					// ifx it_index == BOARDS_COUNT * BOARDS_COUNT - 1 then .DEBUG_INFO else
					.MINIMUM
				);
			}

			BeginMode3D(_camera);
				draw(*particle_system);
			EndMode3D();
		EndDrawing();
		update_audio();
		reset_temporary_storage();
	}
}

#scope_file
_camera : Camera;

_cam_state : enum u8 {
	FIXED;
	MOVE;
} = .FIXED;

process_input_camera :: (using game_scene : Game_Scene) {
	camera := *_camera;
	if _cam_state == {
		case .MOVE;
		update_camera_free_move(camera, 1.);
		if IsMouseButtonPressed(.LEFT) || IsMouseButtonPressed(.RIGHT) {
			_cam_state = .FIXED;
			center := GetWindowPosition() + Vector2.{600, 400};
			SetMousePosition(xx center.x, xx center.y);
			EnableCursor();
		}
		case .FIXED;
		if IsMouseButtonPressed(.RIGHT) {
			_cam_state = .MOVE;
			DisableCursor();
		}
	}
	if IsKeyPressed(.R) then _camera = default_camera(game_scene, 0);
}
default_camera :: (using game_scene : Game_Scene, id : int) -> Camera {
	VV :: Vector3.[.{1, 0, 0}, .{0, 0, 1}, .{-1, 0, 0}, .{0, 0, -1}, .{0.01, 1, 0}];
	return .{
		(VV[id] + .{0, 1, 0}) * (CELL_SIZE * board.diam),
		(VV[id] * .1 + .{0, 0, 0}) * (CELL_SIZE * board.diam),
		.{0, 1, 0}, 45, 0
	};
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

random_click :: (using board_interface : *Board_Interface) {
	assert(uncommited_count == 0);
	steps_count := shown_steps_move.count + shown_steps_capture.count;
	clickable_count := clickable_figures_move.count + clickable_figures_capture.count;
	if steps_count > 0 {
		id := cast(int)(random_get() % cast(u64)steps_count);
		if id < shown_steps_move.count {
			cursor = shown_steps_move[id];			
		} else {
			cursor = shown_steps_capture[id - shown_steps_move.count];
		}
		nodes := click(board_interface);
		for i : 1..nodes undo_single(board);
	} else if clickable_count > 0 {
		id := cast(int)(random_get() % cast(u64)clickable_count);
		if id < clickable_figures_move.count {
			cursor = clickable_figures_move[id];			
		} else {
			cursor = clickable_figures_capture[id - clickable_figures_move.count];
		}
		nodes := click(board_interface);
		for i : 1..nodes undo_single(board);
	}
}