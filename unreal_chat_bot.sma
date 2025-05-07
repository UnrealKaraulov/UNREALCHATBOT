#include <amxmodx>

#include <amxmisc>

#include <easy_http>

#define _easy_cfg_internal
#include <easy_cfg>

#pragma ctrlchar '\'
#pragma dynamic 262144

new const PLUGIN_NAME[] = "UNREAL CHAT BOT";
new const PLUGIN_VERSION[] = "1.00";
new const PLUGIN_AUTHOR[] = "Karaulov";
new const PLUGIN_SITE[] = "https://dev-cs.ru";

#define API_KEY_MAX 512
#define SYS_PROMT_MAX 4077
#define MAX_THREADS 40

new g_sApiUrl[API_KEY_MAX] = "https://api.mistral.ai/v1/chat/completions"
new g_sApiKey[API_KEY_MAX] = "Bearer NpvcgZk0pFTLaTXXXXXXXXXXXXXX";
new g_sChatBotModel[API_KEY_MAX] = "mistral-large-latest";
new g_sChatBotPrefix[API_KEY_MAX] = "^4[GPT]: ";
new g_sChatBotPrefixFixed[API_KEY_MAX];
new g_sJoinMessage[API_KEY_MAX] = "Привет, я ```[username]```! Приветствуй меня на сервере!";
new g_sDelayMessage[API_KEY_MAX] = "Подожди немного, я не занят!";

new bool:g_bSwithAPIonError = false;
new g_iApiCount = 1;
new g_iCurrentApiId = 1;
new g_iApiMultiThreadCount = 1;
new g_iMaxHistory = 40;

new Float:g_fThreadsTimes[MAX_THREADS] = {-999.0,...};

new g_sSystemDirectives[SYS_PROMT_MAX] = "Language: Russian. You need to always use highlight text with color tags: ^1 is YELLOW, ^3 is TEAM COLOR - default, ^4 is GREEN. Team colors ^5 is RED ^6 is GREY ^7 is BLUE and setup at message start. Your name is 'UnrealBot'. Answer more than 4077 characters – make it shorter. Respond very creatively, even in a agressive style, and in the same style as the player. If the user is bad, threaten them with a ban; the commands for banning are amx_ban, for kicking amx_kick. Player data: on the server, they are assigned number [userid], their nickname is [username], their IP address is [ip], and their SteamID is [steamid]. Hide a couple of digits in the IP and SteamID if you write them. Язык ответов - русский.";

new g_sTempBigBuffer[SYS_PROMT_MAX] = {EOS};

new EzJSON: g_playerHistory[MAX_PLAYERS + 1] = {
	EzInvalid_JSON,
	...
};
new Float:g_fLastTimeUsed[MAX_PLAYERS + 1] = {-999.0,...};
new Float:g_fDelayTime = 2.5;
new g_iSayText = 0;
new g_iPrefixUsage = 1;

new bool:g_bCheckForHltv = true;

new bool:g_bCheckForBots = true;


public plugin_init() {
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	create_cvar("unreal_chatbot", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY);

	register_clcmd("say_team", "handle_gpt_command");
	register_clcmd("say", "handle_gpt_command");

	g_iSayText = get_user_msgid("SayText");

	new tmp_cfgdir[512];
	cfg_set_path("plugins/unreal_chatbot.cfg", -1);
	cfg_get_path(tmp_cfgdir, charsmax(tmp_cfgdir));
	trim_to_dir(tmp_cfgdir);

	if (!dir_exists(tmp_cfgdir)) {
		log_amx("Warning config dir not found: %s", tmp_cfgdir);
		if (mkdir(tmp_cfgdir) < 0) {
			log_error(AMX_ERR_NOTFOUND, "Can't create %s dir", tmp_cfgdir);
			set_fail_state("Fail while create %s dir", tmp_cfgdir);
			return;
		} else {
			log_amx("Config dir %s created!", tmp_cfgdir);
		}
	}

	for (new i = 0; i <= MAX_PLAYERS; i++) {
		g_playerHistory[i] = ezjson_init_array();
		g_fLastTimeUsed[i] = 0.0;
	}
	for(new i = 0; i < MAX_THREADS; i++)
	{
		g_fThreadsTimes[i] = -1.0;
	}
	print_unrealchat_cfg();
}

