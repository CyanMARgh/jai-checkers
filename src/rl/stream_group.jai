Stream_Group :: struct {
	streams : [3]Music;
}
make_stream_group :: (src : *u8, voulme := 1.) -> Stream_Group {
	using result : Stream_Group;
	for * streams {
		it.* = LoadMusicStream(src);
		it.looping = false;
		SetMusicVolume(it.*, voulme);
	}
	return result;
}
deinit :: (using stream_group : *Stream_Group) {
	for streams UnloadMusicStream(it);
}
play :: (using stream_group : *Stream_Group) {
	for streams {
		if !IsMusicStreamPlaying(it) {
			// print("!!!\n");
			PlayMusicStream(it);
			break;
		}
	}
}
update :: (using stream_group : *Stream_Group) {
	for streams UpdateMusicStream(it);
}