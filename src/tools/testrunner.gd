# testrunner.gd — the game side's test suite. Run it headless:
#
#     godot --headless --path . res://scene/tests/tests.tscn
#
# Exits 0 if everything passes, 1 if anything fails, so it can gate a commit the
# same way test_api.py does.
#
# WHY THIS EXISTS
# ---------------
# Every one of the 367 tests in this project is on the Flask side. The Godot half
# has only ever been verified by booting it and reading the log, which is how an
# owner panel bound to a key that closes the game, a dead revive branch that
# could never be reached, and a README describing a deleted file all survived.
# None of those were carelessness. They were the absence of anything that fails.
#
# WHAT BELONGS IN HERE
# --------------------
# Logic that can be checked without playing the game: curves, arithmetic, save
# round trips, and above all THE NUMBERS THAT MUST AGREE WITH THE SERVER. Those
# are the ones where drift is silent and expensive — the XP curve once lived in
# two places, disagreed, and rewrote every save on load for a day before anyone
# worked out why.
#
# What does NOT belong: anything needing a player in a world, a physics frame, or
# a rendered scene. That is what booting the game is for.
# THE SUITE IS SPLIT (0.85.0) into a chain of scripts, each extending the one
# before, so every test still runs on this one node with every helper and
# every count: testrunner_base.gd (the counters, check(), section(), the
# shared consts and helpers) <- testrunner_1.gd <- ... <- this file, which
# holds only _ready() and _run_all(). A test lives in a numbered part, and
# a test may call only a test in its own part or an earlier one. One file of
# 2 MB was costly to copy and to edit; a run of a few tests now only edits
# _run_all() here. _is_suite_script() is how a scan leaves the suite out.
extends "res://src/tools/testrunner_8.gd"


func _ready() -> void:
	# Wait one frame before doing anything. Calling get_tree().quit() from inside
	# _ready(), while the tree and the autoloads are still coming up, is a bad
	# idea on its own terms: the suite would be judging a half-built world.
	#
	# THIS COMMENT USED TO CLAIM THE AWAIT ALSO PREVENTED "ObjectDB instances
	# leaked at exit", and that it was harmless when it appeared. Both halves
	# were wrong, and the first run this file ever completed printed the warning
	# anyway. Running it with --verbose named the culprit in one line: a leaked
	# GDScriptFunctionState with orphan StringNames get_json, request_completed
	# and completed - api.gd's unawaited boot probe, still waiting on a three
	# second HTTP timeout when quit() arrived. Fixed there, with the reasoning.
	#
	# WORTH KEEPING AS A LESSON. A comment asserting that a warning is harmless
	# is the most expensive kind of comment there is: it does not just fail to
	# help, it actively tells the next person not to look. A comment cannot fail,
	# so this one went unexamined from the day it was written until the day the
	# file first ran.
	await get_tree().process_frame
	_say("")
	_watch_script_errors()
	_play_in_a_world_of_its_own()
	# NO SCREEN REST IN A RUN (0.55.0). Nobody touches a suite, and two minutes
	# in its veil and its frame cap would be what a dozen checks measured.
	var rest_watch: Timer = Settings.get("_rest_timer") as Timer
	if rest_watch != null:
		rest_watch.stop()
	await _run_all()
	_report()