public plugin_end() {
	for (new i = 0; i <= MAX_PLAYERS; i++) {
		if (g_playerHistory[i] != EzInvalid_JSON) {
			ezjson_free(g_playerHistory[i]);
			g_playerHistory[i] = EzInvalid_JSON;
		}
	}
}

public client_putinserver(id) {
	remove_task(id);
	set_task(3.0,"send_putin_server",id);
	if (get_gametime() - g_fLastTimeUsed[id] < g_fDelayTime) {
		return;
	}
	
	g_fLastTimeUsed[id] = get_gametime() - 3.1;
}

public print_unrealchat_cfg()
{
	cfg_read_bool("general", "change_api_when_error", g_bSwithAPIonError, g_bSwithAPIonError);
	cfg_read_bool("general", "skip_hltv", g_bCheckForHltv, g_bCheckForHltv);
	cfg_read_bool("general", "skip_bots", g_bCheckForBots, g_bCheckForBots);
	cfg_read_int("general", "api_total_count", g_iApiCount, g_iApiCount);
	cfg_read_int("general", "api_id", g_iCurrentApiId, g_iCurrentApiId);
	cfg_read_str("general", "delay_message", g_sDelayMessage, g_sDelayMessage, charsmax(g_sDelayMessage));
	cfg_read_str("general", "join_message", g_sJoinMessage, g_sJoinMessage, charsmax(g_sJoinMessage));
	cfg_read_int("general", "prefix_mode", g_iPrefixUsage, g_iPrefixUsage);
	
	new tmpApiID[64];
	formatex(tmpApiID,charsmax(tmpApiID),"API_%d",g_iCurrentApiId);
	
	cfg_read_str(tmpApiID, "bot_chatprefix", g_sChatBotPrefix, g_sChatBotPrefix, charsmax(g_sChatBotPrefix));
	cfg_read_flt(tmpApiID, "flood_delay", g_fDelayTime, g_fDelayTime);
	cfg_read_str(tmpApiID, "api_system_promt", g_sSystemDirectives, g_sSystemDirectives, charsmax(g_sSystemDirectives));
	cfg_read_str(tmpApiID, "api_chatbot_model", g_sChatBotModel, g_sChatBotModel, charsmax(g_sChatBotModel));
	cfg_read_str(tmpApiID, "api_key", g_sApiKey, g_sApiKey, charsmax(g_sApiKey));
	cfg_read_str(tmpApiID, "api_url", g_sApiUrl, g_sApiUrl, charsmax(g_sApiUrl));
	cfg_read_int(tmpApiID, "api_max_threads", g_iApiMultiThreadCount, g_iApiMultiThreadCount);
	cfg_read_int(tmpApiID, "api_history_count", g_iMaxHistory, g_iMaxHistory);
	
	
	copy(g_sChatBotPrefixFixed,charsmax(g_sChatBotPrefixFixed),g_sChatBotPrefix)
	preparing_message(g_sChatBotPrefixFixed,charsmax(g_sChatBotPrefixFixed));
	
	
	
	log_amx("UnrealChatBot configuration for %d API", g_iCurrentApiId);
	log_amx("System text: %192s", g_sSystemDirectives);

	new tmpApiKey[API_KEY_MAX];
	copy(tmpApiKey, charsmax(tmpApiKey), g_sApiUrl);

	for (new i = 20; i < 30; i++) 
	{
		tmpApiKey[i] = 'X';
	}

	log_amx("\nApi url: %s", tmpApiKey);
	
	copy(tmpApiKey, charsmax(tmpApiKey), g_sApiKey);
	
	for (new i = 28; i < 38; i++) 
	{
		tmpApiKey[i] = 'X';
	}
	
	for (new i = 48; i < 58; i++) 
	{
		tmpApiKey[i] = 'X';
	}
	
	log_amx("Api key: %s", tmpApiKey);

	log_amx("Model: %s", g_sChatBotModel);
	
	log_amx("Bot prefix: %s", g_sChatBotPrefix);
	
	log_amx("Delay between cmds: %f", g_fDelayTime);
	
	log_amx("Max threads: %i", g_iApiMultiThreadCount);
}

