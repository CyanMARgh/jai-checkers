Stream_Group :: struct {
	streams : [10]Music;
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
	for streams {
		UnloadMusicStream(it);
	}
}
play :: (using stream_group : *Stream_Group) {
	count := 0;
	for streams {
		if !IsMusicStreamPlaying(it) {
			count += 1;
			PlayMusicStream(it);
			break;
		}
	}
}
update :: (using stream_group : *Stream_Group) {
	count := 0;
	for streams {
		UpdateMusicStream(it);
		if IsMusicStreamPlaying(it) {
			count += 1;
		}
	}
}