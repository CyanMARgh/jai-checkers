ui_init :: () {
	W, H = GetScreenWidth(), GetScreenHeight();
	ui_buffer = LoadRenderTexture(W, H);
	ui_font = GetFontDefault();
}
ui_deinit :: () {
	UnloadRenderTexture(ui_buffer);
}
add_offset :: (rect : Rectangle, offset : float) -> Rectangle {
	return .{
		rect.x + offset,
		rect.y + offset,
		rect.width - 2 * offset,
		rect.height - 2 * offset		
	};
}
UI_GAP_WIDTH :: 2.;
UI_BORDER_WIDTH :: 5.;

ui_draw_base :: (rect : Rectangle, shadow := false) -> Rectangle {
	c0, c1, c2, c3 : Color = .{131, 131, 131, 255}, .{200, 200, 200, 255}, .{100, 100, 100, 255}, .{170, 170, 170, 255};
	outer := add_offset(rect, UI_GAP_WIDTH);	
	inner := add_offset(rect, UI_BORDER_WIDTH);
	DrawRectangleRec(outer, ifx shadow then c2 else c0);
	DrawRectangleRec(inner, ifx shadow then c3 else c1);
	return inner;
}
ui_draw_text_block :: (rect : Rectangle, text : string, shadow := false) {
	c_text := temp_c_string(text);
	s0 := MeasureTextEx(ui_font, c_text, 1, .1);

	zone := ui_draw_base(rect, shadow);
	font_size := 1. / max(.001, s0.x / zone.width, s0.y / zone.height);
	s0 *= font_size;

	DrawTextPro(
		ui_font, c_text,
		.{zone.x + zone.width / 2, zone.y + zone.height / 2},
		s0 / 2, 0.,
		font_size, font_size * .1,
		.{0, 0, 0, 255}
	);
}

ui_begin :: () {
	W_new, H_new := GetScreenWidth(), GetScreenHeight();
	if W_new != W || H_new != H {
		W, H = W_new, H_new;
		UnloadRenderTexture(ui_buffer);
		ui_buffer = LoadRenderTexture(W, H);
	}

	mouse_pos = GetMousePosition();
	release_on_this_frame = IsMouseButtonReleased(.LEFT);
	press_on_this_frame = IsMouseButtonPressed(.LEFT);
	assert(!release_on_this_frame || !press_on_this_frame);

	BeginTextureMode(ui_buffer);
	ClearBackground(BLANK);
}
ui_end :: () {
	if release_on_this_frame {
		btn_pressed_on_tag = "";
	}
	EndTextureMode();
}
ui_draw_buffer :: () {
	DrawTexturePro(
		ui_buffer.texture, 
		.{0, xx H, xx W, xx-H},
		.{0, 0, xx W, xx H},
		.{0, 0}, 0, WHITE
	);	
}

btn_pressed_on_tag : string;
ui_button :: (rect : Rectangle, tag : string) -> bool {
	result := false;
	if press_on_this_frame {
		if CheckCollisionPointRec(mouse_pos, rect) {
			btn_pressed_on_tag = tag;
		}
	} else if release_on_this_frame {
		if btn_pressed_on_tag == tag && CheckCollisionPointRec(mouse_pos, rect) {
			result = true;
		}
	}

	ui_draw_text_block(rect, tag, shadow = tag == btn_pressed_on_tag);
	return result;
}

#scope_file
mouse_pos : Vector2;
release_on_this_frame : bool;
press_on_this_frame : bool;

ui_buffer : RenderTexture2D;
ui_font : Font;

W, H : s32;
