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

AUTO_PLAY :: false;
SINGLE_CAM :: true;
cam_mode :: Cam_Mode.WITH_RAIL;

_main :: () {
	defer report_memory_leaks();
	init_window_and_resources(); defer deinit_window_and_resources();

	// buffer := LoadRenderTexture(GetScreenWidth(), GetScreenHeight());
	ui_init(); defer ui_deinit();

	input_text : [..]u8; defer array_free(input_text);

	while !WindowShouldClose() {
		W, H := GetScreenWidth(), GetScreenHeight();
		// if key != .NULL || char != .NULL {
		// 	print("%, %\n", key, char);
		// }
		ui_begin();
			if ui_button(.{0, 0, 200, 40}, "button 0") {
				print("click(0)!\n");
			}
			if ui_button(.{0, 40, 200, 40}, "button 1") {
				print("click(1)!\n");
			}
			ui_text_input(.{0, 80, 300, 40}, *input_text, "input text");
		ui_end();
	
		BeginDrawing();
			ClearBackground(WHITE);
			ui_draw_buffer();

			 if is_ui_focused() DrawCircle(400, 400, 50, GREEN);
		EndDrawing();
	}
}

main :: () {
	defer report_memory_leaks();
	init_window_and_resources(); defer deinit_window_and_resources();

	using game_scene := Game_Scene.{
		board = .{
			rules = .{
				must_capture = true,
				diagonal = false,
				leveled_upgrade = true,
				rows_offset = 1,
				rows = 1,
				diam = 8,
				cutoff = 2,
				enable_border = true,
				border_period = 16,
				must_continue_capture = true,
				// two_players = false,
				land_right_behind = false,
				// _180_no_scope = true
			}
		},
		immediate_switch = SINGLE_CAM || cam_mode == .NO_RAIL
	};
	init_main_scene(*game_scene); defer deinit_main_scene(*game_scene);
	init_cameras(game_scene);

	while !WindowShouldClose() {
		delta_time, time :float= xx min(GetFrameTime(), 1), xx GetTime();

		#if AUTO_PLAY {
			if board_interface.uncommited_count == 0 {
				random_click(*board_interface);
			}
			if at(board_interface.board, board_interface.cursor) & .BORDER {
				board_interface.cursor = .{-1, -1};
			}			
		}

		#if !AUTO_PLAY {
			process_input_camera(game_scene);
		}
		camera, clickable := get_current_view_camera(game_scene, cam_mode, time);
		#if !AUTO_PLAY {
			process_input(*game_scene, camera, clickable);
		}
		//process incoming messages
		simulate(*game_scene, delta_time);
		simulate(*particle_system, delta_time);
		BeginDrawing();
			draw_scene(game_scene, camera, time);
			BeginMode3D(camera);
				draw(*particle_system);
			EndMode3D();
		EndDrawing();

		update_audio();
		reset_temporary_storage();
	}
}

#scope_file
#if SINGLE_CAM {
	_camera : Camera;
	_player : int; 
} else {
	_camera_backups : [5]Camera;
}

_cam_state : enum u8 {
	FIXED;
	MOVE;
} = .FIXED;
Cam_Mode :: enum u8 {WITH_RAIL; NO_RAIL; DEMO;}

get_current_view_camera :: (using game_scene : Game_Scene, mode : Cam_Mode, time : float) -> Camera, clickable:bool {
	if mode == .DEMO {
		vv := Vector3.{sin(time * .2), 0, cos(time * .2)};
		return .{
			(vv + .{0, 1, 0}) * (CELL_SIZE * board.diam),
			(vv * .1 + .{0, 0, 0}) * (CELL_SIZE * board.diam),
			.{0, 1, 0}, 45, 0
		}, false;
	}
	#if SINGLE_CAM {
		return _camera, _cam_state == .FIXED;
	} else {
		cam_a := _camera_backups[game_scene.board.current_player];
		if mode == .NO_RAIL || current_step.type != .STEPEND {
			return cam_a, _cam_state == .FIXED;
		}
		cam_b := _camera_backups[current_step.data_stepend.player_new];
		return interpolate_cams(cam_a, cam_b, animation_time), _cam_state == .FIXED;
	}
}
process_input_camera :: (using game_scene : Game_Scene) {
	clamp :: (v : Vector3, a : Vector3, b : Vector3) -> Vector3 {
		return .{
			clamp(v.x, a.x, b.x),
			clamp(v.y, a.y, b.y),
			clamp(v.z, a.z, b.z)
		};
	}

	#if SINGLE_CAM {
		camera := *_camera;
	} else {
		camera := *(_camera_backups[board.current_player]);
	}
	if _cam_state == {
		case .MOVE;
		if current_step.type == .STEPEND return;

		bounds := get_camera_bounds(game_scene);
		update_camera_free_move(camera, 1.);
		clamped_position := clamp(camera.position, bounds.min, bounds.max);
		camera.target += clamped_position - camera.position;
		camera.position = clamped_position;
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
	if IsKeyPressed(.R) {
		reset_this_camera(game_scene);
	}
}
default_camera :: (using game_scene : Game_Scene, id : int) -> Camera {
	VV :: Vector3.[.{1, 0, 0}, .{0, 0, 1}, .{-1, 0, 0}, .{0, 0, -1}, .{0.01, 1, 0}];
	return .{
		(VV[id] + .{0, 1, 0}) * (CELL_SIZE * board.diam),
		(VV[id] * .1 + .{0, 0, 0}) * (CELL_SIZE * board.diam),
		.{0, 1, 0}, 45, 0
	};
}
init_cameras :: (using game_scene : Game_Scene) { 
	#if SINGLE_CAM {
		_camera = default_camera(game_scene, _player);		
	} else {
		for 0..4 {
			_camera_backups[it] = default_camera(game_scene, it);
		}		
	}
}

reset_this_camera :: (using game_scene : Game_Scene) {
	#if SINGLE_CAM {
		_camera = default_camera(game_scene, _player);
	} else {
		_camera_backups[board.current_player] = default_camera(game_scene, board.current_player);
	}
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
