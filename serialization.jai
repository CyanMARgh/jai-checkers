cut_data :: ($T : Type, src : *[]u8) -> T, bool {
	result : T = ---;
	ok := cut_data_move(*result, src);
	return result, ok;
}
cut_data_move :: (dst : *$T, src : *[]u8) -> bool {
	S :: size_of(T);
	if src.count < S then return false;
	memcpy(dst, src.data, S);
	src.data += S; src.count -= S;
	return true;
}
write_data :: (dst : *[..]u8, src : $T) {
	S :: size_of(T);
	src_u8 : []u8 = ---;
	src_u8.data, src_u8.count = xx *src, S;
	array_add(dst, ..src_u8);
}
cut_array_move :: (dst : *[]$T, src : *[]u8) -> bool {
	S :: size_of(T);
	if !cut_data_move(*(dst.count), src) return false;
	S2 := S * dst.count;
	if src.count < S2 return false;
	dst.data = alloc(S2);
	memcpy(dst.data, src.data, S2);
	src.data += S2; src.count -= S2;
	return true;
}
cut_array_move :: (dst : *[..]$T, src : *[]u8) -> bool {
	if !cut_array_move(cast(*[]T)dst, src) return false;
	dst.allocated = dst.count;
	return true;
}
write_array :: (dst : *[..]u8, src : []$T) {
	S :: size_of(T);
	src_u8 : []u8 = ---;
	write_data(dst, src.count);
	src_u8.data, src_u8.count = xx src.data, S * src.count;
	array_add(dst, ..src_u8);
}
to_byte_array_view :: (value : *$T) -> []u8 {
	result : []u8 = ---;
	result.data, result.count = xx value, size_of(T);
	return result;
}
to_u8_array :: (arr : []$T) -> []u8 {
	arr_u8 : []u8;
	arr_u8.data, arr_u8.count = xx arr.data, arr.count * size_of(T);
	return arr_u8;
}
is_same_array :: (arr1 : []$T, arr2 : []T) -> bool {
	if arr1.count != arr2.count return false;
	arr1_u8 := to_u8_array(arr1);
	arr2_u8 := to_u8_array(arr2);
	for i : 0..arr1.count-1 {
		if arr1_u8[i] != arr2_u8[i] return false;
	}
	return true;
}
