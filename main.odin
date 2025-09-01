package ovr_palette_generator

import "core:fmt"


import "base:intrinsics"
import "core:image"
import "core:image/png"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import stbi "vendor:stb/image"

COLOR_STRIDE :: 4

Color :: [4]u8

OVR_GenOption :: enum {
	PALETTE,
	INDEXED,
	BOTH,
}

OVR_GlobalOptions :: struct {
	pallete_path:       string,
	gen_option:         OVR_GenOption,
	using output_image: struct {
		w, h:     i32,
		out_path: string,
	},
	change_amount:      u8,
}

OVR_RowType :: enum {
	Brighten,
	Darken,
	Gradient,
	Solid,
}


OVR_Row :: struct {
	type:          OVR_RowType,
	palatte_index: [2]u8,
	y_index:       u8,
	pattern:       [dynamic]u8,
}

main :: proc() {
	if len(os.args) == 1 {
		fmt.println("ovrp_generator [PATH:description.ovrp]")
		return
	}
	path := os.args[1]
	if path == "--help" || path == "-h" {
		fmt.println("ovrp_generator [PATH:description.ovrp]")
		return
	}
	if !os.exists(path) || !strings.ends_with(path, ".orvp") {
		fmt.println("passed invalid path:", path)
		return
	}
	opts, rows, err := parse_ovrp_from_file(path)

	w, h: i32
	pixels := stbi.load(strings.clone_to_cstring(opts.pallete_path), &w, &h, nil, 4)

	palette_pixels := generate_ovr_palette(rows[:], opts)

	palette_path := parse_palette_file_path(opts.pallete_path)
	switch opts.gen_option {
	case .PALETTE:
		path := create_valid_path(opts.out_path, palette_path)
		fmt.println("saving to: ", path)
		stbi.write_png(
			strings.clone_to_cstring(path),
			opts.w,
			opts.h,
			4,
			&palette_pixels[0],
			opts.w * 4,
		)
	case .INDEXED:
		indexed := index_image(palette_pixels[:], opts.w, opts.h)
		path := create_valid_path(opts.out_path, palette_path, true)
		fmt.println("saving to: ", path)
		stbi.write_png(
			strings.clone_to_cstring(path),
			opts.w + 1,
			opts.h,
			4,
			&indexed[0],
			(opts.w + 1) * 4,
		)
	case .BOTH:
		path := create_valid_path(opts.out_path, palette_path)
		fmt.println("saving to: ", path)
		stbi.write_png(
			strings.clone_to_cstring(path),
			opts.w,
			opts.h,
			4,
			&palette_pixels[0],
			opts.w * 4,
		)
		indexed := index_image(palette_pixels[:], opts.w, opts.h)
		path = create_valid_path(opts.out_path, palette_path, true)
		fmt.println("saving to: ", path)
		stbi.write_png(
			strings.clone_to_cstring(path),
			opts.w + 1,
			opts.h,
			4,
			&indexed[0],
			(opts.w + 1) * 4,
		)
	}
}

generate_ovr_palette :: proc(
	rows: []OVR_Row,
	opts: OVR_GlobalOptions,
	allocator := context.allocator,
) -> [dynamic]u8 {
	palette_w, palette_h: i32
	palette_pixels := stbi.load(
		strings.clone_to_cstring(opts.pallete_path),
		&palette_w,
		&palette_h,
		nil,
		COLOR_STRIDE,
	)
	out_w, out_h := opts.output_image.w, opts.output_image.h
	out_image := make_dynamic_array_len([dynamic]u8, (out_w * COLOR_STRIDE) * out_h, allocator)
	for row in rows {
		write_row(
			row,
			&out_image,
			out_w,
			out_h,
			palette_pixels[0:palette_w * palette_h * COLOR_STRIDE],
			palette_w,
			palette_h,
		)
	}
	return out_image
}

