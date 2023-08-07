Stream_Group :: struct {
	streams : [3]Music;
}
make_stream_group :: (src : *u8) -> Stream_Group {
	using result : Stream_Group;
	for * streams {
		it.* = LoadMusicStream(src);
		it.looping = false;
	}
	return result;
}
deinit :: (using stream_group : *Stream_Group) {
	for streams UnloadMusicStream(it);
}
play :: (using stream_group : *Stream_Group) {
	for streams {
		if !IsMusicStreamPlaying(it) {
			PlayMusicStream(it);
			break;
		}
	}
}
update :: (using stream_group : *Stream_Group) {
	for streams UpdateMusicStream(it);
}