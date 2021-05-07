extends "res://scripts/system/BASE_SYS_SCRIPT.gd"

enum UNIT_FIGHT_STRATEGY {ATTACK_UNIT}

# вариация действия для юнита
class UnitFightAIVariation:
	var unit_info
	var fs_actions = []
	var cur_ap_count
	var points = 0

	func _init(_unit_info):
		unit_info = _unit_info
		cur_ap_count = unit_info.a_points_init_count

# АИ юнита которая анализирует вариации действий юнита
class UnitFightAI:
	var game
	var r

	var fight_team_ai_sys
	var strategy
	var unit_info_param # from fight system
	var unit_info
	var unit_node
	var unit_cur_tile

	var variations = [] # вариации возможных ходов (например проверка всех вражеских юнитов)

	var ally_team
	var enemy_team

	func _init(_fight_team_ai_sys, _strategy, _unit_info_param):
		fight_team_ai_sys = _fight_team_ai_sys
		game = fight_team_ai_sys.game
		
		strategy = _strategy
		unit_info_param = _unit_info_param
		unit_info = unit_info_param.info
		unit_node = game.get_unit_node_by_info(unit_info)
		r = unit_node.r

		unit_cur_tile = unit_node.get_current_tile()

		# находим союзную и вражескую команду
		if fight_team_ai_sys.team_tag == game.TEAM_TAG.PLAYER_TEAM:
			ally_team = game.fight_system.get_units_in_player_team()
			enemy_team = game.fight_system.get_units_in_enemy_team()
		elif fight_team_ai_sys.team_tag == game.TEAM_TAG.ENEMY_TEAM:
			ally_team = game.fight_system.get_units_in_enemy_team()
			enemy_team = game.fight_system.get_units_in_player_team()

		if !unit_node.is_dead():
			calculate_strategy()

	func calculate_strategy():
		var unit_cur_tile = unit_node.get_current_tile()

		if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
			print("AI CALCULATE STRATEGY FOR: " + unit_info.name)

		# СТРАТЕГИЯ НАПАДЕНИЯ
		if strategy == AI.UNIT_FIGHT_STRATEGY.ATTACK_UNIT:
			#var variation_param = {fs_actions = [], points = 0, cur_ap_count = unit_info.a_points_init_count}

			# проверяем всех вражеских юнитов
			# и добавляем вариант(ы?) поведения для каждого
			for en_unit_info in enemy_team:
				var en_unit_node = game.get_unit_node_by_info(en_unit_info)
				var en_unit_cur_tile = en_unit_node.get_current_tile()

				var unit_w_info = unit_node.get_current_now_weapon_info()

				if en_unit_node.is_dead():
					continue

				var cur_variation = UnitFightAIVariation.new(unit_info)

				var gen_path_to_en_unit = r.get_path_between_tiles(
					unit_cur_tile.get_tms(),
					en_unit_node.get_current_tile().get_tms())
				
				var dist_to_en_unit_in_t = gen_path_to_en_unit.size() - 1 # мб - 1 не нужен

				if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
					print("* AI Проверяется противник: " + en_unit_info.name)
					print("Расстояние до него в тайлах " + str(dist_to_en_unit_in_t))
					print("Дойти до него будет стоить " + str(game.fight_system.get_ap_count_for_unit_by_path(unit_info, gen_path_to_en_unit)) + " AP")
					print("\n")

				# если противник ранен у него больший приоритет для нападение
				cur_variation.points += 12 * en_unit_info.health / 10

				# предпочтительные тайлы для передвижения
				var preferred_move_tiles = []

				# ПОЛУЧАЕМ ТАЙЛЫ ИЗ КОТОРЫХ СКОРЕЕ ВСЕГО (если он не съебется) МОЖНО БУДЕТ ПОРАЗИТЬ ВРАЖЕСКОГО ЮНИТА
				var dir_from_en_unit_to_cur = r.get_dirs_from_tile_to_tile(
					unit_cur_tile, en_unit_cur_tile).h_dir_from_other_tile_to_cur
				
				var w_range_tiles_include_en_unit 
				
				if unit_w_info.is_melee():
					# в случае с холодным оружием получаем тайлы рядом с врагом за 1 AP
					w_range_tiles_include_en_unit = r.get_tiles_in_circle_sector_around_tile(
						en_unit_node.get_current_tile(), unit_info.penalty_ap_for_path_size)
				else:
					w_range_tiles_include_en_unit = r.get_tiles_in_range_sector(
						en_unit_cur_tile, dir_from_en_unit_to_cur, unit_node.get_current_now_weapon_info().attack_range, false)
				
				# удаляем тайлы на которых сейчас стоят враги
				var erased_w_range_tiles = []
				for en_unit in enemy_team:
					var cur_en_unit_node = game.get_unit_node_by_info(en_unit)
					
					if w_range_tiles_include_en_unit.has(cur_en_unit_node.get_current_tile()):
						erased_w_range_tiles.append(cur_en_unit_node.get_current_tile())
				# да и союзников тоже нахуй
				for al_unit in ally_team:
					var cur_al_unit_node = game.get_unit_node_by_info(al_unit)

					if w_range_tiles_include_en_unit.has(cur_al_unit_node.get_current_tile()):
						erased_w_range_tiles.append(cur_al_unit_node.get_current_tile())

				for er_tile in erased_w_range_tiles:
					w_range_tiles_include_en_unit.erase(er_tile)

				# каждому тайлу выдаётся определенное количество очков и доп параметры для анализа 
				var tile_ai_params = [] # {points, move_ap_count}

				var is_can_reach_tile_from_w_range = false # может ли приблизиться к врагу на расстояние атаки

				# анализируем эти тайлы
				for t in w_range_tiles_include_en_unit:
					var tile_ai_param = {tile = t, points = 0, gen_path = null, ap_count_for_gen_path = null}
					
					# получаем путь между тайлами
					tile_ai_param.gen_path = r.get_path_between_tiles(unit_cur_tile.get_tms(), t.get_tms(), true)
					# узнаём количество AP для этого пути
					tile_ai_param.ap_count_for_gen_path = game.fight_system.get_ap_count_for_unit_by_path(unit_info, tile_ai_param.gen_path)

					if unit_w_info.is_melee():
						tile_ai_param.points += 100 - dist_to_en_unit_in_t * 20
					else:
						# получаем очки за укрытие в этом тайле
						tile_ai_param.points += get_ai_tile_points_count_by_def_cover_str_between_hostile_tiles(unit_cur_tile, en_unit_cur_tile)
					
					if tile_ai_param.ap_count_for_gen_path <= cur_variation.cur_ap_count:
						is_can_reach_tile_from_w_range = true

					# за каждый лишний AP даём штраф очкам
					for i in range(tile_ai_param.ap_count_for_gen_path):
						if i >= 1:
							tile_ai_param.points -= 6

					# если на этом тайле находится союзник вычитаем много очков
					# эту хуйню уже в другое место перенес
					#for ally_unit in ally_team:
					#	if game.get_unit_node_by_info(ally_unit).get_current_tile() == t:
					#		tile_ai_param.points -= 100

					# анализируем меткость вражеского юнита к этому тайлу и снимаем опр. кол. очков
					var en_w_info = en_unit_node.get_current_now_weapon_info()
					var w_accuracy = game.get_weapon_accuracy_from_tile_to_tile(en_w_info, en_unit_cur_tile, t, en_unit_node)
					tile_ai_param.points -= 35 * w_accuracy

					tile_ai_params.append(tile_ai_param)

				# ЕСЛИ ЮНИТУ ХВАТИТ AP ДОБРАТЬСЯ ДО ЗОНЫ ПОРАЖЕНИЯ ПРОТИВНИКА
				if is_can_reach_tile_from_w_range:
					# сортируем параметры тайлов по очкам			
					var sorted_tile_ai_params = SYS.sort_params_arr_by_key_value(tile_ai_params, "points")
					
					var best_tiles_count = unit_info.ai_precision
					var best_tiles_params = [] # несколько лучших тайлов
					for i in range(best_tiles_count):
						if i > sorted_tile_ai_params.size() - 1:
							break
						else:
							if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
								print(str(i + 1) + " best tile has " + str(sorted_tile_ai_params[i].points))
							best_tiles_params.append(sorted_tile_ai_params[i])

					if best_tiles_params.size() == 0:
						print("AI best_tiles_params error! size() = 0")
						return

					var selected_best_tile_param = SYS.get_random_arr_item(best_tiles_params)
					var move_ap_points = selected_best_tile_param.ap_count_for_gen_path
					var attack_ap_points = cur_variation.cur_ap_count - selected_best_tile_param.ap_count_for_gen_path
					
					if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
						print(unit_info.name + " has " + str(move_ap_points) + " move AP points")
						print(unit_info.name + " has " + str(attack_ap_points) + " attack AP points")
					
					# ATTACK ACTIONS
					var attack_fs_actions = []
					for i in range(attack_ap_points):
						attack_fs_actions.append(get_preffered_weapon_fs_action_against_enemy_unit(en_unit_node, attack_fs_actions))

						if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
							print("Weapon fs action against " + str(en_unit_info.name))

						cur_variation.points += 13

					for attack_fs_action in attack_fs_actions:
						cur_variation.fs_actions.append(attack_fs_action)
						
					# MOVE ACTIONS
					for i in range(move_ap_points):
						var move_from_tile = unit_cur_tile

						var move_gen_path = selected_best_tile_param.gen_path

						# рисуем путь
						unit_node.set_visual_move_path(move_gen_path)
						
						cur_variation.fs_actions.append(
							game.fight_system.get_fs_unit_action(
								unit_info, game.UNIT_ACTION_TAG.MOVE_TO_TILE, 2, 
								{gen_path = move_gen_path}
							)
						)

						cur_variation.points += selected_best_tile_param.points

						if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
							print("AI variatuion added, points: " + str(cur_variation.points))

					
				# ЕСЛИ НЕ МОЖЕТ ДОБРАТЬСЯ ДО ПРОТИВНИКА ДЛЯ АТАКИ
				else:
					if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
						print("AI variatuion UNIT CANT REACH ENEMY UNIT, searching another ways... ")

					for i in range(cur_variation.cur_ap_count):
						var from_tile

						var prev_move_fs_action = game.fight_system.get_fs_action_in_unit_info_param_with_tag(
							unit_info, game.UNIT_ACTION_TAG.MOVE_TO_TILE, cur_variation.fs_actions)

						if prev_move_fs_action == null:
							from_tile = unit_cur_tile
						else:
							from_tile = prev_move_fs_action.addit_params.gen_path.back()

						var dirs_to_en_tile = r.get_dirs_from_tile_to_tile(from_tile, en_unit_cur_tile)

						var move_reach_sector_tiles = r.get_tiles_in_circle_sector_around_tile(from_tile, unit_info.penalty_ap_for_path_size)
						
						# делим сектор тайлов получая только тайлы в направлении противника
						var h_sector_tiles = r.get_tiles_in_dir_from_center_in_tiles_circle_sector(
							from_tile, move_reach_sector_tiles, dirs_to_en_tile.h_dir_to_other_tile
						)
						var v_sector_tiles = r.get_tiles_in_dir_from_center_in_tiles_circle_sector(
							from_tile, move_reach_sector_tiles, dirs_to_en_tile.v_dir_to_other_tile
						)

						var tiles_ai_params = []

						var analyse_tiles = h_sector_tiles + v_sector_tiles
						
						for an_t in analyse_tiles:
							var tile_ai_param = {tile = an_t, points = 0, gen_path = null, dont_move_and_attack_unit = null}
							# если в секторе перемещения есть противники с определнным шансом добавляем действие атаки (авось попадёт)
							var en_units_on_this_tile = []
							for en_unit in enemy_team:
								if r.get_units_with_current_tile(an_t).has(game.get_unit_node_by_info(en_unit)):
									en_units_on_this_tile.append(en_unit)

							if en_units_on_this_tile.size() > 0:
								var path_between_units = r.get_path_between_tiles(from_tile.get_tms(), an_t.get_tms(), true)
								tile_ai_param.points = 160
								for i in range(path_between_units.size()):
									tile_ai_param.points -= 30
								var en_unit = SYS.get_random_arr_item(en_units_on_this_tile)
								tile_ai_param.dont_move_and_attack_unit = en_unit

							else:
								# получаем очки за укрытие в этом тайле
								tile_ai_param.points += get_ai_tile_points_count_by_def_cover_str_between_hostile_tiles(an_t, en_unit_cur_tile)
								# получаем путь между тайлами
								tile_ai_param.gen_path = r.get_path_between_tiles(from_tile.get_tms(), an_t.get_tms(), true)

								if h_sector_tiles.has(an_t) and v_sector_tiles.has(an_t):
									tile_ai_param.points += 15

							tiles_ai_params.append(tile_ai_param)

						# ВЫБИРАЕМ FS ACTION НА ЭТУ ИТЕРАЦИЮ
						# сортируем параметры тайлов по очкам			
						var sorted_tile_ai_params = SYS.sort_params_arr_by_key_value(tiles_ai_params, "points")
						
						var best_tiles_count = unit_info.ai_precision
						var best_tiles_params = [] # несколько лучших тайлов
						for i in range(best_tiles_count):
							if i > sorted_tile_ai_params.size() - 1:
								break
								
							if PLAYER.PARAMS.AI_CONSOLE_DEBUG_ENABLED:
								print(str(i + 1) + " best tile has " + str(sorted_tile_ai_params[i].points))
								if sorted_tile_ai_params[i].dont_move_and_attack_unit != null:
									print(unit_info.name + " TRY TO ATTACK " + sorted_tile_ai_params[i].dont_move_and_attack_unit.info.name)
									
							best_tiles_params.append(sorted_tile_ai_params[i])

						var selected_best_tile_param = SYS.get_random_arr_item(best_tiles_params)
						# move
						if selected_best_tile_param != null and selected_best_tile_param.dont_move_and_attack_unit == null:
							var move_to_tile = selected_best_tile_param.tile
							cur_variation.fs_actions.append(game.fight_system.get_fs_unit_action(
								unit_info, game.UNIT_ACTION_TAG.MOVE_TO_TILE, 2, 
								{gen_path = selected_best_tile_param.gen_path}
							))
						# try to attack unit
						else:
							cur_variation.fs_actions.append(get_preffered_weapon_fs_action_against_enemy_unit(
								selected_best_tile_param.dont_move_and_attack_unit))

				variations.append(cur_variation)

	# получает лучшие выбранные fs_actions из разных вариантов
	func get_selected_fs_actions():
		# test
		if variations.size() > 0:
			var sel_variation = SYS.get_random_arr_item(variations)
			print("Selected variation (points: " + str(sel_variation.points) +")")
			return sel_variation.fs_actions
		else:
			print("AI game fs get_selected_fs_actions() variations size <= 0 returned []")
			return []

	# получает предпочтительное действия для оружия юнита (перезаряжать или атаковать цель и тд)
	func get_preffered_weapon_fs_action_against_enemy_unit(_target_unit, _cur_fs_actions = []):
		var unit_w_info = unit_node.get_current_now_weapon_info()
		var preffered_fs_action

		# RELOAD (если не хватает патронов на атаку и нет действия перезарядка)
		if unit_w_info.w_class != HUMANS.WEAPON_CLASS.MELEE and unit_w_info.get_ammo_for_attack_count() > unit_w_info.cur_ammo and \
			game.fight_system.get_fs_action_in_unit_info_param_with_tag(unit_info, game.UNIT_ACTION_TAG.RELOAD_W, _cur_fs_actions) == null:

			preffered_fs_action = game.fight_system.get_fs_unit_action(
				unit_info, game.UNIT_ACTION_TAG.RELOAD_W, 1, {})

		# ATTACK
		else:
			preffered_fs_action = game.fight_system.get_fs_unit_action(
				unit_info, game.UNIT_ACTION_TAG.ATTACK_UNIT, 1,
				{aggresor_unit = unit_node, target_unit = _target_unit}
			)
		return preffered_fs_action

	# ПОЛУЧЕНИЕ AI ОЧКОВ

	# получает количество очков для параметра тайла в зависимости от его укрытия
	# относительно вражеского тайла (на котором находится противник)
	func get_ai_tile_points_count_by_def_cover_str_between_hostile_tiles(_cur_tile, _hostile_tile):
		var cur_t = _cur_tile
		var hostile_t = _hostile_tile
		
		var dirs_from_cur_t_to_hostile_t = r.get_dirs_from_tile_to_tile(_cur_tile, _hostile_tile)
		
		var h_dir_to_other_tile = dirs_from_cur_t_to_hostile_t.h_dir_to_other_tile
		var v_dir_to_other_tile = dirs_from_cur_t_to_hostile_t.v_dir_to_other_tile
		var h_dir_from_other_tile_to_cur = dirs_from_cur_t_to_hostile_t.h_dir_from_other_tile_to_cur
		var v_dir_from_other_tile_to_cur = dirs_from_cur_t_to_hostile_t.v_dir_from_other_tile_to_cur

		# получаем нужные стороны укрытия, для того что бы позже выдать за них определенное количество очков
		var tile_needed_h_def_cov_str
		var tile_needed_v_def_cov_str
		var hostile_t_needed_h_def_cov_str
		var hostile_t_needed_v_def_cov_str

		var tile_def_cover_str = r.get_def_cover_str_in_tile(cur_t)
		var hostile_tile_def_cover_str = r.get_def_cover_str_in_tile(hostile_t)

		if h_dir_from_other_tile_to_cur == SYS.DIR.LEFT:
			tile_needed_h_def_cov_str = tile_def_cover_str.left
			hostile_t_needed_h_def_cov_str = hostile_tile_def_cover_str.right
		else:
			tile_needed_h_def_cov_str = tile_def_cover_str.right
			hostile_t_needed_h_def_cov_str = hostile_tile_def_cover_str.left

		if v_dir_from_other_tile_to_cur == SYS.DIR.UP:
			tile_needed_v_def_cov_str = tile_def_cover_str.up
			hostile_t_needed_v_def_cov_str = hostile_tile_def_cover_str.down
		else:
			tile_needed_v_def_cov_str = tile_def_cover_str.down
			hostile_t_needed_h_def_cov_str = hostile_tile_def_cover_str.up

		var points_count = 0

		# ПРОВЕРЯЕМ ЗАЩИТУ ТАЙЛА
		var check_current_defs = [tile_needed_h_def_cov_str, tile_needed_v_def_cov_str]
		var check_hostile_defs = [hostile_t_needed_h_def_cov_str, hostile_t_needed_v_def_cov_str]
		for i in range(2):
			var check_defs
			if i == 0:
				check_defs = check_current_defs
			else:
				check_defs = check_hostile_defs

			for check_def in check_defs:
				if check_def == null:
					if i == 0:
						points_count -= 15
					else:
						points_count += 15

				elif check_def == ENV.DEFENCE_COVER_STRENGTH.LOW:
					if i == 0:
						points_count += 5
					else:
						points_count -= 4

				elif check_def == ENV.DEFENCE_COVER_STRENGTH.MEDIUM:
					if i == 0:
						points_count += 10
					else:
						points_count -= 9

				elif check_def == ENV.DEFENCE_COVER_STRENGTH.HIGH:
					if i == 0:
						points_count += 15
					else:
						points_count -= 14

				elif check_def == ENV.DEFENCE_COVER_STRENGTH.HIGH_WALL:
					if i == 0:
						points_count += 20
					else:
						points_count -= 21
				else:
					print("ERROR! UNDEFINED check_def type in get_ai_tile_points_count_by_def_cover_str_between_hostile_tiles()")

		return points_count