write_row :: proc(
	ovr_row: OVR_Row,
	write_img: ^[dynamic]u8,
	w, h: i32,
	palette_img: []u8,
	p_w, p_h: i32,
) {

	if ovr_row.y_index < 0 && i32(ovr_row.y_index) >= h {
		return
	}
	index_color1 := get_color(
		palette_img,
		i32(ovr_row.palatte_index[0]) % p_w,
		i32(ovr_row.palatte_index[0]) / p_w,
		p_w,
	)
	index_color2 := get_color(
		palette_img,
		i32(ovr_row.palatte_index[1]) % p_w,
		i32(ovr_row.palatte_index[1]) / p_w,
		p_w,
	)
	#partial switch ovr_row.type {
	case .Solid:
		for x in 0 ..< w {
			set_color(write_img, index_color1, x, i32(ovr_row.y_index), w)
		}
	case .Brighten:
		new_color := index_color1
		for x in 0 ..< w {
			amount := ovr_row.pattern[x % i32(len(ovr_row.pattern))]
			new_color = color_add_u8(new_color, {amount, amount, amount, 0})
			set_color(write_img, new_color, x, i32(ovr_row.y_index), w)
		}

	case .Darken:
		new_color := index_color1
		for x in 0 ..< w {
			r, g, b, a := new_color.r, new_color.g, new_color.b, new_color.a
			amount: u8 = ovr_row.pattern[x % i32(len(ovr_row.pattern))]
			new_color = color_sub_u8(new_color, {amount, amount, amount, 0})
			set_color(write_img, new_color, x, i32(ovr_row.y_index), w)
		}
	case .Gradient:
		for x in 0 ..< w {
			f := f32(x) / f32(w)
			new_color := lerp_color_u8(index_color1, index_color2, f)
			set_color(write_img, new_color, x, i32(ovr_row.y_index), w)
		}
	}
}


index_image :: proc(img: []u8, w, h: i32, allocator := context.allocator) -> [dynamic]u8 {
	indexed_img := make_dynamic_array_len([dynamic]u8, ((w + 1) * COLOR_STRIDE) * h, allocator)
	for idx in 0 ..< h {
		set_color(&indexed_img, {u8(idx), 0, 0, 255}, 0, idx, w + 1)
	}
	for x in 1 ..= w {
		for y in 0 ..< h {
			set_color(&indexed_img, get_color(img, x, y, w), x, y, w + 1)
		}
	}
	return indexed_img
}

color_add_u8 :: proc(lhs, rhs: [4]u8) -> [4]u8 {
	return {
		u8(clamp(int(lhs.r) + int(rhs.r), 0, 255)),
		u8(clamp(int(lhs.g) + int(rhs.g), 0, 255)),
		u8(clamp(int(lhs.b) + int(rhs.b), 0, 255)),
		u8(clamp(int(lhs.a) + int(rhs.a), 0, 255)),
	}

}
color_sub_u8 :: proc(lhs, rhs: [4]u8) -> [4]u8 {
	return {
		u8(clamp(int(lhs.r) - int(rhs.r), 0, 255)),
		u8(clamp(int(lhs.g) - int(rhs.g), 0, 255)),
		u8(clamp(int(lhs.b) - int(rhs.b), 0, 255)),
		u8(clamp(int(lhs.a) - int(rhs.a), 0, 255)),
	}

}

color_mul_u8 :: proc(lhs, rhs: [4]u8) -> [4]u8 {
	return {
		u8(clamp(int(lhs.r) * int(rhs.r), 0, 255)),
		u8(clamp(int(lhs.g) * int(rhs.g), 0, 255)),
		u8(clamp(int(lhs.b) * int(rhs.b), 0, 255)),
		u8(clamp(int(lhs.a) * int(rhs.a), 0, 255)),
	}

}

