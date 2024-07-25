--This file is separate from strings.lua so that UTF-8 strings won't be in that file causing problems with encoding in certain editors.

-- TODO(dbriscoe): Generate this file from our strings so it's easier to add
-- new languages and for translators to update these translations.

local LANGUAGE = require "languages.langs"

STRINGS.PRETRANSLATED =
{
    LANGUAGES =
    {
        [LANGUAGE.ENGLISH] = "English",
        [LANGUAGE.FRENCH] = "Français (French)",
        [LANGUAGE.SPANISH] = "Español (Spanish)",
        [LANGUAGE.SPANISH_LA] = "Español - América Latina\n(Spanish - Latin America)",
        [LANGUAGE.GERMAN] = "Deutsch (German)",
        [LANGUAGE.ITALIAN] = "Italiano (Italian)",
        [LANGUAGE.PORTUGUESE_BR] = "Português (Portuguese)",
        [LANGUAGE.POLISH] = "Polski (Polish)",
        [LANGUAGE.RUSSIAN] = "Русский (Russian)",
        [LANGUAGE.KOREAN] = "한국어 (Korean)",
        [LANGUAGE.CHINESE_S] = "简体中文 (Simplified Chinese)",
        [LANGUAGE.UKRAINIAN] = "Українська (Ukrainian)",
    },

    LANGUAGES_TITLE =
    {
        [LANGUAGE.ENGLISH] = "Translation Option",
        [LANGUAGE.FRENCH] = "Option de traduction",
        [LANGUAGE.SPANISH] = "Opción de traducción",
        [LANGUAGE.SPANISH_LA] = "Opción de traducción",
        [LANGUAGE.GERMAN] = "Übersetzungsoption",
        [LANGUAGE.ITALIAN] = "Opzione di traduzione",
        [LANGUAGE.PORTUGUESE_BR] = "Opção de Tradução",
        [LANGUAGE.POLISH] = "Opcja tłumaczenia",
        [LANGUAGE.RUSSIAN] = "Вариант перевода",
        [LANGUAGE.KOREAN] = "번역 옵션",
        [LANGUAGE.CHINESE_S] = "语言设定",
        [LANGUAGE.UKRAINIAN] = "Варіант перекладу",
    },

	LANGUAGES_BODY =
    {
        [LANGUAGE.ENGLISH] = "Your interface language is set to English. Would you like to enable the translation for your language?",
        [LANGUAGE.FRENCH] = "Votre langue d'interface est définie sur Français. Voulez-vous activer la traduction pour votre langue?",
        [LANGUAGE.SPANISH] = "El idioma de la interfaz está configurado a español. ¿Quieres permitir la traducción a tu idioma?",
        [LANGUAGE.SPANISH_LA] = "El idioma de la interfaz está configurado a español. ¿Quieres permitir la traducción a tu idioma?",
        [LANGUAGE.GERMAN] = "Deine Sprache ist auf Deutsch eingestellt. Möchtest du die Übersetzung für deine Sprache aktivieren?",
        [LANGUAGE.ITALIAN] = "La lingua dell'interfaccia è impostata su italiano. Vorresti abilitare la traduzione per la tua lingua?",
        [LANGUAGE.PORTUGUESE_BR] = "O idioma da interface está definido como português. Gostaria de habilitar a tradução para o seu idioma?",
        [LANGUAGE.POLISH] = "Język interfejsu został określony jako: polski. Czy życzysz sobie włączyć tłumaczenie na twój język?",
        [LANGUAGE.RUSSIAN] = "В качестве языка интерфейса выбран русский. Вам требуется перевод на ваш язык?",
        [LANGUAGE.KOREAN] = "인터페이스 언어가 한국어로 설정되어 있습니다. 해당 언어의 번역을 사용 하시겠습니까?",
        [LANGUAGE.CHINESE_S] = "是否把语言设定为中文？",
        [LANGUAGE.UKRAINIAN] = "В якості мови інтерфейсу вибрана українська. Вам потрібен переклад на вашу мову?",
    },

	LANGUAGES_YES =
    {
        [LANGUAGE.ENGLISH] = "Yes",
        [LANGUAGE.FRENCH] = "Oui",
        [LANGUAGE.SPANISH] = "Sí",
        [LANGUAGE.SPANISH_LA] = "Sí",
        [LANGUAGE.GERMAN] = "Ja",
        [LANGUAGE.ITALIAN] = "Sì",
        [LANGUAGE.PORTUGUESE_BR] = "Sim",
        [LANGUAGE.POLISH] = "Tak",
        [LANGUAGE.RUSSIAN] = "Да",
        [LANGUAGE.KOREAN] = "예",
        [LANGUAGE.CHINESE_S] = "是",
        [LANGUAGE.UKRAINIAN] = "Так",
    },

	LANGUAGES_NO =
    {
        [LANGUAGE.ENGLISH] = "No",
        [LANGUAGE.FRENCH] = "Non",
        [LANGUAGE.SPANISH] = "No",
        [LANGUAGE.SPANISH_LA] = "No",
        [LANGUAGE.GERMAN] = "Nein",
        [LANGUAGE.ITALIAN] = "No",
        [LANGUAGE.PORTUGUESE_BR] = "Não",
        [LANGUAGE.POLISH] = "Nie",
        [LANGUAGE.RUSSIAN] = "Нет",
        [LANGUAGE.KOREAN] = "아니",
        [LANGUAGE.CHINESE_S] = "否",
        [LANGUAGE.UKRAINIAN] = "Ні",
    },
}

if Platform.IsConsole() then
	STRINGS.PRETRANSLATED.LANGUAGES[LANGUAGE.SPANISH] = "Español - España\n(Spanish - Spain)"
end