public send_putin_server(id){
	if (g_playerHistory[id] != EzInvalid_JSON) {
		ezjson_array_clear(g_playerHistory[id]);
	} else {
		g_playerHistory[id] = ezjson_init_array();
	}
	
	new userid[16];
	formatex(userid, charsmax(userid), "%i", get_user_userid(id));
	new username[33];
	get_user_name(id, username, charsmax(username));
	new userip[16];
	get_user_ip(id, userip, charsmax(userip), true);
	new userauth[64];
	get_user_authid(id, userauth, charsmax(userauth));

	copy(g_sTempBigBuffer,charsmax(g_sTempBigBuffer), g_sSystemDirectives);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[userid]",userid);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[username]",username);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[ip]",userip);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[steamid]",userauth);
	preparing_message(g_sTempBigBuffer, charsmax(g_sTempBigBuffer));

	new EzJSON: msg = ezjson_init_object();
	ezjson_object_set_string(msg, "role", "system");
	ezjson_object_set_string(msg, "content", g_sTempBigBuffer);
	
	copy(g_sTempBigBuffer,charsmax(g_sTempBigBuffer), g_sJoinMessage);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[userid]",userid);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[username]",username);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[ip]",userip);
	replace_all(g_sTempBigBuffer,charsmax(g_sTempBigBuffer),"[steamid]",userauth);
	preparing_message(g_sTempBigBuffer, charsmax(g_sTempBigBuffer));

	ezjson_array_append_value(g_playerHistory[id], msg);
	ezjson_free(msg);

	if (get_gametime() - g_fLastTimeUsed[id] < g_fDelayTime) {
		return;
	}

	g_fLastTimeUsed[id] = get_gametime();
	add_user_message(id, g_sTempBigBuffer);
}

public handle_gpt_command(id) 
{
	new message[512];
	read_args(message, charsmax(message));
	remove_quotes(message);
	trim(message);
	if (strlen(message) == 0 || containi(message, "/gpt") < 0 || containi(message, "/gpt") > 1) {
		return PLUGIN_CONTINUE;
	}

	if (floatabs(get_gametime() - g_fLastTimeUsed[id]) < g_fDelayTime) {
		client_print(id, print_chat, "\x04%s \x01 %s", g_sChatBotPrefixFixed, g_sDelayMessage);
		return PLUGIN_HANDLED;
	}
	
	if (update_threads() > g_iApiMultiThreadCount)
	{
		client_print(id, print_chat, "\x04%s \x01 [THREADS] %s", g_sChatBotPrefixFixed, g_sDelayMessage);
		return PLUGIN_HANDLED;
	}

	replace_all(message, charsmax(message), "/gpt", "");
	
	if (strlen(message) == 0) {
		client_print(id, print_chat, "[GPT] Введите сообщение после /gpt");
		return PLUGIN_HANDLED;
	}
	client_print(id, print_console, "say /gpt %s", message);
	
	add_user_message(id, message);
	return PLUGIN_HANDLED;
}

public add_assistant_message(id, const message[]) {
	if (g_playerHistory[id] == EzInvalid_JSON) {
		g_playerHistory[id] = ezjson_init_array();
	}

	new EzJSON: msg = ezjson_init_object();
	ezjson_object_set_string(msg, "role", "assistant");
	ezjson_object_set_string(msg, "content", message);

	ezjson_array_append_value(g_playerHistory[id], msg);
	ezjson_free(msg);

	trim_history(id);
}
/*
write_debug_log(const filepath[], const message[]) 
{
	new file = fopen(filepath, "a");
	if(file) 
	{
		new timestamp[32];
		get_time("%Y-%m-%d %H:%M:%S", timestamp, charsmax(timestamp));
		
		fprintf(file, "[%s] %s\n", timestamp, message);
		fclose(file);
	}
}

dump_request_to_file(id, const EzJSON:request) 
{
	new filename[64];
	formatex(filename, charsmax(filename), "requests.log");
	
	if(request == EzInvalid_JSON)
	{	
		write_debug_log(filename, "EzInvalid_JSON");
		return;
	}
	new js_string[4000];
	ezjson_serial_to_string(request, js_string, charsmax(js_string), true);
	
	write_debug_log(filename, js_string);
}

dump_response_to_file(id, const response[]) 
{
	new filename[64];
	formatex(filename, charsmax(filename), "addons/amxmodx/logs/responses.log");
	
	write_debug_log(filename, response);
}
*/

