extends Node2D

const GRID_SIZE: int = 7
const CELL: int = 60
const RADIUS: int = 24
const OFFSET: Vector2 = Vector2(80, 100)

var board: Array = []
var selected = null
var game_over_message: String = ""

func _ready() -> void:
	init_board()
	queue_redraw()

func _draw() -> void:
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(20, 30), "Pins remaining: %d" % count_pegs(), HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			if board[r][c] == -1:
				continue
			var pos = OFFSET + Vector2(c * CELL, r * CELL)
			draw_circle(pos, RADIUS + 6, Color(0.18, 0.18, 0.22))
			if board[r][c] == 1:
				var col = Color(0.85, 0.65, 0.2)
				if selected != null and selected == Vector2i(c, r):
					col = Color(0.95, 0.3, 0.3)
				draw_circle(pos, RADIUS, col)
	
	if game_over_message != "":
		draw_string(font, Vector2(20, 600), game_over_message, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)

func _input(event: InputEvent) -> void:
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
	
	board[from.y][from.x] = 0
	board[mid.y][mid.x] = 0
	board[to.y][to.x] = 1
	return true

func handle_click(cell: Vector2i) -> void:
	var c = cell.x
	var r = cell.y
	
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
		check_game_over()
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
	if r < 2 or r > 4:
		return c >= 2 and c <= 4
	return true

func count_pegs() -> int:
	var pegs = 0
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			if board[r][c] == 1:
				pegs += 1
	return pegs

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
	queue_redraw()

func _on_restart_button_pressed() -> void:
	restart_game()
