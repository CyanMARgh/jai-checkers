#import "Basic"()(MEMORY_DEBUGGER=DEBUG);
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
#load "rl/capture.jai";

AUTO_PLAY :: false;
SINGLE_CAM :: false;
cam_mode :: Cam_Mode.WITH_RAIL;
RENDER_VIDEO :: false;

_main :: () {
	#if DEBUG {
		defer report_memory_leaks();
	}
	init_window_and_resources(); defer deinit_window_and_resources();

	// buffer := LoadRenderTexture(GetScreenWidth(), GetScreenHeight());
	ui_init(); defer ui_deinit();

	input_text : [..]u8; defer array_free(input_text);

	huh : bool;
	value := 10;
	option := 0;

	while !WindowShouldClose() {
		W, H := GetScreenWidth(), GetScreenHeight();
		ui_begin();
			if ui_button(.{0, 0, 200, 40}, "button 0") print("click(0)!\n");
			if ui_button(.{0, 40, 200, 40}, "button 1") print("click(1)!\n");
			ui_text_input(.{0, 80, 300, 40}, "input text", *input_text);
			ui_checkbox_with_text(.{0, 120, 300, 40}, "huh", *huh);
			ui_range_selector(.{0, 160, 300, 40}, "range selector", *value, -3, 10, "some value = %");
			ui_option_selector(.{0, 200, 300, 40}, *option, .["apple", "apricot", "banana"]);
		ui_end();
	
		BeginDrawing();
			ClearBackground(WHITE);
			ui_draw_buffer();
		EndDrawing();
	}
}

