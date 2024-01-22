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
     * The text for the block, in the form of a text object.
     *
     * Minimum length for the text in this field is 1 and maximum length is 3000 characters.
     *
     * This field is not required if a valid array of fields objects is provided instead.
     */
    property name="_text" type="PlainTextOnlyTextObject";

    /**
     * Required if no text is provided. An array of text objects.
     *
     * Any text objects included with fields will be rendered in a compact format
     * that allows for 2 columns of side-by-side text. Maximum number of items
     * is 10 while maximum item content length is capped at 2000 characters.
     */
    property name="fields" type="array";

    /**
     * One of the available element objects.
     */
    property name="_accessory" type="any";

    public SectionBlock function init() {
        variables.fields = [];
        return this;
    }

    /**
     * Set the block identifier.
     */
    public SectionBlock function id( required string id ) {
        variables.blockId = arguments.id;
        return this;
    }

    /**
     * Set the text for the block.
     */
    public TextObject function text( required string text ) {
        variables._text = new Elements.TextObject( text = arguments.text, maxLength = 3000 );
        return variables._text;
    }

    /**
     * Add a field to the block.
     */
    public TextObject function field( required string text ) {
        var field = new Elements.TextObject( text = arguments.text, maxLength = 2000 );
        variables.fields.append( field );
        return field;
    }

    /**
     * Set the accessory for the block.
     */
    public SectionBlock function accessory( required any element ) {
        variables._accessory = arguments.element;
        return this;
    }

    public struct function getMemento() {
        var memento = { "type": "section" };

        if ( isNull( variables._text ) && variables.fields.isEmpty() ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "A section requires at least one block, or the text to be set."
            );
        }

        if ( !isNull( variables._text ) ) {
            memento[ "text" ] = variables._text.getMemento();
        }

        if ( variables.fields.len() > 0 ) {
            if ( variables.fields.len() > 10 ) {
                throw(
                    type = "Megaphone.Provider.SlackBlockException",
                    message = "There is a maximum of 10 fields in each section block."
                );
            }
            memento[ "fields" ] = variables.fields.map( ( field ) => field.getMemento() );
        }

        if ( !isNull( variables._accessory ) ) {
            memento[ "accessory" ] = variables._accessory.getMemento();
        }

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
