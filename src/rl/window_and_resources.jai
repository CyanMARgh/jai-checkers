using global_resources : struct {
	particle_system := Particle_System.{particles_count = 100000};
	model_cell : Model;
	model_cylinder : Model;
	model_sphere : Model;
	texture_rose : Texture;
	font : Font;

	sg_slide, sg_crack, sg_upgrade : Stream_Group;
}
W0, H0 :s32= 1200, 800;
init_window_and_resources :: () {
	SetConfigFlags(.WINDOW_RESIZABLE);
	SetConfigFlags(.MSAA_4X_HINT);
	InitWindow(W0, H0, "c4eckers!");

	InitAudioDevice();
	sg_slide = make_stream_group("res/slide2.mp3");
	sg_crack = make_stream_group("res/crack.wav", .3);
	sg_upgrade = make_stream_group("res/upgrade.wav");

	gl_load(*gl);
	SetTargetFPS(60);

	font = GetFontDefault();
	texture_rose = LoadTexture("res/rose.png");

	model_cell = LoadModelFromMesh(GenMeshCube(CELL_SIZE, CELL_HEIGHT, CELL_SIZE));
	model_cylinder = LoadModelFromMesh(GenMeshCylinder(FIGURE_RADIUS, FIGURE_HEIGHT, 16));
	model_sphere = LoadModelFromMesh(GenMeshSphere(1, 16, 16));	

	init(*particle_system);
}
deinit_window_and_resources :: () {
	deinit(*particle_system);

	UnloadModel(model_sphere);
	UnloadModel(model_cylinder);
	UnloadModel(model_cell);
	UnloadTexture(texture_rose);

	deinit(*sg_slide);
	deinit(*sg_crack);
	deinit(*sg_upgrade);
	CloseAudioDevice();
	CloseWindow();
}
update_audio :: () {
	update(*sg_slide);
	update(*sg_crack);
	update(*sg_upgrade);
}