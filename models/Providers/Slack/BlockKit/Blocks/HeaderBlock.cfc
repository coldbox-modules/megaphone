component accessors="true" {

    /**
     * A string acting as a unique identifier for a block.
     *
     * If not specified, a block_id will be generated.
     *
     * You can use this block_id when you receive an interaction payload to identify the source of the action.
     */
    property name="blockId" type="string";

    /**
     * The text for the block, in the form of a plain_text text object.
     *
     * Maximum length for the text in this field is 150 characters.
     */
    property name="text" type="PlainTextOnlyTextObject";

    public HeaderBlock function init( required string text, function callback ) {
        variables.text = new Elements.PlainTextOnlyTextObject( text = arguments.text, maxLength = 150 );
        if ( !isNull( arguments.callback ) ) {
            arguments.callback( variables.text );
        }
        return this;
    }

    /**
     * Set the block identifier.
     */
    public HeaderBlock function id( required string id ) {
        variables.blockId = arguments.id;
        return this;
    }

    public struct function getMemento() {
        var memento = { "type": "header", "text": variables.text.getMemento() };

        if ( !isNull( variables.blockId ) ) {
            if ( variables.blockId.len() > 255 ) {
                throw(
                    type = "Megaphone.Provider.SlackBlockException",
                    message = "Maximum length for the block_id field is 255 characters."
                );
            }
            memento[ "block_id" ] = variables.blockId;
        }

        return memento;
    }

}
