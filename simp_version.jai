
Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System"; 
#import "String";
#import "Random";

#load "board.jai";

GAME_NAME :: "checkers_jai";
GAME_VERSION :: "v1";

mouse_over    : ivec2 = .{-1, -1};
selected_tile : ivec2 = .{-1, -1};
rules := Rules.{diam=16, cutoff=4, rows=3, rows_offset=0, must_capture=false, diagonal=true};
board : Board;

player_colors :: Vector4.[.{.933,.378,.407,1.},.{.424,.964,.273,1.},.{.254,.306,.936,1.},.{.917,.999,.000,1.}, .{0,0,0,1}];

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}

my_window: Window_Type;
my_emoji_font: *Simp.Dynamic_Font;

window_width   : s32 = 1920;
window_height  : s32 = 1080;
window_widthf  : float = 1920.;
window_heightf : float = 1080.;
board_corner   : Vector2 = .{420., 0.};
tile_l         : float = 1080./16;

//image_test: Simp.Texture;

screenshot_index := 0;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }
    my_window = create_window(window_width, window_height, #run sprint("% %", GAME_NAME, GAME_VERSION));
    // Init board
    {
        board.rules = *rules;
        init(*board, *rules);
    }
    defer deinit(*board);

    // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
    window_width, window_height = Simp.get_render_dimensions(my_window);
    window_widthf, window_heightf = cast(float) window_width, cast(float) window_height;
    {
        board_side : float = min(window_widthf, window_heightf);
        tile_l = board_side/rules.diam;
        board_corner = .{(window_widthf-board_side)/2, (window_heightf-board_side)/2};
    }

    Simp.set_render_target(my_window);
    
    my_init_fonts();
    // success := Simp.texture_load_from_file(*image_test, "image_test.jpg");
    // assert(success);
    
    quit := false;
    want_screenshot := false;
    last_time := get_time();
    while !quit {
        current_time := get_time();
        dt := cast(float)(current_time - last_time);
        // Clamp(*dt, 0, 0.1); cheatable?
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);  // Simp will do nothing if it doesn't care about this window.
            
            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;
                window_widthf, window_heightf = cast(float) window_width, cast(float) window_height;
                {
                    board_side : float = min(window_widthf, window_heightf);
                    tile_l = board_side/rules.diam;
                    board_corner = .{(window_widthf-board_side)/2, (window_heightf-board_side)/2};
                }

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }
        // Get mouse position
        {
            x, y, success := get_mouse_pointer_position(my_window, true);
            if success && (x >= cast(int) board_corner.x && y >= cast(int) board_corner.y) {
                l := min(window_width, window_height);
                mouse_over.x = cast(s32) (x - cast(s32) board_corner.x)*rules.diam/l;
                mouse_over.y = cast(s32) (y - cast(s32) board_corner.y)*rules.diam/l;
                if (mouse_over.x >= rules.diam || mouse_over.y >= rules.diam) mouse_over.x = -1;
                if at(*board, mouse_over) & .BORDER then mouse_over.x = -1;
            } else mouse_over.x = -1;
        }

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }

                if it.key_pressed && it.key_code == .PRINT_SCREEN {  // Press PrintScreen to take a screenshot.
                want_screenshot = true;
            }

            if it.key_pressed && it.key_code == .MOUSE_BUTTON_LEFT { // Make move
            moving_player := board.current_player;
            if mouse_over.x != -1 {
                if selected_tile.x == -1 {
                    if is_owned_by(at(*board, mouse_over), moving_player) &&
                       (!should_current_player_kill(*board) || can_kill(*board, mouse_over))
                    then selected_tile = mouse_over;
                } else {
                    if selected_tile == mouse_over selected_tile.x = -1;
                    else if is_owned_by(at(*board, mouse_over), moving_player) selected_tile = mouse_over;
                    else {
                        result := try_step(*board, selected_tile, mouse_over);
                        if result == {
                            case .NONE;
                            case .MOVE; #through;
                            case .ENDSEQ;
                                selected_tile.x = -1;
                            case .KILL;
                                selected_tile = mouse_over;
                                // Can't have an extra hacky click behind the scenes in this game
                        }
                    }
                }
            }
        }

                /*if it.key_pressed && it.key_code == .MOUSE_BUTTON_RIGHT { // Change player
                    moving_player = moving_player % 4 + 1;
                    selected_tile.x = -1;
                    #if RIGHT_CLICK_PROMOTE if mouse_over.x != -1 && board[mouse_over.x+rules.diam*mouse_over.y] != 0 then board[mouse_over.x+rules.diam*mouse_over.y] |= KING_FLAG;
                    #if RIGHT_CLICK_DELETE if mouse_over.x != -1 then board[mouse_over.x+rules.diam*mouse_over.y] = 0;
                }*/
    
            }
        }

        if want_screenshot {
            want_screenshot = false;
            screenshot_index += 1;

            async_read := Simp.pixel_read_begin(null, .RGBA8);
            bitmap     := Simp.pixel_read_end(async_read);
            defer Simp.deinit(*bitmap);

            filename := tprint("screenshot%.png\0", screenshot_index);

            #import "stb_image_write";
            stbi_write_png(filename.data, bitmap.width, bitmap.height, 4, bitmap.data.data, xx (bitmap.width * Simp.get_image_bytes_per_texel(bitmap.format)));  // Hardcoded to 4 channels because we know we requested .BGRA8 above.
        }

        //simulate(dt);
        /*{
            timers[moving_player-1] -= dt;
            if timers[moving_player-1] < 0 {
                timers[moving_player-1] = 0;
                moving_player = moving_player % 4 + 1;
                selected_tile.x = -1;
            }
            if timers[0] == 0 && timers[1] == 0 && timers[2] == 0 && timers[3] == 0 then quit = true;
        }*/

        draw_one_frame(current_time, dt);
        
        reset_temporary_storage();
        sleep_milliseconds(xx ifx floor(16-1000*dt) > 0 else 0);
    }
}