lerp_color_u8 :: proc(c1, c2: [4]u8, f: f32) -> [4]u8 {
	f := clamp(f, 0, 1)
	return {
		u8(f32(c1.r) * (1 - f) + f32(c2.r) * f),
		u8(f32(c1.g) * (1 - f) + f32(c2.g) * f),
		u8(f32(c1.b) * (1 - f) + f32(c2.b) * f),
		u8(f32(c1.a) * (1 - f) + f32(c2.a) * f),
	}
}


clamp :: proc(v, min, max: $T) -> T where intrinsics.type_is_numeric(T) {
	if v < min do return min
	if v > max do return max
	return v
}

set_color :: proc(arr: ^[dynamic]u8, color: Color, x, y, w: i32) {
	idx := (x + (y * w)) * COLOR_STRIDE
	arr^[idx] = color.r
	arr^[idx + 1] = color.g
	arr^[idx + 2] = color.b
	arr^[idx + 3] = color.a
}


get_color :: proc(arr: []u8, x, y, w: i32) -> Color {
	idx := (x + (y * w)) * COLOR_STRIDE
	if int(idx) > len(arr) - 4 do return {0, 0, 0, 0}
	return {arr[idx], arr[idx + 1], arr[idx + 2], arr[idx + 3]}
}


@(require_results)
parse_ovrp_from_file :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	OVR_GlobalOptions,
	[dynamic]OVR_Row,
	os.Error,
) {
	data, err := os.read_entire_file_or_err(path)
	if err != nil {
		return {}, {}, err
	}

	str := strings.clone_from_bytes(data, allocator)
	lines := strings.split(str, "\n")
	cleaned := clean_lines(lines)
	opts: OVR_GlobalOptions
	rows: [dynamic]OVR_Row
	for line in cleaned {
		if strings.starts_with(line, "SETUP:") {
			opts = parse_global_options(line)
			continue
		}
		append(&rows, parse_ovr_row(line))
	}
	return opts, rows, nil
}


// SETUP: - Global setup
// input (def: panic) - path to palette (maybe even array of input)
// gen (def: PALETTE)- enum [PALETTE|INDEXED|BOTH]
// PALETTE - creates palette
// INDEXED - creates indexed palete (indexed= first column filled with red color coresponding to row (255 max))
// BOTH - dose both
// out (def: ovr_palette.png) - output path 
// out_size (def: 32, 256) - size of output texture (indexed always one widther) 
// change_amount (def: 10) - used to change value on x axis if not secified in row settings
parse_global_options :: proc(line: string) -> OVR_GlobalOptions {
	opts: OVR_GlobalOptions = {
		gen_option    = .PALETTE,
		out_path      = "ovr_palette.png",
		w             = 32,
		h             = 256,
		change_amount = 10,
	}
	key_value := create_keys_value_pairs(strings.trim_prefix(line, "SETUP:"))
	if gen_opt, ok := key_value["gen_files"]; ok {
		switch gen_opt {
		case "PALETTE":
			opts.gen_option = .PALETTE
		case "INDEXED":
			opts.gen_option = .INDEXED
		case "BOTH":
			opts.gen_option = .BOTH
		}
	}
	if change_amount, ok := key_value["change_amount"]; ok {
		opts.change_amount = u8(clamp(strconv.atoi(change_amount), 0, 255))
	}
	if input, ok := key_value["input"]; ok {
		opts.pallete_path = input
	}
	if out, ok := key_value["out"]; ok {
		opts.out_path = out
	}
	if out, ok := key_value["out"]; ok {
		opts.out_path = out
	}
	if out_size, ok := key_value["out_size"]; ok {
		arr := ovr_array_to_int_array(out_size)
		if len(arr) != 2 {
			fmt.println("inavlid out size")
		} else {
			opts.w = i32(arr[0])
			opts.h = i32(arr[1])
		}

	}
	return opts
}

