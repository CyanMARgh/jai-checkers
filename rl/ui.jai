#import "String";

ui_init :: () {
	W, H = GetScreenWidth(), GetScreenHeight();
	ui_buffer = LoadRenderTexture(W, H);
	ui_font = GetFontDefault();
}
ui_deinit :: () {
	UnloadRenderTexture(ui_buffer);
	free(focus_tag);
	free(down_tag);
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

	input_key, input_char = GetKeyPressed(), GetCharPressed();

	BeginTextureMode(ui_buffer);
	ClearBackground(BLANK);
}
ui_end :: () {
	if press_on_this_frame {
		safe_move(*down_tag, pressed_tag);
		if pressed_tag == "" {
			safe_move(*down_tag, "");
		}
	} else if release_on_this_frame {
		safe_move(*down_tag, "");
	}
	pressed_tag, released_tag = "";
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

ui_button :: (_rect : Rectangle, tag : string) -> bool {
	return ui_button(_rect, tag, tag);
}
ui_button :: (_rect : Rectangle, tag : string, text : string) -> bool {
	rect := add_offset(_rect, UI_GAP_WIDTH);
	result := ui_click(rect, tag, false);
	ui_draw_text_block(rect, text, shadow = down_tag == tag);
	return result;
}
ui_checkbox :: (_rect : Rectangle, tag : string, enabled : *bool) -> updated:bool {
	rect := add_offset(_rect, UI_GAP_WIDTH);
	inner := ui_draw_base(rect, down_tag == tag);
	clicked := ui_click(rect, tag, false);
	enabled.* ^= clicked;
	if enabled.* {
		DrawRectangleRec(add_offset(inner, UI_BORDER_WIDTH), BLACK);
	}
	return clicked;
}

is_printable :: (char : KeyboardKey) -> bool {
	code := cast(u32) char;
	return code >= 32 && code <= 126;
}

ui_text_input :: (_rect : Rectangle, tag : string, buffer : *[..]u8) {
	rect := add_offset(_rect, UI_GAP_WIDTH);
	add_char :: (buffer : *[..]u8, char : s32) {
		while char {
			array_add(buffer, xx(char & 0xFF));
			char >>= 8;
		}
	}
	if tag == focus_tag {
		if is_printable(input_char) {
			add_char(buffer, xx input_char);
		} else if input_key == .BACKSPACE {
			if buffer.count > 0 {
				buffer.count -= 1;
			}
		}
	}

	ui_click(rect, tag, true);
	ui_draw_text_block(rect, to_string(buffer.*), shadow = tag == focus_tag);
}

safe_move :: (dst : *string, src : string) {
	free(dst.*);
	dst.* = copy_string(src);
}
ui_text :: (_rect : Rectangle, text : string) {
	rect := add_offset(_rect, UI_GAP_WIDTH);
	ui_draw_text_block(rect, text);
}
ui_range_selector :: (rect : Rectangle, tag : string, value : *$T, minval : T, maxval : T) -> updated:bool {
	return ui_range_selector(rect, tag, value, minval, maxval, tag);
}
ui_range_selector :: (rect : Rectangle, tag : string, value : *$T, minval : T, maxval : T, text : string) -> updated:bool {
	#run {
		type := type_info(T).type;
		assert(type == .INTEGER, tprint("type =%\n", type));
	}
	updated := false;
	percents_count := 0;
	{
		for i : 0..text.count-1 if text[i] == #char"%" then percents_count += 1;
		assert(percents_count <= 1);
	}
	assert(rect.width > rect.height * 2);
	rect_left := Rectangle.{
		rect.x, rect.y,
		rect.height, rect.height
	};
	rect_center := Rectangle.{
		rect.x + rect.height, rect.y,
		rect.width - 2 * rect.height, rect.height
	};
	rect_right := Rectangle.{
		rect.width + rect.x - rect.height, rect.y,
		rect.height, rect.height
	};
	if ui_button(rect_left, tprint("%.0", tag), "<") && value.* > minval {
		value.* -= 1;
		updated = true;
	}
	if ui_button(rect_right, tprint("%.1", tag), ">") && value.* < maxval {
		value.* += 1;
		updated = true;
	}
	ui_text(rect_center, ifx percents_count == 0 then text else tprint(text, value.*));
	return updated;
}
ui_option_selector :: (rect : Rectangle, id : *$T, options : []string) -> updated:bool {
	return ui_option_selector(rect, join(..options, allocator = temp, separator = "_"), id, options);
}
ui_option_selector :: (rect : Rectangle, tag : string, id : *$T, options : []string) -> updated:bool {
	assert(options.count > 0);
	updated := false;
	if id.* >= options.count {
		id.* = options.count - 1; 
		updated = true;
	}
	#run {
		type := type_info(T).type;
		assert(type == .INTEGER, tprint("type =%\n", type));
	}
	assert(rect.width > rect.height * 2);
	rect_left := Rectangle.{
		rect.x, rect.y,
		rect.height, rect.height
	};
	rect_center := Rectangle.{
		rect.x + rect.height, rect.y,
		rect.width - 2 * rect.height, rect.height
	};
	rect_right := Rectangle.{
		rect.width + rect.x - rect.height, rect.y,
		rect.height, rect.height
	};
	if ui_button(rect_left, tprint("%.0", tag), "<") && id.* > 0 {
		id.* -= 1;
		updated = true;
	}
	if ui_button(rect_right, tprint("%.1", tag), ">") && id.* < options.count-1 {
		id.* += 1;
		updated = true;
	}
	ui_text(rect_center, options[id.*]);
	return updated;
}
ui_checkbox_with_text :: (rect : Rectangle, tag : string, enabled : *bool) -> updated:bool {
	return ui_checkbox_with_text(rect, tag, enabled, tag);
}
ui_checkbox_with_text :: (rect : Rectangle, tag : string, enabled : *bool, text : string) -> updated:bool {
	rect_left := Rectangle.{
		rect.x, rect.y,
		rect.height, rect.height
	};
	rect_right := Rectangle.{
		rect.x + rect.height, rect.y,
		rect.width - rect.height, rect.height
	};
	ui_text(rect_right, text);
	return ui_checkbox(rect_left, tprint("%.0", tag), enabled);
}

is_ui_focused :: () -> bool {
	return focus_tag != "";
}

#scope_file
input_char, input_key : KeyboardKey;

pressed_tag : string;
down_tag : string;
released_tag : string;
focus_tag : string;

mouse_pos : Vector2;
release_on_this_frame : bool;
press_on_this_frame : bool;

ui_buffer : RenderTexture2D;
ui_font : Font;

W, H : s32;

ui_click :: (rect : Rectangle, tag : string, focus : bool) -> bool {
	if press_on_this_frame {
		if CheckCollisionPointRec(mouse_pos, rect) {
			pressed_tag = tag;
			safe_move(*focus_tag, ifx focus then tag else "");
		}
	} else if release_on_this_frame {
		if CheckCollisionPointRec(mouse_pos, rect) {
			released_tag = tag;
			if down_tag == tag {
				return true;
			}
		}
	}
	return false;
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
	outer := rect;//add_offset(rect, UI_GAP_WIDTH);
	inner := add_offset(outer, UI_BORDER_WIDTH);
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