func _run_all() -> void:
	# FIRST, DELIBERATELY. A script that will not compile makes unrelated sections
	# fail for reasons their own names do not mention. See the header above
	# _test_every_script_compiles() for the eight gold failures that came out of
	# one bad line in baseenemy.gd.
	_test_every_script_compiles()
	_test_curve_agreement()
	_test_skill_curves()
	_test_shared_constants()
	_test_class_curves()
	_test_enemy_constants()
	_test_player_stats()
	_test_facing()
	_test_formation()
	_test_pet_controller()
	_test_itemstack()
	_test_ranks()
	_test_settings()
	_test_map_landmarks()
	_test_boss_arena_exits()
	await _test_the_finale_sends_you_home()
	await _test_a_pet_says_how_to_summon_it()
	_test_staff_panel()
	_test_collision_contract()
	_test_pet_shots_reach()
	_test_script_references()
	_test_element_enum_order()
	_test_spawn_ordering()
	_test_await_does_not_lose_work()
	_test_helper_scripts_ascii()
	_test_art_folders_are_licensed()
	_test_third_party_licences()
	_test_audio_paths()
	await _test_every_portal_makes_a_sound()
	_test_the_export_carries_every_price()
	_test_chat_picture_sweep()
	_test_chat_deletions_reach_the_client()
	_test_security_policy()
	_test_skills_are_not_pushed()
	_test_god_mode_earns_nothing()
	_test_teleport_is_wired()
	_test_players_menu_and_pvp_are_honest()
	_test_death_reaches_the_server()
	_test_world_status_is_shown()
	_test_timestamps_are_the_servers()
	_test_the_calendar()
	_test_board_says_what_it_is_made_of()
	_test_the_guild_tag_is_drawn_everywhere()
	_test_panels_are_windows()
	_test_unauthorized_is_answered()
	_test_the_client_says_which_build_it_is()
	_test_login_states_are_distinct()
	_test_no_import_cache_references()
	_test_every_font_draws_without_the_os()
	_test_every_ui_character_is_in_the_font()
	_test_a_save_from_outside_the_tree()
	_test_no_unused_parameters()
	_test_floor_coverage()
	_test_frame_budget()
	_test_no_black_underlay()
	_test_only_levelling_up_refills()
	_test_nothing_shadows_its_base_class()
	_test_nothing_shadows_its_own_members()
	_test_every_resource_reference_exists()
	_test_panels_fill_their_window()
	_test_slots_wear_the_hotbar_socket()
	_test_the_bank_reads_well()
	_test_notices_fade_and_login_is_quiet()

	# LAST, AND AWAITED. This is the one section that needs the tree to tick - it
	# waits for a real animation to finish rather than calling the handler by
	# hand. An un-awaited coroutine would return here immediately and the rest of
	# its checks would run AFTER _report() had already printed the totals, which
	# is the "section that died halfway still reports 0 failed" trap wearing a
	# different hat. Hence `await _run_all()` in _ready() as well.
	await _test_the_shopkeeper_waves_once()
	await _test_the_anvil_stands_by_the_shop()
	await _test_the_anvil_opens_the_smith()
	await _test_the_smith_tempers()
	await _test_the_smith_certifies()
	await _test_the_board_takes_gifts()
	await _test_props_block_the_player()
	await _test_a_lit_fire_opens_cooking()
	await _test_the_hotbar_holds_items()
	await _test_the_gm_panel_is_a_window()
	await _test_the_staff_desk()
	await _test_the_guild_panel_reads_well()
	await _test_trades_reach_the_right_people()
	await _test_the_trade_switch_reaches_the_game()
	await _test_a_kill_waits_for_the_servers_receipt()
	await _test_old_versions_must_update()
	await _test_no_debug_keys_the_panel_does_it()
	await _test_the_readout_counts_a_crowd()
	await _test_options_explain_themselves()
	await _test_escape_closes_every_window()
	await _test_move_players_from_the_list()
	await _test_give_and_save_history()
	await _test_monitors_and_window_modes()
	await _test_text_size_and_font()
	await _test_windows_snap_to_their_text()
	await _test_rebindable_keys()
	await _test_the_kill_record()
	_test_presence_carries_the_monsters()
	await _test_shared_monsters_lead()
	await _test_shared_monsters_follow()
	await _test_shared_monsters_handover()
	await _test_shared_monsters_targets()
	await _test_shared_monsters_pieces()
	await _test_shared_monsters_hold_the_leaders_numbers()
	_test_presence_carries_the_books()
	await _test_shared_monsters_keep_the_books()
	await _test_the_server_owns_monster_health()
	await _test_long_names_fit_their_windows()
	await _test_the_game_reports_its_errors()
	_test_combat_bounds_match_the_game()
	await _test_enemies_see_a_player_against_a_wall()
	await _test_attacks_stop_at_walls()
	_test_the_export_reads_a_mages_leash_in_the_editor()
	await _test_the_mage_spike_finds_its_mark()
	await _test_the_mage_kit()
	await _test_bullets_fly_true()
	await _test_bullets_vanish_over_the_black()
	_test_placed_nodes_are_not_drawn_from_the_origin()
	await _test_guild_chat_is_open()
	await _test_the_staff_desk_reads_trades()
	await _test_the_friends_header_reads_well()
	await _test_the_world_loads_in_the_background()
	_test_one_thread_loads_in_the_background()
	await _test_rare_loot_reads_as_rare()
	_test_a_loot_bag_is_reached_from_further()
	_test_amulets_carry_their_bonus()
	await _test_the_game_has_a_pace()
	_test_better_loot_carries_more()
	_test_bosses_hit_for_their_band()
	await _test_gear_bonuses_are_shown()
	await _test_tooltips_say_it_once()
	_test_the_sweep_wiring()
	_test_the_sweep_words()
	_test_the_browser_build()
	_test_the_windows_build()
	await _test_leaving_waits_for_the_save()
	_test_skill_xp_rounds_like_the_server()
	await _test_game_keys_are_not_menu_keys()
	_test_staff_logins_take_a_code()
	_test_chat_is_one_line_per_message()
	await _test_chat_keeps_your_place()
	await _test_chat_walk_and_talk()
	await _test_whispers_reach_you()
	_test_black_past_the_map()
	_test_signing_in_never_makes_an_account()
	_test_remember_me_means_it()
	_test_one_game_per_account()
	_test_email_prompt_can_wait()
	_test_chat_filter()
	_test_chat_safety_menu()
	_test_staff_reports_and_mutes()
	await _test_a_failed_load_is_not_an_empty_account()
	_test_character_select_has_a_way_out()
	await _test_every_area_can_be_walked()
	await _test_the_big_field()
	await _test_the_owner_stress_crowd()
	await _test_the_crowd_takes_seats()
	_test_the_big_field_is_dressed()
	await _test_the_crypt_doors()
	await _test_the_bullet_zone()
	await _test_the_bullet_zone_is_shared()
	await _test_the_field_volleys()
	await _test_the_bosses_are_seven_fights()
	await _test_bosses_scale_to_their_fight()
	_test_the_road_through_the_game()
	await _test_the_arrival_portal_closes_behind_you()
	await _test_monsters_go_out_in_a_burst()
	await _test_a_hit_flashes_the_artists_white()
	await _test_the_crypt_skeletons()
	await _test_far_enemies_sleep()
	await _test_a_big_fight_is_cheap()
	await _test_a_crowd_thinks_in_turns()
	await _test_the_crypt_crowd_is_cheap()
	await _test_a_crowd_waits_its_turn()
	_test_every_class_stands_in_front_of_a_wall()
	_test_one_characters_map_is_not_anothers_world()
	_test_a_broken_map_is_mended_once()
	_test_the_larder_loads()
	_test_monsters_drop_what_fits_them()
	_test_the_store_sells_the_larder()
	_test_the_export_carries_the_larder()
	_test_the_welcome_plays_once_a_login()
	await _test_the_credits()
	_test_a_character_can_be_deleted()
	_test_one_code_per_computer()
	_test_install_id_is_kept_and_sent()
	_test_a_window_never_outgrows_the_screen()
	await _test_banked_gold_goes_through_the_server()
	_test_the_store_sells_the_next_set()
	await _test_the_shop_buys()
	_test_the_shop_gives_the_mythics_away()
	await _test_quality_rolls()
	await _test_armour_resistance()
	await _test_stirring_lands()
	await _test_player_stats_window()
	await _test_world_events()
	await _test_event_report()
	await _test_land_report()
	await _test_the_boss_gates_lever()
	await _test_other_players_are_drawn()
	_test_other_players_move_evenly()
	await _test_other_players_attacks_are_pictures()
	await _test_other_players_attacks_switch()
	await _test_attacks_aim_with_no_cursor()
	await _test_aim_holds_still_while_walking()
	await _test_a_touch_screen_plays_the_game()
	await _test_a_phone_saves_its_battery()
	await _test_a_finger_held_uses_an_item()
	await _test_the_hotbar_grows_for_thumbs()
	await _test_windows_fit_a_thumb()
	await _test_a_phone_stays_cool_and_unburnt()
	await _test_what_you_do_is_saved_before_you_leave()
	await _test_a_phone_can_do_what_a_mouse_can()
	await _test_items_agree_with_the_server()
	_test_fights_hit_what_they_aim_at()
	await _test_other_players_aim_and_health()
	await _test_parties()
	await _test_names_open_the_player_menu()
	await _test_party_voice()
	await _test_voice_settings()
	_test_every_class_answers_its_own_attack()
	_test_presence_sends_attacks()
	await _test_levers_are_shared()
	await _test_held_keys_are_let_go()
	await _test_gifts_are_counted()
	await _test_coowners_and_their_levels()
	await _test_economy_rules_on_the_client()
	await _test_the_gm_panel_economy_tab()
	await _test_the_gm_panel_health_tab()
	await _test_the_damage_meter()
	await _test_the_fight_log()
	await _test_damage_taken()
	await _test_monsters_fire_their_element()
	await _test_what_hit_me()
	_test_field_effects()
	await _test_founding_a_guild_shows_what_it_cost()
	_test_a_request_waiting_on_you_lights_its_button()
	_test_the_login_screen_asks_without_a_login()
	_test_a_gateway_saying_no_answer_is_no_answer()
	_test_a_lost_server_is_asked_for_more_often()
	await _test_the_bag_is_the_servers()
	await _test_the_map_comes_back()
	_test_enemies_keep_their_place_in_the_ring()
	_test_a_door_is_quick()
	_test_the_emoji_font_is_chat_sized()
	await _test_connections_are_kept_open()
	await _test_token_lifecycle()
	_test_the_powers_panel_closes()
	_test_the_powers_read_in_words()
	_test_the_staff_windows_share_one_look()
	await _test_players_right_click_menu()
	_test_the_stats_window_reads_cleanly()
	await _test_bank_buttons_and_the_cooking_window()
	await _test_the_fire_shows_the_fish_it_cooks()
	await _test_the_cooking_window_cooks_meals()
	await _test_a_meal_buff_works_while_it_lasts()
	await _test_the_catch_names_its_bait()
	await _test_a_tooltip_says_what_food_is_for()
	_test_the_healer_aims_from_its_middle()
	await _test_monsters_show_who_they_are_after()
	_test_how_far_they_reach()
	await _test_monsters_notice_close_and_chase_far()
	await _test_monsters_walk_in_between_attacks()
	_test_the_rings_have_switches()
	_test_the_mage_has_an_off_hand()
	await _test_the_tank_aura_burns()
	_test_every_area_floor_is_under_its_floor_effects()
	await _test_the_mage_spell_effects()
	await _test_the_healer_orbs()
	await _test_the_warrior_blows()
	await _test_the_healer_aura()
	_test_the_tank_loop_takes_every_step()
	await _test_the_first_five_minutes()
	_test_the_game_says_its_version()
	await _test_the_mythic_weapons()
	await _test_the_meteor_pulls()
	await _test_the_axe_rolls()
	await _test_the_rare_roll_switch()
	await _test_the_item_menu()
	await _test_the_gm_panel_sets_a_level()
	await _test_the_gm_panel_sets_skills()
	await _test_mythic_drops()


