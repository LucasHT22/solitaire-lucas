extends Node2D

enum { SHAPE_ENGLISH, SHAPE_EUROPEAN, SHAPE_FULL }
const SHAPE_NAMES = ["English Cross (33)", "European Cross (37)", "Full Square (49)"]

const GRID_SIZE: int = 7
const CELL: int = 60
const RADIUS: int = 24
const OFFSET: Vector2 = Vector2(80, 100)
const JUMP_DURATION: float = 0.25
const SOLVER_PEG_THRESHOLD: int = 22

@onready var hint_button: Button = $HintButton
@onready var count_button: Button = $CountButton
@onready var solve_button: Button = $SolveButton

var board: Array = []
var selected = null
var game_over_message: String = ""
var board_shape: int = SHAPE_ENGLISH

var animating: bool = false
var anim_from: Vector2i
var anim_mid: Vector2i
var anim_to: Vector2i
var anim_progress: float = 0.0

var solving: bool = false
var valid_cells: Array = []
var cell_index: Dictionary = {}
var solver_moves: Array = []
var solver_failed_cache: Dictionary = {}
var solution_count_cache: Dictionary = {}

var hint_move = null

func _ready() -> void:
	init_board()
	build_solver_data()
	update_solver_buttons()
	queue_redraw()

func _draw() -> void:
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(20, 30), "Pins remaining: %d" % count_pegs(), HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	draw_string(font, Vector2(20, 55), "Board: %s" % SHAPE_NAMES[board_shape], HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
	
	for c in range(GRID_SIZE):
		var label = char(65 + c)
		draw_string(font, OFFSET + Vector2(c * CELL - 5, -20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6))
	for r in range(GRID_SIZE):
		var label = str(r + 1)
		draw_string(font, OFFSET + Vector2(-28, r * CELL + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.6))
	
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			if board[r][c] == -1:
				continue
			var pos = OFFSET + Vector2(c * CELL, r * CELL)
			draw_circle(pos, RADIUS + 6, Color(0.18, 0.18, 0.22))
			
			if animating and Vector2i(c, r) == anim_to:
				continue
			
			if board[r][c] == 1:
				var col = Color(0.85, 0.65, 0.2)
				if selected != null and selected == Vector2i(c, r):
					col = Color(0.95, 0.3, 0.3)
				draw_circle(pos, RADIUS, col)
	
	if selected != null and not animating:
		for dest in valid_destinations(selected):
			var pos = OFFSET + Vector2(dest.x * CELL, dest.y * CELL)
			draw_arc(pos, RADIUS + 3, 0, TAU, 32, Color(0.3, 0.9, 0.4), 3.0)
	
	if hint_move != null:
		var hf = OFFSET + Vector2(hint_move.from.x * CELL, hint_move.from.y * CELL)
		var ht = OFFSET + Vector2(hint_move.to.x * CELL, hint_move.to.y * CELL)
		draw_arc(hf, RADIUS + 5, 0, TAU, 32, Color(0.3, 0.6, 1.0), 3.0)
		draw_arc(ht, RADIUS + 5, 0, TAU, 32, Color(0.3, 0.6, 1.0), 3.0)
		draw_line(hf, ht, Color(0.3, 0.6, 1.0, 0.6), 2.0)
	
	if animating:
		var from_pos = OFFSET + Vector2(anim_from.x * CELL, anim_from.y * CELL)
		var to_pos = OFFSET + Vector2(anim_to.x * CELL, anim_to.y * CELL)
		var current_pos = from_pos.lerp(to_pos, anim_progress)
		draw_circle(current_pos, RADIUS, Color(0.85, 0.65, 0.2))
		
		var mid_pos = OFFSET +Vector2(anim_mid.x * CELL, anim_mid.y * CELL)
		draw_circle(mid_pos, RADIUS, Color(0.85, 0.65, 0.2, 1.0 - anim_progress))
	
	if count_pegs() > SOLVER_PEG_THRESHOLD:
		draw_string(font, Vector2(20, 75), "Solver unlocks at %d pegs or fewer" % SOLVER_PEG_THRESHOLD, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.5, 0.3))
	
	if game_over_message != "":
		draw_string(font, Vector2(20, 600), game_over_message, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)

func _input(event: InputEvent) -> void:
	if animating or solving:
		return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = event.position
		for r in range(GRID_SIZE):
			for c in range(GRID_SIZE):
				if board[r][c] == -1:
					continue
				var pos = OFFSET + Vector2(c * CELL, r * CELL)
				if local.distance_to(pos) <= RADIUS + 6:
					handle_click(Vector2i(c, r))
					return
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		restart_game()