draw_one_frame :: (time: float64, dt : float) {

    Simp.clear_render_target(.15, .08, .08, 1);

    Simp.set_shader_for_color();

    // Green background
    Simp.immediate_quad(0.,0., window_widthf, window_heightf, player_colors[board.current_player]*0.27);


    // Draw board
    {
        Simp.set_shader_for_color();
        color1 :: Vector4.{.2,.15,.1,1.};
        color2 :: Vector4.{.813,.734,.028,1.};
        border :: 0.01;
        for x: 0..rules.diam-1 for y: 0..rules.diam-1 {
            if at(*board, .{x, y}) & .BORDER continue;

            Simp.immediate_quad(board_corner.x+x*tile_l,board_corner.y+y*tile_l,board_corner.x+(x+1)*tile_l,board_corner.y+(y+1)*tile_l,color1);
            Simp.immediate_quad(board_corner.x+(x+border)*tile_l,board_corner.y+(y+border)*tile_l,board_corner.x+(x+1-border)*tile_l,board_corner.y+(y+1-border)*tile_l,color2);
        }
    }
    // Draw pieces
    {
        text_width := Simp.prepare_text(my_emoji_font, "🔘");
        text_width = text_width - text_width/20; // @Cleanup hax for bad font
        
        for x: 0..rules.diam-1 for y: 0..rules.diam-1 {
            cell := at(*board, .{x, y});
            if cell & .BORDER || !(cell & .FIGURE) continue;
            
            king := cast(bool) cell & .KING_ANY;
            if king {
                text_width = Simp.prepare_text(my_emoji_font, "👑");
                text_width = text_width - text_width/20; // @Cleanup hax for bad font
            }
            Simp.draw_prepared_text(my_emoji_font, 
                    cast,trunc(s64) (board_corner.x+(x+.5)*tile_l-text_width/2), 
                    cast,trunc(s64) (board_corner.y+(y+.5)*tile_l-my_emoji_font.character_height/2 + my_emoji_font.character_height/8), // @Cleanup hax for bad font
                    player_colors[get_player_by_code(cell)]);
            if king {
                text_width = Simp.prepare_text(my_emoji_font, "🔘");
                text_width = text_width - text_width/20; // @Cleanup hax for bad font
            }
        }
    }
    // Draw possible moves
    /*{
        selected_pos := selected_tile;
        if selected_pos.x == -1 selected_pos = mouse_over;
        selected : u8 = ifx selected_pos.x != -1 then board[selected_pos.x + rules.diam*selected_pos.y] else 0;
        if selected {
            text_width := Simp.prepare_text(my_emoji_font, "⚪");
            text_width = text_width - text_width/20; // @Cleanup hax for bad font

            visited : [rules.diam*rules.diam] bool;
            dirs :: Pos.[.{1, 1}, .{1, -1}, .{-1, 1}, .{-1, -1}];
            _queue : [rules.diam*rules.diam] Pos = ---;
            queue : [] Pos = _queue;
            queue[0] = selected_pos; queue.count = 1;
            first_pass := true;
            while queue.count > 0 {
                tile := queue[0];
                queue.data += 1; queue.count -= 1;
                for dir : dirs {
                    next := tile;
                    jumped : bool;
                    for x : 1..rules.diam {
                        if !(selected & KING_FLAG) && (x > 2 || (!jumped && x > 1)) break;
                        next += dir;
                        if next.x < 0 || next.y < 0 || next.x >= rules.diam || next.y >= rules.diam || is_pos_cut_off(next.x,next.y) break;
                        target := board[next.x + rules.diam*next.y] & COLOR_MASK;
                        if target == selected & COLOR_MASK break;
                        if target {
                            jumped = true;
                        } else {
                            if !visited[next.x + rules.diam*next.y] {
                                if first_pass || jumped then Simp.draw_prepared_text(my_emoji_font, 
                                    cast,trunc(s64) (board_corner.x+(next.x+.5)*tile_l-text_width/2), 
                                    cast,trunc(s64) (board_corner.y+(next.y+.5)*tile_l-my_emoji_font.character_height/2 + my_emoji_font.character_height/8), // @Cleanup hax for bad font
                                    player_colors[xx selected & COLOR_MASK]* ifx first_pass then 1. else 0.3);
                                if jumped {
                                    visited[next.x + rules.diam*next.y] = true;
                                    queue.count += 1; queue[queue.count-1] = next;
                                    break;
                                }
                            }
                            if jumped break;
                            visited[next.x + rules.diam*next.y] = true;
                        }
                    }
                }
                first_pass = false;
            }
            /*for board {
                if it continue;
                x := it_index % rules.diam;
                y := it_index / rules.diam;
                dx, dy := x-selected_pos.x, y-selected_pos.y;
                if dx*dx != dy*dy continue;
                if is_pos_cut_off(x,y) continue;
                if dx*dx > 4 continue;
                selected := board[selected_pos.x+rules.diam*selected_pos.y];
                if dx*dx == 4 {
                    target := board[x-dx/2 + rules.diam*(y-dy/2)];
                    if target == 0 || target & COLOR_MASK == selected & COLOR_MASK continue;
                }
                Simp.draw_prepared_text(my_emoji_font, 
                    cast,trunc(s64) (board_corner.x+(x+.5)*tile_l-text_width/2), 
                    cast,trunc(s64) (board_corner.y+(y+.5)*tile_l-my_emoji_font.character_height/2 + my_emoji_font.character_height/8), // @Cleanup hax for bad font
                    player_colors[xx selected & COLOR_MASK]);
            }*/
        }
    }*/
    // Draw selection
    {
        if selected_tile.x != -1 {
            Simp.set_shader_for_color(true);
            theta := cast(float) fmod_cycling(time*4, TAU);
            color := Vector4.{1.,1.,1.,1.};
            color.w = -cos(theta)*.1+.4;
            Simp.immediate_quad(board_corner.x+selected_tile.x*tile_l,board_corner.y+selected_tile.y*tile_l,board_corner.x+(selected_tile.x+1)*tile_l,board_corner.y+(selected_tile.y+1)*tile_l,color);
        }
    }
    // Draw mouseover
    {
        if mouse_over.x != -1 {
            Simp.set_shader_for_color(true);
            theta := cast(float) fmod_cycling(time*4, TAU);
            color := Vector4.{1.,1.,1.,1.};
            color.w = cos(theta)*.1+.4;
            Simp.immediate_quad(board_corner.x+mouse_over.x*tile_l,board_corner.y+mouse_over.y*tile_l,board_corner.x+(mouse_over.x+1)*tile_l,board_corner.y+(mouse_over.y+1)*tile_l,color);
        }
    }
    // Draw timers
    /*{
        for timers {
            seconds := fmod_cycling(it, 60.);
            text_width := Simp.prepare_text(my_font, ifx it >= 60 then tprint("%:%0%", cast,trunc(int) it / 60, ifx seconds <=10 "0" else "", FormatFloat.{value=seconds, zero_removal=.NO, trailing_width=1}) else tprint("%", FormatFloat.{value=it, zero_removal=.NO, trailing_width=1}));
            Simp.draw_prepared_text(my_font, 
            ifx it_index == 1 || it_index == 2  window_width-text_width else 0, 
            ifx it_index < 2 window_height-my_font.character_height else 0, 
            player_colors[it_index+1]*0.7);
        }
    }*/

/*
    if image_test.width && image_test.height {
        // Draw the texture test, to make sure
        // it comes out right-side-up.

        Simp.set_shader_for_images(*image_test);
        Simp.immediate_begin();

        w := window_height/8.0;

        v2 :: make_vector2;
        Simp.immediate_quad(v2(0, 0), v2(w, 0), v2(w, w), v2(0, w));
        Simp.immediate_flush();
    }
    */
    Simp.swap_buffers(my_window);
}

my_init_fonts :: () {
    // So that we can load our font, set to path of running executable.
    // @Incomplete: Pack a default font into Simp.

    if !working_directory_set {
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);
        working_directory_set = true;
    }
    
    pixel_height := window_height / 24;

    // @Cleanup: Don't have path + name be separate.
    //my_font = Simp.get_font_at_size(".", "unifont-15.0.06.ttf", pixel_height);
    //assert(my_font != null);

    pixel_height = min(window_height, window_width)/17;

    my_emoji_font = Simp.get_font_at_size(".", "AndroidEmoji.ttf", pixel_height);
    assert(my_emoji_font != null);
}

working_directory_set := false;