# =============================================================================
# CONFIGURE BEFORE add_child(), or the profile multiplies nothing
# =============================================================================
# add_child() is what runs _ready(). bossprojectile.gd's _ready() calls
# _apply_element_profile(), and that function MULTIPLIES what the caller set:
#
#     telegraph_seconds = telegraph_seconds * p["telegraph"]
#     damage            = damage * p["damage"]
#     scale            *= p["size"]
#
# Set those AFTER add_child and two things happen, neither of them loud: the
# profile scaled the scene's defaults instead of your values, and your
# assignment then flattened the result. The thing spawns wearing its element's
# ART and none of its behaviour.
#
# THIS IS NOT HYPOTHETICAL. bossstalker._drop_pillar() did exactly that, and
# every pillar in a stalker's trail telegraphed in 0.50s and hit for 22 whether
# it was lightning or earth, while the boss's own cast pillars - spawned in the
# right order - varied 0.25s to 0.68s and 19 to 28. It was invisible because a
# flat number is not a wrong number, it is just not an elemental one.
#
# The same trap has a second face, recorded in bossenemy.gd: an assignment onto
# a property the scene does not have RAISES, and every statement below it in the
# function silently never runs. That is why the correct sites guard with
# `if "x" in node` before setting anything they do not own.
#
# So this reads the source of every spawn site and asserts the order. It is a
# text check on purpose - the failure it guards has no runtime symptom to assert
# against, which is the entire reason it survived as long as it did.