// ROW: 
// type (def: BRIGHTEN)- color modifier enum [BRIGHTEN|DARKEN|GRADIENT|SOLID]
// SOLID - whole row in solid color
// BRIGHTEN - brightenss in corespondence of pattern or global amount
// DARKEN - darkens in corespondence of pattern or global amount
// GRADIENT - lerps between two colors
// index (def: {0, 0}) - ethier one or two indexes pointing to pallet pixels (only GRADIENT setting uses second index)
// y - y offset on texture dose nothing if not valid range
// pattern (def: 5,0,0,0,5,5,5,5)- patter that repeats over x axis and subtracts or adds value ex. $pattern=5,0,0,0,5,5,5,5
parse_ovr_row :: proc(line: string) -> OVR_Row {
	def_pattern := [?]u8{5, 0, 0, 0, 5, 5, 5, 5}
	row: OVR_Row = {
		type          = .Brighten,
		palatte_index = {0, 0},
		y_index       = 0,
	}
	key_value := create_keys_value_pairs(line)
	if type, ok := key_value["type"]; ok {
		switch type {
		case "GRADIENT":
			row.type = .Gradient
		case "BRIGHTEN":
			row.type = .Brighten
		case "DARKEN":
			row.type = .Darken
		case "SOLID":
			row.type = .Solid
		}
	}
	if y, ok := key_value["y"]; ok {
		row.y_index = u8(clamp(strconv.atoi(y), 0, 255))
	}
	if index, ok := key_value["index"]; ok {
		arr := ovr_array_to_int_array(index)
		if len(arr) == 1 {
			row.palatte_index.y = u8(arr[0])
		} else if len(arr) == 2 {
			row.palatte_index.x = u8(arr[0])
			row.palatte_index.y = u8(arr[1])
		}
	}
	if pattern, ok := key_value["pattern"]; ok {
		arr := ovr_array_to_int_array(pattern)
		if len(arr) != 0 {
			p: [dynamic]u8
			for n in arr {
				append(&p, u8(clamp(n, 0, 255)))
			}
			row.pattern = p
		}


	}
	if len(row.pattern) == 0 {
		p: [dynamic]u8
		for n in def_pattern {
			append(&p, n)
		}
		row.pattern = p
	}
	return row
}

ovr_array_to_int_array :: proc(line: string) -> [dynamic]int {
	parts := strings.split(line, ",")
	nums: [dynamic]int
	for part in parts {
		append(&nums, strconv.atoi(part))
	}
	return nums
}

create_keys_value_pairs :: proc(line: string) -> map[string]string {
	key_value_pairs := make_map(map[string]string)
	pairs := strings.split(line, "$")
	for pair in pairs {
		kv := strings.split(pair, "=")
		if len(kv) != 2 {
			continue
		}
		key_value_pairs[strings.trim_space(kv[0])] = strings.trim_space(kv[1])
	}
	return key_value_pairs
}

clean_lines :: proc(lines: []string) -> []string {
	cleaned: [dynamic]string
	for line in lines {
		if strings.starts_with(line, "#") || line == "" {
			continue
		}
		append(&cleaned, line)
	}
	return cleaned[:]
}


parse_palette_file_path :: proc(path: string) -> string {
	if strings.contains_rune(path, '/') {
		parts := strings.split(path, "/")
		if len(parts) == 0 {
			return "INVALID_PATH"
		}
		last := parts[len(parts) - 1]
		return strings.trim_suffix(last, ".png")
	}
	return strings.trim_suffix(path, ".png")
}

create_valid_path :: proc(path, palette_file: string, indexed: bool = false) -> string {
	path := path
	if strings.contains(path, "%s") {
		path = fmt.aprintf(path, palette_file)
	}
	if indexed {
		if strings.ends_with(path, ".png") {
			striped := strings.trim_suffix(path, ".png")
			return strings.join({path, "_indexed", ".png"}, "")
		}
	}
	if strings.ends_with(path, ".png") {
		return path
	}
	return strings.join({path, ".png"}, "")
}
