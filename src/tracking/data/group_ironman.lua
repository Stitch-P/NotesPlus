-- Group Ironman: the Journey Tiers and their tasks, from the game's achievement data.
-- Each task: { id, name, flag, descriptions } where flag is the variable set once the group has done it, and
-- descriptions are by group size (2 to 5 players; [0] is the general wording). Tier lists leave out the tier before.
local TIERS = {
    { id = 3534, name = "Journey Tier 0", sprite = 33651, description = "Complete the listed achievements to gain access to Group Ironman Storage.", tasks = {
        { 3535, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_0", { [0] = "Reach a group total level of 40 x group size.", [2] = "Achieve 80 total level across the group.", [3] = "Achieve 120 total level across the group.", [4] = "Achieve 160 total level across the group.", [5] = "Achieve 200 total level across the group." } },
        { 3536, "Cooks assistant", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_COOKS_ASSISTANT", { [0] = "At least one player must complete the quest 'Cooks assistant'." } },
        { 3537, "Collect Ironman Armour", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_COLLECT_ARMOUR", { [0] = "At least one player must have collected a set of ironman armour from the Iron Enclave." } },
    } },
    { id = 3538, name = "Journey Tier 1", sprite = 34496, description = "Complete the listed achievements.", tasks = {
        { 3539, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_1", { [0] = "Reach a group total level of 50 x group size.", [2] = "Achieve 100 total level across the group.", [3] = "Achieve 150 total level across the group.", [4] = "Achieve 200 total level across the group.", [5] = "Achieve 250 total level across the group." } },
        { 3540, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_1", { [0] = "Reach a group total Quest Points of 5 x group size.", [2] = "Achieve 10 total Quest Points across the group.", [3] = "Achieve 15 total Quest Points across the group.", [4] = "Achieve 20 total Quest Points across the group.", [5] = "Achieve 25 total Quest Points across the group." } },
        { 3541, "Restless ghost", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_RESTLESS_GHOST", { [0] = "At least one player must complete the quest 'Restless ghost'" } },
        { 3542, "The Scourge of Misthalin", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_SCOURGE", { [0] = "At least one player must complete the achievement 'The Scourge of Misthalin'" } },
        { 3543, "The Provider of Misthalin", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PROVIDER", { [0] = "At least one player must complete the achievement 'The Provider of Misthalin'" } },
    } },
    { id = 3544, name = "Journey Tier 2", sprite = 34497, description = "Complete the listed achievements.", tasks = {
        { 3545, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_2", { [0] = "Reach a group total level of 200 x group size.", [2] = "Achieve 400 total level across the group.", [3] = "Achieve 600 total level across the group.", [4] = "Achieve 800 total level across the group.", [5] = "Achieve 1,000 total level across the group." } },
        { 3546, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_2", { [0] = "Reach a group total Quest Points of 20 x group size.", [2] = "Achieve 40 total Quest Points across the group.", [3] = "Achieve 60 total Quest Points across the group.", [4] = "Achieve 80 total Quest Points across the group.", [5] = "Achieve 100 total Quest Points across the group." } },
        { 3547, "Priest in Peril", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PRIEST_IN_PERIL", { [0] = "At least one player must complete the quest 'Priest in Peril'" } },
        { 3548, "Slayer 10", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_SLAYER_10", { [0] = "At least one player must complete the achievement 'Slayer 10'" } },
        { 3549, "Lumbridge Set Tasks - Easy", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_LUMBRIDGE_EASY", { [0] = "At least one player must complete the achievement 'Lumbridge Set Tasks - Easy'" } },
    } },
    { id = 3550, name = "Journey Tier 3", sprite = 34498, description = "Complete the listed achievements.", tasks = {
        { 3551, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_3", { [0] = "Reach a group total level of 500 x group size.", [2] = "Achieve 1,000 total level across the group.", [3] = "Achieve 1,500 total level across the group.", [4] = "Achieve 2,000 total level across the group.", [5] = "Achieve 2,500 total level across the group." } },
        { 3552, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_3", { [0] = "Reach a group total Quest Points of 40 x group size.", [2] = "Achieve 80 total Quest Points across the group.", [3] = "Achieve 120 total Quest Points across the group.", [4] = "Achieve 160 total Quest Points across the group.", [5] = "Achieve 200 total Quest Points across the group." } },
        { 3553, "Icthlarin's Little Helper", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_ICS_LITTLE_HELPER", { [0] = "At least one player must complete the quest 'Icthlarin's Little Helper'" } },
        { 3554, "Dragon Slayer", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_DRAGON_SLAYER", { [0] = "At least one player must complete the quest 'Dragon Slayer'" } },
        { 3555, "Wonderful Walls", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_FORT_WALLS", { [0] = "At least one player must complete the achievement 'Wonderful Walls'" } },
        { 3556, "Novice Provisions Officer", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PROVISIONS_1", { [0] = "At least one player must complete the achievement 'Novice Provisions Officer'" } },
    } },
    { id = 3557, name = "Journey Tier 4", sprite = 34499, description = "Complete the listed achievements.", tasks = {
        { 3558, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_4", { [0] = "Reach a group total level of 1,000 x group size.", [2] = "Achieve 2,000 total level across the group.", [3] = "Achieve 3,000 total level across the group.", [4] = "Achieve 4,000 total level across the group.", [5] = "Achieve 5,000 total level across the group." } },
        { 3559, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_4", { [0] = "Reach a group total Quest Points of 80 x group size.", [2] = "Achieve 160 total Quest Points across the group.", [3] = "Achieve 240 total Quest Points across the group.", [4] = "Achieve 320 total Quest Points across the group.", [5] = "Achieve 400 total Quest Points across the group." } },
        { 3560, "One Small Favour", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_ONE_SMALL_FAVOUR", { [0] = "At least one player must complete the quest 'One Small Favour'" } },
        { 3561, "King Black Dragon", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_BSLAY_KBD", { [0] = "At least one player must complete the achievement 'King Black Dragon'" } },
        { 3562, "Ardougne Set Tasks - Easy", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_ARDOUGNE_EASY", { [0] = "At least one player must complete the achievement 'Ardougne Set Tasks - Easy'" } },
        { 3563, "Beginner Provisions Officer", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PROVISIONS_2", { [0] = "At least one player must complete the achievement 'Beginner Provisions Officer'" } },
    } },
    { id = 3564, name = "Journey Tier 5", sprite = 34500, description = "Complete the listed achievements.", tasks = {
        { 3565, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_5", { [0] = "Reach a group total level of 1,400 x group size.", [2] = "Achieve 2,800 total level across the group.", [3] = "Achieve 4,200 total level across the group.", [4] = "Achieve 5,600 total level across the group.", [5] = "Achieve 7,000 total level across the group." } },
        { 3566, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_5", { [0] = "Reach a group total Quest Points of 120 x group size.", [2] = "Achieve 240 total Quest Points across the group.", [3] = "Achieve 360 total Quest Points across the group.", [4] = "Achieve 480 total Quest Points across the group.", [5] = "Achieve 600 total Quest Points across the group." } },
        { 3567, "Desert Treasure", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_DESERT_TREASURE", { [0] = "At least one player must complete the quest 'Desert Treasure'" } },
        { 3568, "Kalphite Queen", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_BSLAY_KALPHITE_QUEEN", { [0] = "At least one player must complete the achievement 'Kalphite Queen'" } },
        { 3569, "Morytania Set Tasks - Easy", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_MORYTANIA_EASY", { [0] = "At least one player must complete the achievement 'Morytania Set Tasks - Easy'" } },
        { 3570, "Competent Provisions Officer", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PROVISIONS_3", { [0] = "At least one player must complete the achievement 'Competent Provisions Officer'" } },
    } },
    { id = 3571, name = "Journey Tier 6", sprite = 34501, description = "Complete the listed achievements.", tasks = {
        { 3572, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_6", { [0] = "Reach a group total level of 1,800 x group size.", [2] = "Achieve 3,600 total level across the group.", [3] = "Achieve 5,400 total level across the group.", [4] = "Achieve 7,200 total level across the group.", [5] = "Achieve 9,000 total level across the group." } },
        { 3573, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_6", { [0] = "Reach a group total Quest Points of 160 x group size.", [2] = "Achieve 320 total Quest Points across the group.", [3] = "Achieve 480 total Quest Points across the group.", [4] = "Achieve 640 total Quest Points across the group.", [5] = "Achieve 800 total Quest Points across the group." } },
        { 3574, "The Path of Glouphrie", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PATH_OF_GLOUPHRIE", { [0] = "At least one player must complete the quest 'The Path of Glouphrie'" } },
        { 3575, "God Wars Dungeon", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_GODWARS_KILL_EACH_ONCE", { [0] = "At least one player must complete the achievement 'God Wars Dungeon'" } },
        { 3576, "Desert Set Tasks - Medium", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_DESERT_MEDIUM", { [0] = "At least one player must complete the achievement 'Desert Set Tasks - Medium'" } },
        { 3577, "Proficient Provisions Officer", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PROVISIONS_4", { [0] = "At least one player must complete the achievement 'Proficient Provisions Officer'" } },
    } },
    { id = 3578, name = "Journey Tier 7", sprite = 34502, description = "Complete the listed achievements.", tasks = {
        { 3579, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_7", { [0] = "Reach a group total level of 2,000 x group size.", [2] = "Achieve 4,000 total level across the group.", [3] = "Achieve 6,000 total level across the group.", [4] = "Achieve 8,000 total level across the group.", [5] = "Achieve 10,000 total level across the group." } },
        { 3580, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_7", { [0] = "Reach a group total Quest Points of 200 x group size.", [2] = "Achieve 400 total Quest Points across the group.", [3] = "Achieve 600 total Quest Points across the group.", [4] = "Achieve 800 total Quest Points across the group.", [5] = "Achieve 1,000 total Quest Points across the group." } },
        { 3581, "Recipe for Disaster", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_RECIPE_FOR_DISASTER", { [0] = "At least one player must complete the quest 'Recipe for Disaster'" } },
        { 3582, "Seeing Lava", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_SEEING_LAVA", { [0] = "At least one player must complete the achievement 'Seeing Lava'" } },
        { 3583, "Falador Set Tasks - Hard", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_FALADOR_HARD", { [0] = "At least one player must complete the achievement 'Falador Set Tasks - Hard'" } },
    } },
    { id = 3584, name = "Journey Tier 8", sprite = 34503, description = "Complete the listed achievements.", tasks = {
        { 3585, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_8", { [0] = "Reach a group total level of 2,150 x group size.", [2] = "Achieve 4,300 total level across the group.", [3] = "Achieve 6,450 total level across the group.", [4] = "Achieve 8,600 total level across the group.", [5] = "Achieve 10,750 total level across the group." } },
        { 3586, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_8", { [0] = "Reach a group total Quest Points of 250 x group size.", [2] = "Achieve 500 total Quest Points across the group.", [3] = "Achieve 750 total Quest Points across the group.", [4] = "Achieve 1,000 total Quest Points across the group.", [5] = "Achieve 1,250 total Quest Points across the group." } },
        { 3587, "Do No Evil", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_DO_NO_EVIL", { [0] = "At least one player must complete the quest 'Do No Evil'" } },
        { 3588, "Heart of Gielinor", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_GWD2_KILL_EACH_ONCE", { [0] = "At least one player must complete the achievement 'Heart of Gielinor'" } },
        { 3589, "Daemonheim Set Tasks - Hard", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_DAEMONHEIM_HARD", { [0] = "At least one player must complete the achievement 'Daemonheim Set Tasks - Hard'" } },
        { 3590, "Expert Provisions Officer", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PROVISIONS_5", { [0] = "At least one player must complete the achievement 'Expert Provisions Officer'" } },
    } },
    { id = 3591, name = "Journey Tier 9", sprite = 34504, description = "Complete the listed achievements.", tasks = {
        { 3592, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_9", { [0] = "Reach a group total level of 2,300 x group size.", [2] = "Achieve 4,600 total level across the group.", [3] = "Achieve 6,900 total level across the group.", [4] = "Achieve 9,200 total level across the group.", [5] = "Achieve 11,500 total level across the group." } },
        { 3593, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_9", { [0] = "Reach a group total Quest Points of 300 x group size.", [2] = "Achieve 600 total Quest Points across the group.", [3] = "Achieve 900 total Quest Points across the group.", [4] = "Achieve 1,200 total Quest Points across the group.", [5] = "Achieve 1,500 total Quest Points across the group." } },
        { 3594, "Ritual of the Mahjarrat", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_RITUAL_OF_THE_MAHJARRAT", { [0] = "At least one player must complete the quest 'Ritual of the Mahjarrat'" } },
        { 3595, "Araxxi", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_BSLAY_ARAXXI", { [0] = "At least one player must complete the achievement 'Araxxi'" } },
        { 3596, "Tirannwn Set Tasks - Hard", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_TIRANNWN_HARD", { [0] = "At least one player must complete the achievement 'Tirannwn Set Tasks - Hard'" } },
    } },
    { id = 3597, name = "Journey Tier 10", sprite = 34505, description = "Complete the listed achievements.", tasks = {
        { 3598, "Total level", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_LEVEL_TIER_10", { [0] = "Reach a group total level of 2,500 x group size.", [2] = "Achieve 5,000 total level across the group.", [3] = "Achieve 7,500 total level across the group.", [4] = "Achieve 10,000 total level across the group.", [5] = "Achieve 12,500 total level across the group." } },
        { 3599, "Total Quest Points", "GROUP_IRONMAN_ACHIEVEMENT_TOTAL_PLAYER_CACHE_TOTAL_QUESTPOINTS_TIER_10", { [0] = "Reach a group total Quest Points of 375 x group size.", [2] = "Achieve 750 total Quest Points across the group.", [3] = "Achieve 1,125 total Quest Points across the group.", [4] = "Achieve 1,500 total Quest Points across the group.", [5] = "Achieve 1,875 total Quest Points across the group." } },
        { 3600, "Sliske's Endgame", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_SLISKES_ENDGAME", { [0] = "At least one player must complete the quest 'Sliske's Endgame'" } },
        { 3601, "Telos If You're Angry II", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_TELOS_ENRAGE_2", { [0] = "At least one player must complete the achievement 'Telos If You're Angry II'" } },
        { 3602, "Fremennik Set Tasks - Elite", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_FREMENNIK_ELITE", { [0] = "At least one player must complete the achievement 'Fremennik Set Tasks - Elite'" } },
        { 3603, "Master Provisions Officer", "GROUP_IRONMAN_ACHIEVEMENT_SOLO_PLAYER_CACHE_PROVISIONS_6", { [0] = "At least one player must complete the achievement 'Master Provisions Officer'" } },
    } },
}

return { TIERS = TIERS }