# АИ для команды в бою
class FightTeamAISys:
	var game
	var team
	var team_tag
	var units_ai_params = [] # параметры с различными вариантами UnitFightAI

	func _init(_game):
		game = _game

	func setup_fs_actions_for_team(_team_array):
		units_ai_params = []

		team_tag = null
		team = _team_array
		
		# НАСТРАИВАЕТ AI ДЛЯ КАЖДОГО ЮНИТА В КОМАНДЕ
		for u_info in team:
			var cur_unit_info_param = game.fight_system.get_unit_info_param_by_info(u_info)
			# получаем тег команды если он ещё не получен
			if team_tag == null:
				team_tag = cur_unit_info_param.team_tag

			# ТУТ ПОТОМ СКОРЕЕ ВСЕГО НУЖНО БУДЕТ ПРОВЕРЯТЬ ХП И ТД ДЛЯ ВЫСТАВЛЕНИЯ ПРАВИЛЬНОЙ СТРАТЕГИИ
			create_fight_ai_for_unit_info_param(
				AI.UNIT_FIGHT_STRATEGY.ATTACK_UNIT, cur_unit_info_param)

		# ВЫДАЁТ ЮНИТАМ СГЕНЕРИРОВАННЫЙ fs_actions
		for unit_ai_param in units_ai_params:
			unit_ai_param.unit_info_param.fs_actions = unit_ai_param.selected_fs_actions

	func create_fight_ai_for_unit_info_param(_strategy, _u_i_param):
		var new_ai = AI.UnitFightAI.new(self, _strategy, _u_i_param)
		var new_unit_ai_param = {unit_info_param = _u_i_param, ai = new_ai, selected_fs_actions = null}
		new_unit_ai_param.selected_fs_actions = new_unit_ai_param.ai.get_selected_fs_actions()

		units_ai_params.append(new_unit_ai_param)