public add_user_message(id, const message[]) {

	if (update_threads() > g_iApiMultiThreadCount)
	{
		return;
	}

	if (g_playerHistory[id] == EzInvalid_JSON) {
		g_playerHistory[id] = ezjson_init_array();
	}

	new EzJSON: msg = ezjson_init_object();
	ezjson_object_set_string(msg, "role", "user");
	ezjson_object_set_string(msg, "content", message);

	ezjson_array_append_value(g_playerHistory[id], msg);
	ezjson_free(msg);

	trim_history(id);

	if (strlen(g_sApiKey) == 0) {
		log_amx("%s Error! No API key entered", g_sChatBotPrefixFixed)
		client_print(id, print_chat, "%s \x01 Error! No API key!", g_sChatBotPrefixFixed);
		return;
	}

	new EzHttpOptions: options = ezhttp_create_options();

	ezhttp_option_set_header(options, "Authorization", g_sApiKey);
	ezhttp_option_set_header(options, "Content-Type", "application/json; charset=utf-8");
	ezhttp_option_set_header(options, "HTTP-Referer", PLUGIN_SITE);
	ezhttp_option_set_header(options, "X-Title", PLUGIN_NAME);

	ezhttp_option_set_connect_timeout(options, 20000);
	ezhttp_option_set_timeout(options, 20000);

	new EzJSON: request_body = ezjson_init_object();
	if (strlen(g_sChatBotModel) > 0)
	{
		ezjson_object_set_string(request_body, "model", g_sChatBotModel);
	}
	
	/*ezjson_object_set_real(request_body, "temperature", 1.5);
	ezjson_object_set_real(request_body, "frequency_penalty", 0.5);
	ezjson_object_set_real(request_body, "presence_penalty", 0.5);
	ezjson_object_set_real(request_body, "repetition_penalty", 0.9);
	ezjson_object_set_number(request_body, "seed", random_num(0,999999));*/

	if (g_playerHistory[id] != EzInvalid_JSON) {
		ezjson_object_set_value(request_body, "messages", g_playerHistory[id]);
	}

	ezhttp_option_set_body_from_json(options, request_body);

	// dump_request_to_file(id, request_body);

	new callback[64];
	formatex(callback, charsmax(callback), "handle_openrouter_response_%d", id);
	ezhttp_post(g_sApiUrl, callback, options);


	// для какой-то цели удаляет history_copy, по этому выше костыль для предотвращения удаления
	new EzJSON: history_copy = g_playerHistory[id];
	g_playerHistory[id] = ezjson_deep_copy(g_playerHistory[id]);
	// 
	ezjson_free(history_copy);
	ezjson_free(request_body);
	update_threads(true);
	/*get_user_name(id,callback,charsmax(callback));
	log_amx("Player %s say %s to chatbot.", callback, message);*/
}

public trim_history(id) {
	if (g_playerHistory[id] == EzInvalid_JSON) return;

	new count = ezjson_array_get_count(g_playerHistory[id]);

	while (count > g_iMaxHistory) {
		ezjson_array_remove(g_playerHistory[id], 0);
		count--;
	}
}

