SHOW_LETTER_BOUNDRY :: false;
LETTER_BOUNDRY_COLOR :: VIOLET;
LETTER_BOUNDRY_SIZE :: 0.25;

DrawTextCodepoint3D :: (font : Font, codepoint : s32, _position : Vector3, fontSize : float, backface : bool, tint : Color) {
    position := _position;
    index := GetGlyphIndex(font, codepoint);
    scale := fontSize / font.baseSize;

    position.x += cast(float)(font.glyphs[index].offsetX - font.glyphPadding) / cast(float)font.baseSize * scale;
    position.z += cast(float)(font.glyphs[index].offsetY - font.glyphPadding) / cast(float)font.baseSize * scale;

    srcRec := Rectangle.{
        font.recs[index].x - cast(float)font.glyphPadding,
        font.recs[index].y - cast(float)font.glyphPadding,
        font.recs[index].width + 2 * font.glyphPadding,
        font.recs[index].height + 2 * font.glyphPadding
    };

    width := cast(float)(font.recs[index].width + 2 * font.glyphPadding) / cast(float)font.baseSize * scale;
    height := cast(float)(font.recs[index].height + 2 * font.glyphPadding) / cast(float)font.baseSize * scale;

    if font.texture.id > 0 {
        x, y, z := 0.;

        tx := srcRec.x / font.texture.width;
        ty := srcRec.y / font.texture.height;
        tw := (srcRec.x + srcRec.width) / font.texture.width;
        th := (srcRec.y + srcRec.height) / font.texture.height;

        if SHOW_LETTER_BOUNDRY DrawCubeWiresV(.{position.x + width / 2, position.y, position.z + height / 2}, .{width, LETTER_BOUNDRY_SIZE, height}, LETTER_BOUNDRY_COLOR);

        CheckRenderBatchLimit((4 + 4 * cast(s32)backface));
        SetTexture(font.texture.id);

        PushMatrix();
            Translatef(position.x, position.y, position.z);
            Begin(RL_QUADS);
                Color4ub(tint.r, tint.g, tint.b, tint.a);

                // Front Face
                Normal3f(0, 1, 0);                                       // Normal Pointing Up
                TexCoord2f(tx, ty); Vertex3f(x,         y, z);              // Top Left Of The Texture and Quad
                TexCoord2f(tx, th); Vertex3f(x,         y, z + height);     // Bottom Left Of The Texture and Quad
                TexCoord2f(tw, th); Vertex3f(x + width, y, z + height);     // Bottom Right Of The Texture and Quad
                TexCoord2f(tw, ty); Vertex3f(x + width, y, z);              // Top Right Of The Texture and Quad

                if backface {
                    // Back Face
                    Normal3f(0, -1, 0);                              // Normal Pointing Down
                    TexCoord2f(tx, ty); Vertex3f(x,         y, z);          // Top Right Of The Texture and Quad
                    TexCoord2f(tw, ty); Vertex3f(x + width, y, z);          // Top Left Of The Texture and Quad
                    TexCoord2f(tw, th); Vertex3f(x + width, y, z + height); // Bottom Left Of The Texture and Quad
                    TexCoord2f(tx, th); Vertex3f(x,         y, z + height); // Bottom Right Of The Texture and Quad
                }
            End();
        PopMatrix();
        SetTexture(0);
    }
}

DrawText3D :: (font : Font, text : *u8, position : Vector3, fontSize : float, fontSpacing : float, lineSpacing : float, backface : bool, tint : Color) {
    length := TextLength(text);
    textOffsetX, textOffsetY := 0.;

    scale := fontSize / cast(float)font.baseSize;

    for i : 0..length-1 {
        codepointByteCount :s32= 0;
        codepoint := GetCodepoint(*(text[i]), *codepointByteCount);
        index := GetGlyphIndex(font, codepoint);

        if codepoint == 0x3f then codepointByteCount = 1;

        if codepoint == #char"\n" {
            textOffsetY += scale + lineSpacing / cast(float)font.baseSize * scale;
            textOffsetX = 0.;
        } else {
            if ((codepoint != #char" ") && (codepoint != #char"\t")) {
                DrawTextCodepoint3D(font, codepoint, .{position.x + textOffsetX, position.y, position.z + textOffsetY}, fontSize, backface, tint);
            }

            if font.glyphs[index].advanceX == 0  {
                textOffsetX += cast(float)(font.recs[index].width + fontSpacing) / cast(float)font.baseSize * scale;
            } else {
                textOffsetX += cast(float)(font.glyphs[index].advanceX + fontSpacing) / cast(float)font.baseSize * scale;
            }
        }
    }
}

MeasureText3D :: (font : Font, text : *u8, fontSize : float, fontSpacing : float, lineSpacing : float) -> Vector3 {
    len := TextLength(text);
    tempLen, lenCounter :s32= 0;

    tempTextWidth := 0.;

    scale := fontSize / cast(float)font.baseSize;
    textHeight := scale;
    textWidth := 0.;

    letter, index :s32= 0;

    for i : 0..len-1 {
        lenCounter += 1;

        next :s32= 0;
        letter = GetCodepoint(*(text[i]), *next);
        index = GetGlyphIndex(font, letter);

        if (letter == 0x3f) next = 1;
        i += xx(next - 1);

        if (letter != #char"\n") {
            if (font.glyphs[index].advanceX != 0) {
                textWidth += (font.glyphs[index].advanceX + fontSpacing) / cast(float)font.baseSize * scale;
            } else {
                textWidth += (font.recs[index].width + font.glyphs[index].offsetX) / cast(float)font.baseSize * scale;                
            }   
        } else {
            if (tempTextWidth < textWidth) tempTextWidth = textWidth;
            lenCounter = 0;
            textWidth = 0.;
            textHeight += scale + lineSpacing / cast(float)font.baseSize * scale;
        }

        if (tempLen < lenCounter) tempLen = lenCounter;
    }

    if (tempTextWidth < textWidth) tempTextWidth = textWidth;

    vec := Vector3.{
        tempTextWidth + cast(float)((tempLen - 1) * fontSpacing / cast(float)font.baseSize * scale),
        0.25,
        textHeight
    };

    return vec;
}