var game
var fight_team_ai_sys  

func start_script():
	.start_script()

func set_game(_game):
	game = _game
	fight_team_ai_sys = FightTeamAISys.new(game)

# СТРАТЕГИЯ AI
# У КАЖДОГО ЮНИТА ГЕНЕРИРУЕТСЯ СТРАТЕГИЯ АТАКИ ДЛЯ КАЖДОГО ВРАЖЕСКОГО ЮНИТА
# 
# ЗА КАЖДОЕ ВОЗМОЖНОЕ ДЕЙСТВИЕ ГЕНЕРИРУЮТСЯ ОЧКИ
# ВСЕ ЭТИ ДЕЙСТВИЯ ~ВОЗМОЖНО~ ПРОИЗОЙДУТ ИБО ЕСТЬ ШАНС ПРОМАХА И Т.Д.

# ЕСЛИ ДЕЙСТВИЕ ВЫПОЛНЯЕТСЯ С ОПРЕДЕЛЕННЫМ ШАНСОМ (НАПРИМЕР АТАКА) НАЧИСЛЯЮТСЯ ДОП ОЧКИ
# ЕСЛИ ШАНС БОЛЬШЕ 75%: +15
# ЕСЛИ ШАНС БОЛЬШЕ 50%: +10
# ЕСЛИ ШАНС БОЛЬШЕ 25%: +3
# ЕСЛИ ШАНС БОЛЬШЕ 5%: -5
# ИНАЧЕ: -15
# ЕСЛИ ЕСТЬ ДРУЖЕСТВЕННЫЙ ЮНИТ КОТОРЫЙ УЖЕ АТАКУЕТ ЭТУ ЦЕЛЬ + 15

# ЮНИТ ВОЗМОЖНО УБЬЁТ ЮНИТА ИГРОКА + 10
# ЮНИТ ВОЗМОЖНО НАНЕСЕТ УРОН + 5
# ЮНИТ ПОЛУЧИТ МАЛ. УРОН - 3
# ЮНИТ АТАКУЕТ ИЗ СРЕДНЕГО УКРЫТИЯ + 10
# ЮНИТ АТАКУЕТ ИЗ МАКСИМАЛЬНОГО УКРЫТИЯ + 20