// Не знал как в API передать нужные мне доп параметры по этому мой фирменный костыль:
public handle_openrouter_response_0(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 0);
}
public handle_openrouter_response_1(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 1);
}
public handle_openrouter_response_2(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 2);
}
public handle_openrouter_response_3(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 3);
}
public handle_openrouter_response_4(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 4);
}
public handle_openrouter_response_5(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 5);
}
public handle_openrouter_response_6(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 6);
}
public handle_openrouter_response_7(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 7);
}
public handle_openrouter_response_8(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 8);
}
public handle_openrouter_response_9(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 9);
}
public handle_openrouter_response_10(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 10);
}
public handle_openrouter_response_11(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 11);
}
public handle_openrouter_response_12(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 12);
}
public handle_openrouter_response_13(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 13);
}
public handle_openrouter_response_14(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 14);
}
public handle_openrouter_response_15(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 15);
}
public handle_openrouter_response_16(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 16);
}
public handle_openrouter_response_17(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 17);
}
public handle_openrouter_response_18(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 18);
}
public handle_openrouter_response_19(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 19);
}
public handle_openrouter_response_20(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 20);
}
public handle_openrouter_response_21(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 21);
}
public handle_openrouter_response_22(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 22);
}
public handle_openrouter_response_23(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 23);
}
public handle_openrouter_response_24(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 24);
}
public handle_openrouter_response_25(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 25);
}
public handle_openrouter_response_26(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 26);
}
public handle_openrouter_response_27(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 27);
}
public handle_openrouter_response_28(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 28);
}
public handle_openrouter_response_29(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 29);
}
public handle_openrouter_response_30(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 30);
}
public handle_openrouter_response_31(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 31);
}
public handle_openrouter_response_32(EzHttpRequest: request_id, error) {
	handle_openrouter_response(request_id, error, 32);
}

public handle_error()
{
	for (new id = 0; id <= MAX_PLAYERS; id++) {
		if (g_playerHistory[id] != EzInvalid_JSON) {
			ezjson_free(g_playerHistory[id]);
			g_playerHistory[id] = ezjson_init_array();
		}
		remove_task(id);
		if (is_user_connected(id))
		{
			g_fLastTimeUsed[id] = get_gametime();
			set_task(3.0,"send_putin_server",id);
		}
	}
	
	if (g_bSwithAPIonError)
	{
		for (new id = 0; id <= MAX_PLAYERS; id++) {
			remove_task(id);
			if (is_user_connected(id))
			{
				g_fLastTimeUsed[id] = get_gametime();
				set_task(3.0,"send_putin_server",id);
			}
		}
		g_iCurrentApiId++;
		if (g_iCurrentApiId > g_iApiCount)
		{
			g_iCurrentApiId = 1;
		}
		
		update_threads(false,false,true);
		
		
		cfg_write_int("general", "api_id", g_iCurrentApiId);
		print_unrealchat_cfg();
	}
}

