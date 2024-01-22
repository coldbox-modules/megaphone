component {

    /**
     * The text of this text object.
     */
    property name="text" type="string";

    /**
     * Indicates whether emojis in a text field should be escaped into the colon emoji format.
     */
    property name="_emoji" type="boolean";

    /**
     * Create a new confirm object instance.
     */
    public PlainTextOnlyTextObject function init(
        required string text,
        numeric maxLength = 3000,
        numeric minLength = 1
    ) {
        if ( arguments.text.len() < arguments.minLength ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Text must be at least #arguments.minLength# #arguments.minLength == 1 ? "character" : "characters"# long."
            );
        }

        if ( arguments.text.len() > arguments.maxLength ) {
            arguments.text = left( arguments.text, arguments.maxLength - 3 ) & "...";
        }

        variables.text = arguments.text;

        return this;
    }

    /**
     * Set the title of the confirm object.
     */
    public PlainTextOnlyTextObject function emoji() {
        variables._emoji = true;
        return this;
    }

    public struct function getMemento() {
        var memento = { "type": "plain_text", "text": variables.text };

        if ( !isNull( variables._emoji ) ) {
            memento[ "emoji" ] = variables._emoji;
        }

        return memento;
    }

}