main :: () {
	#if DEBUG {
		defer report_memory_leaks();
	}
	#if RENDER_VIDEO {
		#if DEBUG {
			FPS :: 30;
		} else {
			FPS :: 40;
		}
		ffmpeg := ffmpeg_start_rendering(W0, H0, fps = FPS);
		defer ffmpeg_end_rendering(*ffmpeg);
		buffer := make_frame(W0, H0);
		defer clear(buffer);		
	} else {
		FPS :: 60;
	}

	init_window_and_resources(); defer deinit_window_and_resources();
	SetTargetFPS(FPS);
	ui_init(); defer ui_deinit();
	SetExitKey(KEY_NULL);

	app_state : enum u8 {
		MENU :: 0;
		GAME :: 1;
		PAUSE :: 2;
	} = .MENU;
	is_board_valid, validation_message := true, "";

	using game_scene := Game_Scene.{
		board = .{
			rules = .{
				must_capture = .ALWAYS,
				diagonal = false,
				leveled_upgrade = true,
				rows_offset = 1,
				rows = 2,
				diam = 10,
				cutoff = 3,
				enable_border = true,
				border_period = 16,
				must_continue_capture = true,
				land_right_behind = false,
			}
		},
		immediate_switch = SINGLE_CAM || cam_mode == .NO_RAIL
	};
	init_main_scene(*game_scene);
	defer deinit_main_scene(*game_scene);
	init_cameras(game_scene);

	exit_forced := false;

	save_file_name_buf : [..]u8;
	defer array_free(save_file_name_buf);
	add_string(*save_file_name_buf, "B0");

	while !WindowShouldClose() && !exit_forced {
		delta_time, time :float= xx min(GetFrameTime(), 1), xx GetTime();

		if #complete app_state == {
			case .MENU;
			ui_begin();
				if ui_button(.{160, 0, 160, 40}, "exit") exit_forced = true;

				updated := ui_checkbox_with_text(.{0, 40, 200, 40}, "diagonal", *board.diagonal);
				updated |= ui_range_selector(.{0, 80, 300, 40}, "diameter = %", *board.diam, 0, 26);
				updated |= ui_range_selector(.{0, 120, 300, 40}, "cutoff = %", *board.cutoff, 0, 13);
				updated |= ui_range_selector(.{0, 160, 360, 40}, "rows = %", *board.rows, 1, 13);
				updated |= ui_range_selector(.{0, 200, 360, 40}, "rows offset = %", *board.rows_offset, 0, 13);
				// updated |= ui_checkbox_with_text(.{0, 240, 240, 40}, "must capture", *board.must_capture);
				updated |= ui_option_selector(.{0, 240,  360, 40}, cast(*s8)*board.must_capture, .["no forced capture", "forced capture", "angry queens"]);
				updated |= ui_checkbox_with_text(.{0, 280, 360, 40}, "180 degrees no scope", *board._180_no_scope);
				updated |= ui_checkbox_with_text(.{0, 320, 320, 40}, "only 2 players", *board.two_players);
				updated |= ui_checkbox_with_text(.{0, 360, 360, 40}, "backward capture", *board.backward_capture);
				updated |= ui_checkbox_with_text(.{0, 400, 360, 40}, "battle royale border", *board.enable_border);
				updated |= ui_range_selector(.{0, 440, 360, 40}, "border period = %", *board.border_period, 1, 1000);
				updated |= ui_checkbox_with_text(.{0, 480, 360, 40}, "must continue capture", *board.must_continue_capture);
				updated |= ui_checkbox_with_text(.{0, 520, 360, 40}, "land right begind", *board.land_right_behind);

				updated |= ui_checkbox_with_text(.{400, 40, 280, 40}, "leveled queens", *board.leveled_upgrade);
				if board.leveled_upgrade {
					ui_text(.{400, 80, 280, 40}, "queen ranges:");
					updated |= ui_range_selector(.{400, 120, 160, 40}, "qr0", *(board.length_by_level[0]), 1, 32, "%");
					updated |= ui_range_selector(.{400, 160, 160, 40}, "qr1", *(board.length_by_level[1]), 1, 32, "%");
					updated |= ui_range_selector(.{400, 200, 160, 40}, "qr2", *(board.length_by_level[2]), 1, 32, "%");
					updated |= ui_range_selector(.{400, 240, 160, 40}, "qr3", *(board.length_by_level[3]), 1, 32, "%");
				} else {
					ui_text(.{400, 80, 280, 40}, "queen range:");
					updated |= ui_range_selector(.{400, 120, 160, 40}, "qr4", *(board.length_by_level[3]), 1, 32, "%");					
				}

				if updated {
					is_board_valid, validation_message = is_valid(board.rules);
					deinit_main_scene(*game_scene);
					if is_board_valid {
						init_main_scene(*game_scene);
						init_cameras(game_scene);
					}
				}
				if ui_button(.{360, 0, 160, 40}, "load game") {
					new_board : Board;
					path := tprint("./saves/%.board", cast(string)cast([]u8)save_file_name_buf);
					ok := load_board(*new_board, path);
					if ok {
						deinit(*board);
						board = new_board;
						updated = true;
					} else {
						print("failed to load board: %\n", path);
					}
				}
				if !is_board_valid {
					ui_text(.{320, 0, 500, 40}, validation_message);	
				}
				if ui_button(.{0, 0, 160, 40}, "play") && is_board_valid {
					app_state = .GAME;
				}
				ui_text_input(.{520, 0, 240, 40}, "board name(load)", *save_file_name_buf);
			ui_end();
			BeginDrawing();
				if is_board_valid {
					camera, clickable := get_current_view_camera(game_scene, cam_mode, time);
					draw_scene(game_scene, camera, time, .BACKGROUND);
					BeginMode3D(camera);
						draw(*particle_system);
					EndMode3D();
					DrawRectangle(0, 0, GetScreenWidth(), GetScreenHeight(), .{255, 255, 255, 150});					
				} else {
					ClearBackground(.{200, 200, 200, 255});
				}
				ui_draw_buffer();
			EndDrawing();

			case .GAME;
			process_input_camera(game_scene);
			camera, clickable := get_current_view_camera(game_scene, cam_mode, time);
			process_input(*game_scene, camera, clickable);

			//process incoming messages
			simulate(*game_scene, delta_time);
			simulate(*particle_system, delta_time);
			BeginDrawing();
				draw_scene(game_scene, camera, time, .ALL);
				BeginMode3D(camera);
					draw(*particle_system);
				EndMode3D();
			EndDrawing();
			update_audio();
			if IsKeyPressed(.ESCAPE) {
				app_state = .PAUSE;
				if _cam_state != .FIXED {
					return_cursor();
				}
			}
			case .PAUSE;
			camera, clickable := get_current_view_camera(game_scene, cam_mode, time);
			//process incoming messages
			BeginDrawing();
				draw_scene(game_scene, camera, time, .ALL & ~.DEBUG_INFO);
				BeginMode3D(camera);
					draw(*particle_system);
				EndMode3D();
				DrawRectangle(0, 0, GetScreenWidth(), GetScreenHeight(), .{255, 255, 255, 150});
				ui_begin();	
					if ui_button(.{0, 0, 200, 40}, "exit to menu") {
						deinit_main_scene(*game_scene);
						init_main_scene(*game_scene);
						init_cameras(*game_scene);
						reset(*particle_system);
						app_state = .MENU;
					}
					if ui_button(.{0, 40, 240, 40}, "exit from game") {
						deinit_main_scene(*game_scene);
						init_main_scene(*game_scene);
						app_state = .MENU;
						exit_forced = true;
					}
					if ui_button(.{0, 120, 200, 40}, "save board:") {
						save_board(board, tprint("./saves/%.board", cast(string)cast([]u8)save_file_name_buf));
					}
					ui_text_input(.{0, 160, 240, 40}, "board name", *save_file_name_buf);
				ui_end();
				ui_draw_buffer();
			EndDrawing();
			update_audio();

			if IsKeyPressed(.ESCAPE) {
				app_state = .GAME;
				if _cam_state != .FIXED {
					hide_cursor();
				}
			}
		}

		#if RENDER_VIDEO {
			ffmpeg_send_screenshot(*ffmpeg, *buffer);
		}

		reset_temporary_storage();
	}
}

#scope_file
is_online_version := false;
Player_Status :: struct {
	connection_status : enum u8 {
		CONNECTED;
		LEAVED;
		WAIT;
		// 
	};
	game_status :: enum u8 {
		ALIVE;
		DEAD;
	}
}
players_status : [4]Player_Status;

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
			return_cursor();
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
return_cursor :: () {
	center := GetWindowPosition() + Vector2.{600, 400};
	SetMousePosition(xx center.x, xx center.y);
	EnableCursor();
}
hide_cursor :: () {
	DisableCursor();
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