public handle_openrouter_response(EzHttpRequest: request_id, error, id) {
	static raw_response[4096];
	static message[SYS_PROMT_MAX];
	ezhttp_get_data(request_id, raw_response, charsmax(raw_response));
	//dump_response_to_file(id, raw_response);
	new bool:connect = is_user_connected(id) > 0;

	if (error != _: EZH_OK) {
		ezhttp_get_error_message(request_id, message, charsmax(message));
		
		log_amx("[api_result] error, raw response: %s", message);
		
		if(connect)
			client_print(id, print_chat, "%s \x01 Error (%d): %60s", g_sChatBotPrefixFixed, error, message);
			
		handle_error();
		return;
	}

	new http_code = ezhttp_get_http_code(request_id);
	if (http_code != 200) {
		ezhttp_get_data(request_id, raw_response, charsmax(raw_response));
		log_amx("[api_result] error, raw response: %s", raw_response);
		
		if (connect)
			client_print(id, print_chat, "%s \x01 Server error code: %d", g_sChatBotPrefixFixed, http_code);
			
		handle_error();
		return;
	}

	new EzJSON: response = ezhttp_parse_json_response(request_id);

	if (response != EzInvalid_JSON) {
		new EzJSON: choices = ezjson_object_get_value(response, "choices");
		if (choices != EzInvalid_JSON) {
			if (ezjson_is_array(choices))
			{
				new EzJSON: first_choice = ezjson_array_get_value(choices, 0);
				if (first_choice != EzInvalid_JSON) {
					new EzJSON: json_message = ezjson_object_get_value(first_choice, "message");
					if (json_message != EzInvalid_JSON) {
						ezjson_object_get_string(json_message, "content", message, charsmax(message));
						new count = ezjson_array_get_count(g_playerHistory[id]);
						preparing_message(message, charsmax(message));
						SendSplitMessage(count > 1 && connect ? id : 0, g_sChatBotPrefixFixed, message);
						
						/*if (connect){					
							get_user_name(id,raw_response,64);
							log_amx("Player %s got response %192s from chatbot.", raw_response, message);
						}*/
						
						update_threads(false,true);
				
						add_assistant_message(id, message);
						ezjson_free(json_message);
					}
					else 
					{
						new raw_response[2048];
						ezhttp_get_data(request_id, raw_response, charsmax(raw_response));
						log_amx("[api_result] json error, no messages: %s", raw_response);
						handle_error();
					}
					ezjson_free(first_choice);
				}
				else 
				{
					new raw_response[2048];
					ezhttp_get_data(request_id, raw_response, charsmax(raw_response));
					log_amx("[api_result] json error, empty choices: %s", raw_response);
					handle_error();
				}
			}
			else 
			{
				new raw_response[2048];
				ezhttp_get_data(request_id, raw_response, charsmax(raw_response));
				log_amx("[api_result] json error, invalid choices: %s", raw_response);
				handle_error();
			}
			ezjson_free(choices);
		}
		else 
		{
			new EzJSON: result = ezjson_object_get_value(response, "result");
			if (result != EzInvalid_JSON) {
				ezjson_object_get_string(result, "response", message, charsmax(message));
				new count = ezjson_array_get_count(g_playerHistory[id]);
				preparing_message(message, charsmax(message));
				SendSplitMessage(count > 1 && connect ? id : 0, g_sChatBotPrefixFixed, message);
				
				/*if (connect){					
					get_user_name(id,raw_response,64);
					log_amx("Player %s got response %192s from chatbot.", raw_response, message);
				}*/
				
				update_threads(false,true);
				
				add_assistant_message(id, message);
				ezjson_free(result);
			} 
			else 
			{
				new raw_response[2048];
				ezhttp_get_data(request_id, raw_response, charsmax(raw_response));
				log_amx("[api_result] json error, no choices/result: %s", raw_response);
				handle_error();
			}
		}
		ezjson_free(response);
	} else {
		new raw_response[2048];
		ezhttp_get_data(request_id, raw_response, charsmax(raw_response));
		log_amx("[api_result] json error, raw response: %s", raw_response);
		
		if (connect)
			client_print(id, print_chat, "%s \x01 invalid json, message: %60s", g_sChatBotPrefixFixed, raw_response);
		handle_error();
	}
}

update_threads(bool:need_add = false, bool:need_remove = false, bool:clear_all = false)
{
	new thread_count = 0;
	new Float:t = get_gametime();
	new Float:tmpMaxTime = 0.0;
	new tmpMaxId = 0;
	for(new i = 0; i < MAX_THREADS; i++)
	{
		if (clear_all)
		{
			g_fThreadsTimes[i] = -1.0;
			continue;
		}
		if (g_fThreadsTimes[i] > tmpMaxTime)
		{
			tmpMaxTime = g_fThreadsTimes[i];
			tmpMaxId = i;
		}
		if (g_fThreadsTimes[i] > 0.01 && floatabs(t - g_fThreadsTimes[i]) < 20.0)
		{
			thread_count++;
		}
		else 
		{
			if (need_add)
			{
				need_add = false;
				g_fThreadsTimes[i] = t;
				thread_count++;
			}
			else 
			{
				need_remove = false;
				g_fThreadsTimes[i] = -1.0;
			}
		}
	}
	
	if (need_remove)
	{
		g_fThreadsTimes[tmpMaxId] = -1.0;
	}
	
	return thread_count;
}

