/*iMatrix2 :: struct {
    _11, _12 : s32;
    _21, _22 : s32;

    #place _11; v:      [2]    ivec2 = ---; // These are row vectors.
    #place _11; coef:   [2][2] s32   = ---;
    #place _11; ints:   [4]    s32   = ---;

    Row_Type    :: ivec2;
    Column_Type :: ivec2;

    IsMatrixFromMathModule :: false;
}*/

iMatrix3x2 :: struct {
    _11, _12, _13 : s32;
    _21, _22, _23 : s32;

    #place _11; v:      [2]    ivec3 = ---; // These are row vectors.
    #place _11; coef:   [3][4] s32   = ---;
    #place _11; ints:   [12]   s32   = ---;

    Row_Type    :: ivec3;
    Column_Type :: ivec2;

    IsMatrixFromMathModule :: false;
}

multiply :: (m: iMatrix3x2, v: ivec3) -> ivec2 {
    result: ivec2 = ---;
    result.x = m._11 * v.x + m._12 * v.y + m._13 * v.z;
    result.y = m._21 * v.x + m._22 * v.y + m._23 * v.z;
    return result;
}

operator * :: (m: iMatrix3x2, v: ivec3) -> ivec2 {
    return inline multiply(m, v);
}