func update_solver_buttons() -> void:
	var enabled = count_pegs() <= SOLVER_PEG_THRESHOLD
	hint_button.disabled = not enabled
	count_button.disabled = not enabled

func try_move(from: Vector2i, to: Vector2i) -> bool:
	if board[to.y][to.x] != 0:
		return false
	
	var dx = to.x - from.x
	var dy = to.y - from.y
	
	var is_horizontal_jump = (absi(dx) == 2 and dy == 0)
	var is_vertical_jump = (absi(dy) == 2 and dx == 0)
	if not (is_horizontal_jump or is_vertical_jump):
		return false
	
	var mid = Vector2i(from.x + dx / 2, from.y + dy / 2)
	if board[mid.y][mid.x] != 1:
		return false
	
	anim_from = from
	anim_mid = mid
	anim_to = to
	
	board[from.y][from.x] = 0
	board[mid.y][mid.x] = 0
	board[to.y][to.x] = 1
	return true

func handle_click(cell: Vector2i) -> void:
	var c = cell.x
	var r = cell.y
	hint_move = null
	
	if selected == null:
		if board[r][c] == 1:
			selected = cell
		queue_redraw()
		return
	
	if selected == cell:
		selected = null
		queue_redraw()
		return
	
	if try_move(selected, cell):
		selected = null
		start_jump_animation()
	else:
		if board[r][c] == 1:
			selected = cell
		else:
			selected = null
	
	queue_redraw()

func init_board() -> void:
	board.clear()
	for r in range(GRID_SIZE):
		var row = []
		for c in range(GRID_SIZE):
			if is_valid_cell(r, c):
				row.append(1)
			else:
				row.append(-1)
		board.append(row)
	board[3][3] = 0

func is_valid_cell(r: int, c: int) -> bool:
	match board_shape:
		SHAPE_ENGLISH:
			if r < 2 or r > 4:
				return c >= 2 and c <= 4
			return true
		SHAPE_EUROPEAN:
			var width_by_row = [3, 5, 7, 7, 7, 5, 3]
			var w = width_by_row[r]
			var start = int((GRID_SIZE - w) / 2.0)
			return c >= start and c < start + w
		SHAPE_FULL:
			return true
	return false

func count_pegs() -> int:
	var pegs = 0
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			if board[r][c] == 1:
				pegs += 1
	return pegs

func valid_destinations(from: Vector2i) -> Array:
	var dests = []
	var dirs = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	for d in dirs:
		var to = Vector2i(from.x + d.x, from.y + d.y)
		if to.x < 0 or to.x >= GRID_SIZE or to.y < 0 or to.y >= GRID_SIZE:
			continue
		if board[to.y][to.x] != 0:
			continue
		var mid = Vector2i(from.x + d.x / 2, from.y + d.y / 2)
		if board[mid.y][mid.x] == 1:
			dests.append(to)
	return dests

func has_move(r: int, c: int) -> bool:
	var dirs = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	for d in dirs:
		var to = Vector2i(c + d.x, r + d.y)
		if to.x < 0 or to.x >= GRID_SIZE or to.y < 0 or to.y >= GRID_SIZE:
			continue
		if board[to.y][to.x] != 0:
			continue
		var mid = Vector2i(c + d.x / 2, r + d.y / 2)
		if board[mid.y][mid.x] == 1:
			return true
	return false

func check_game_over() -> void:
	var moves_available = false
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			if board[r][c] == 1 and has_move(r, c):
				moves_available = true
	if not moves_available:
		if count_pegs() == 1:
			game_over_message = "You win! 1 pin left!"
		else:
			game_over_message = "Game over! Pins remaining: %d" % count_pegs()

func restart_game() -> void:
	init_board()
	selected = null
	game_over_message = ""
	animating = false
	solving = false
	hint_move = null
	solver_failed_cache.clear()
	solution_count_cache.clear()
	update_solver_buttons()
	queue_redraw()
 
func start_jump_animation() -> void:
	animating = true
	anim_progress = 0.0
	var tween = create_tween()
	tween.tween_method(_on_anim_step, 0.0, 1.0, JUMP_DURATION)
	tween.tween_callback(_on_anim_finished)

func _on_anim_step(t: float) -> void:
	anim_progress = t
	queue_redraw()

func _on_anim_finished() -> void:
	animating = false
	update_solver_buttons()
	queue_redraw()
	check_game_over()

