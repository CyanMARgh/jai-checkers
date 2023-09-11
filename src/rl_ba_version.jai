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
#load "rl/capture.jai";

// CLIP_NAME :: "clip.mpg";
CLIP_NAME :: "badapple.mpg";
RENDER_VIDEO :: true;
AUTO_PLAY :: true;

main :: () {
	defer report_memory_leaks();

	prepare(); defer finalize();
	fps := cast(int)get_framerate(plm);

	#if RENDER_VIDEO {
		ffmpeg := ffmpeg_start_rendering(W0, H0, fps = fps);
		defer ffmpeg_end_rendering(*ffmpeg);
		buffer := make_frame(W0, H0);
		defer clear(buffer);		
	}

	init_window_and_resources(); defer deinit_window_and_resources();
	SetTargetFPS(xx fps);

	fuse := 40;

	game_scene := Game_Scene.{
		board = .{
			rules = .{
				must_capture = .ALWAYS,
				diagonal = false,
				leveled_upgrade = true,
				rows_offset = 1,
				rows = 2,
				diam = 26,
				cutoff = 3,
				enable_border = true,
				border_period = 40,
				must_continue_capture = true,
				two_players = true,
				land_right_behind = false,
				// _180_no_scope = true
			}
		},
		immediate_switch = true
	};
	init_main_scene(*game_scene);
	defer deinit_main_scene(*game_scene);

	_camera = default_camera(game_scene, 0);

	while !WindowShouldClose() {
		delta_time, time :float= xx min(GetFrameTime(), 1), xx GetTime();
		process_input_camera(game_scene);

		update_main_frame();
		if fuse > 0 {
			fuse -= 1;
		} else {
			move_to_board(*game_scene.board);
		}

		BeginDrawing();
			ClearBackground(GRAY);
			draw_scene(game_scene, _camera, time, .ALL & ~.CURSOR & ~.DEBUG_INFO);

			BeginMode3D(_camera);
				draw(*particle_system);
			EndMode3D();
		EndDrawing();
		update_audio();
		#if RENDER_VIDEO {
			ffmpeg_send_screenshot(*ffmpeg, *buffer);
		}
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

using,except(Frame) PL_MPEG :: #import "pl_mpeg";
plm : *Plm;
video_size : ivec2;
main_frame : []u8vec3;

prepare :: () {
	plm = create_with_filename(tprint("./res/%", CLIP_NAME));
	if !plm {
		print("Couldn't open video\n");
		exit(1);
	}
	w, h := get_size(plm); video_size = .{w, h};
	set_audio_enabled(plm, false);
	main_frame = NewArray(w * h, u8vec3);
}
finalize :: () {
	plm_destroy(plm);
	array_free(main_frame);
}
update_main_frame :: () -> ok:bool {
	frame_plm := decode_video(plm);
	if !frame_plm {
		array_free(main_frame);
		main_frame = .[];
		return false;
	}
	frame_to_rgb(frame_plm, xx main_frame.data, video_size.x * 3);
	return true;
}
move_to_board :: (board : *Board) {
	pixel_at :: (p : ivec2) -> Color #expand {
		_x, _y := p.x * (video_size.x - 1) / board.diam, p.y * (video_size.y - 1) / board.diam;	
		pixel := ifx main_frame then main_frame[_y * video_size.x + _x] else .{255, 255, 255};
		return .{xx pixel.x, xx pixel.y, xx pixel.z, 255};
	}
	distance :: (c1 : Color, c2 : Color) -> float {
		r, g, b := cast(float)c1.r - c2.r, cast(float)c1.g - c2.g, cast(float)c1.b - c2.b;
		return r * r + g * g + b * b;
	}
	closest :: (color : Color) -> Cell {
		d0 := distance(color, BLACK);
		d1 := distance(color, BLUE);
		d2 := distance(color, RED);
		d3 := distance(color, GREEN);
		d4 := distance(color, WHITE);
		result := Cell.BLACK;
		#if CLIP_NAME != "badapple.mpg" {
			if d1 < d0 then result, d0 = Cell.BLUE, d1;
			if d2 < d0 then result, d0 = Cell.RED, d1;
			if d3 < d0 then result, d0 = Cell.GREEN, d1;			
		}
		if d4 < d0 then result, d0 = Cell.EMPTY, d1;
		return result;
	}
	i := 0;
	for y : 0..board.diam-1 {
		for x : 0..board.diam-1 {
			pixel := pixel_at(.{xx(board.diam - y - 1), xx x});
			color := closest(pixel);
			board.cells[i] = (board.cells[i] & ~.FIGURE) | color;
			i += 1;
		}
	}
}