stock SendSplitMessage(id, const prefix[], const message[]) {
	new msg_len = strlen(message);
	new prefix_len = strlen(prefix);
	new max_part_len = 192 - prefix_len;
	new sender = id;
	new cur_pos = 0;
	static tempChar = 0;
	static part[192];
	static dst_msg[192];
	static target_prefix[192];
	new last_color = EOS;
	new parts = 0;

	max_part_len -= 3; //color size + EOS + base color \x01

	while (cur_pos < msg_len) {
		new part_len = 0;

		while (cur_pos < msg_len && part_len <= max_part_len) {
			// size of on UTF8 char ? EN/RU/etc
			new char_bytes = 1;
			if (message[cur_pos] & 0x80) 
			{
				if ((message[cur_pos] & 0xE0) == 0xC0) char_bytes = 2;
				else if ((message[cur_pos] & 0xF0) == 0xE0) char_bytes = 3;
				else if ((message[cur_pos] & 0xF8) == 0xF0) char_bytes = 4;
			}
			
			if (part_len + char_bytes >= max_part_len) 
			{
				break;
			}
			
			// save last color her?e?
			if (cur_pos + 1 < msg_len)
			{
				tempChar = message[cur_pos];
				if (tempChar == '^')
				{
					tempChar = message[cur_pos + 1];
						
					if (tempChar == '5')
					{
						sender = print_team_red;
						cur_pos+=2;
						continue;
					}
					else if (tempChar == '6')
					{
						sender = print_team_grey;
						cur_pos+=2;
						continue;
					}
					else if (tempChar == '7')
					{
						sender = print_team_blue;
						cur_pos+=2;
						continue;
					}
				}
			}
			
			for (new i = 0; i < char_bytes && cur_pos < msg_len; i++) 
			{
				tempChar = message[cur_pos++];
				
				if (tempChar == '\t')
					tempChar = ' ';
				
				if (tempChar == 10 || tempChar == 13)
				{
					continue;
				}
				
				part[part_len++] = tempChar;
			}
		}
		
		parts++;
		part[part_len] = EOS;

		if (part_len > 0) 
		{
			if (g_iPrefixUsage == 1 || (g_iPrefixUsage == 2 && parts == 1))
			{
				if ((g_iPrefixUsage == 2 && parts == 1))
				{
					prefix_len -= strlen(prefix);
				}
				formatex(target_prefix,charsmax(target_prefix),"%s", prefix);
				target_prefix[strlen(target_prefix)] = last_color;
				target_prefix[strlen(target_prefix)+1] = EOS;
			}
			else 
			{
				target_prefix[0] = last_color;
				target_prefix[1] = EOS;
			}
			
			formatex(dst_msg, charsmax(dst_msg), "%s%s", target_prefix, part);
			write_client_message(id, sender, dst_msg);
			
			for(new i = part_len - 1; i > 0;i--)
			{
				new tempChar = part[i];
				if (tempChar == 1 || tempChar == 4 ||
					tempChar == 3) {
					last_color = tempChar;
					break;
				}
			}
		}
	}
}

stock write_client_message(const index, const sender, const message[], any: ...) {
	static buffer[256];

	message_begin(MSG_ONE, g_iSayText, _, index);
	write_byte(sender);
	new numArguments = numargs();
	if (numArguments == 2) {
		formatex(buffer, charsmax(buffer), "%192s", message);
	} else {
		vformat(buffer, charsmax(buffer), message, 3);
	}
	buffer[191] = EOS;
	write_string(buffer);
	message_end();
}

stock trim_to_dir(path[]) {
	new len = strlen(path);
	len--;
	for (; len >= 0; len--) {
		if (path[len] == '/' || path[len] == '\\') {
			path[len] = EOS;
			break;
		}
	}
}

stock preparing_message(str[], len)
{
	replace_all(str, len, "^1", "\x01");
	replace_all(str, len, "^2", "\x02");
	replace_all(str, len, "^3", "\x03");
	replace_all(str, len, "^4", "\x04");
	/*replace_all(str, len, "^5", "\x05");
	replace_all(str, len, "^6", "\x06");
	replace_all(str, len, "^7", "\x07");*/
	replace_all(str, len, "\t", " ");
	replace_all(str, len, "\r", "");
	replace_all(str, len, "\n", "");
}