func _on_restart_button_pressed() -> void:
	restart_game()

func _on_solve_button_pressed() -> void:
	if animating or solving:
		return
	hint_move = null
	
	var mask = board_to_bitmask()
	var pegs = count_pegs()
	
	if pegs > SOLVER_PEG_THRESHOLD:
		game_over_message = "Solving %d pegs - this may take a moment..." % pegs
		solve_button.disabled = true
		queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
	
	solver_failed_cache.clear()
	var solution = solve_from(mask)
	
	solve_button.disabled = false
	
	if solution == null:
		game_over_message = "No possible solution."
		queue_redraw()
		return
	
	game_over_message = ""
	play_solution(solution)

func build_solver_data() -> void:
	valid_cells.clear()
	cell_index.clear()
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			if is_valid_cell(r, c):
				cell_index[Vector2i(c, r)] = valid_cells.size()
				valid_cells.append(Vector2i(c, r))
	
	solver_moves.clear()
	var dirs = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	for cell in valid_cells:
		for d in dirs:
			var mid = cell + Vector2i(d.x / 2, d.y / 2)
			var to = cell + d
			if cell_index.has(mid) and cell_index.has(to):
				solver_moves.append({
					"from": cell_index[cell],
					"mid": cell_index[mid],
					"to": cell_index[to]
				})

func board_to_bitmask() -> int:
	var mask = 0
	for i in range(valid_cells.size()):
		var v = valid_cells[i]
		if board[v.y][v.x] == 1:
			mask |= (1 << i)
	return mask

func count_bits(mask: int) -> int:
	var count = 0
	var m = mask
	while m != 0:
		count += m & 1
		m >>= 1
	return count

func solve_from(mask: int) -> Variant:
	if count_bits(mask) == 1:
		return []
	if solver_failed_cache.has(mask):
		return null
	
	for move in solver_moves:
		var from_bit = 1 << move.from
		var mid_bit = 1 << move.mid
		var to_bit = 1 << move.to
		if (mask & from_bit) != 0 and (mask & mid_bit) != 0 and (mask & to_bit) == 0:
			var new_mask = mask
			new_mask &= ~from_bit
			new_mask &= ~mid_bit
			new_mask |= to_bit
			var rest = solve_from(new_mask)
			if rest != null:
				var result = [move]
				result.append_array(rest)
				return result
	
	solver_failed_cache[mask] = true
	return null

func count_solutions(mask: int) -> int:
	if count_bits(mask) == 1:
		return 1
	if solution_count_cache.has(mask):
		return solution_count_cache[mask]
	
	var total = 0
	for move in solver_moves:
		var from_bit = 1 << move.from
		var mid_bit = 1 << move.mid
		var to_bit = 1 << move.to
		if (mask & from_bit) != 0 and (mask & mid_bit) != 0 and (mask & to_bit) == 0:
			var new_mask = mask
			new_mask &= ~from_bit
			new_mask &= ~mid_bit
			new_mask |= to_bit
			total += count_solutions(new_mask)
	
	solution_count_cache[mask] = total
	return total

func play_solution(moves: Array) -> void:
	solving = true
	for move in moves:
		var from_v: Vector2i = valid_cells[move.from]
		var to_v: Vector2i = valid_cells[move.to]
		
		selected = from_v
		queue_redraw()
		await get_tree().create_timer(0.25).timeout
		
		try_move(from_v, to_v)
		start_jump_animation()
		await get_tree().create_timer(JUMP_DURATION + 0.05).timeout
	
	selected = null
	solving = false
	queue_redraw()


func _on_hint_button_pressed() -> void:
	if animating or solving:
		return
	var mask = board_to_bitmask()
	solver_failed_cache.clear()
	var solution = solve_from(mask)
	if solution == null or solution.size() == 0:
		game_over_message = "No hint from here."
		queue_redraw()
		return
	var first_move = solution[0]
	hint_move = {
		"from": valid_cells[first_move.from],
		"to": valid_cells[first_move.to]
	}
	selected = null
	queue_redraw()


func _on_shape_button_pressed() -> void:
	if animating or solving:
		return
	
	board_shape = (board_shape + 1) % SHAPE_NAMES.size()
	build_solver_data()
	restart_game()


func _on_count_button_pressed() -> void:
	if animating or solving:
		return
	var mask = board_to_bitmask()
	solution_count_cache.clear()
	var total = count_solutions(mask)
	game_over_message = "Distinct solutions from here: %d" % total
	queue_redraw()
