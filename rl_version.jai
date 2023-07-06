#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";
#import,dir "../rfoeraylib/Raylib";
using RL;

main :: () {
	defer report_memory_leaks();

	W0, H0 :: 1200, 800;

	X, Y :: 8, 8;
	content := u8.[
		0, 1, 0, 1, 0, 1, 0, 1,
		1, 0, 1, 0, 1, 0, 1, 0,
		0, 1, 0, 1, 0, 1, 0, 1,
		1, 0, 1, 0, 1, 0, 1, 0,
		0, 1, 0, 1, 0, 1, 0, 1,
		1, 0, 3, 0, 1, 2, 1, 0,
		0, 1, 2, 1, 2, 1, 0, 1,
		1, 0, 1, 0, 1, 0, 1, 0
	];

	draw_scene :: () #expand {
		BeginDrawing(); defer EndDrawing();
		ClearBackground(GRAY);
		BeginMode3D(camera);		
			DrawGrid(10, 1.0);
			i := 0;
			for y : 0..Y-1 {
				for x : 0..X-1 {
					defer i += 1;
					pos := (Vector3.{xx x, 0, xx y} - Vector3.{xx(X - 1), 0, xx(Y - 1)} * .5) * .5;
					DrawCube(pos, .5, .3, .5, ifx content[i] & 1 then WHITE else RAYWHITE);

					if content[i] & 2 then DrawCylinder(pos + Vector3.{0, .15, 0}, .2, .2, .1, 12, RED);
				}
			}
		EndMode3D();
		DrawFPS(20, 20);
	}


	// SetConfigFlags(xx ConfigFlags.WINDOW_RESIZABLE);
	InitWindow(W0, H0, "c4eckers?"); defer CloseWindow();
	camera := Camera.{.{5, 5, 5}, .{0, 0, 0}, .{0, 1, 0}, 45, 0};
	SetTargetFPS(60);

	while !WindowShouldClose() {
        UpdateCamera(*camera, .ORBITAL);
		draw_scene();
		reset_temporary_storage();
	}
}