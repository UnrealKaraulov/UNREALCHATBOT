# UNREALCHATBOT
Плагин - чат бот для AMXMODX, версия alpha тест.

Конфиг с разнообразными настройками и поддержкой множественных API, для стабильной работы длительное время.

Приветсвие игроков на сервере и общение с чат ботом.

![image](https://github.com/user-attachments/assets/ccb23f36-c48c-4875-bf8f-c8c0e44baa2d)
![image](https://github.com/user-attachments/assets/2c52a66e-5eed-4924-a128-3ed70f4d324a)
![image](https://github.com/user-attachments/assets/c771b367-d7a9-40f4-8bd5-bb30047eb75d)
![image](https://github.com/user-attachments/assets/6a6a413c-83a3-4fe2-8a04-5e9fdf69d6b1)

Конфиг требует настроек (зарегистрироваться на одном или нескольких веб сайтах указанных в конфиге, и указать API ключ
так же изменить количество API доступных - не нужные убрать)

Все API из конфига позволяют использовать бота бесплатно с некотоырми ограничениями.

В случае ошибки API автоматически переключается на следующий.


Пример конфига

```
[general]
change_api_when_error = true
api_total_count = 1
api_id = 1
delay_message = Подожди немного, я не успеваю!
join_message = Привет, я ```[username]```! Сообщи о моем приходе на сервер!
; 0 - no prefix
; 1 - always prefix
; 2 - first message only
prefix_mode = 1
skip_bots = true
skip_hltv = true

[API_1]
bot_chatprefix = ^4[GPT]: 
flood_delay = 2.5
api_system_promt = Language: Russian. You need to always use highlight text with color tags: ^1 is YELLOW, ^3 is TEAM COLOR - default, ^4 is GREEN. Team colors ^5 is RED ^6 is GREY ^7 is BLUE and setup at message start. Your name is 'UnrealBot'. Answer more than 4077 characters – make it shorter. Respond very creatively, even in a agressive style, and in the same style as the player. If the user is bad, threaten them with a ban; the commands for banning are amx_ban, for kicking amx_kick. Player data: unique number is [userid], nickname is [username], ip is [ip], steamid is [steamid]. Hide a couple of digits in the IP and SteamID if you write them. Язык ответов - русский. No repeat answers.
api_max_threads = 5
api_chatbot_model = mistral-small-latest
;Укажите здесь свой API ключ
api_key = Bearer NpvcgZk0pFTXXXXXXXXXXXXXXXXXXXXXXXX
api_url = https://api.mistral.ai/v1/chat/completions
api_history_count = 40
```

Более наглядный пример https://github.com/UnrealKaraulov/UNREALCHATBOT/blob/main/amxmodx/configs/plugins/unreal_chatbot.cfg.ini

Для сообщения боту напишите в чат `/gpt текст` или в консоль `say /gpt текст`.
