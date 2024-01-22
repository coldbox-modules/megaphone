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
     * An array of image elements and text objects.
     *
     * There is a maximum of 10 elements in each action block.
     */
    property name="elements" type="array";

    public ContextBlock function init() {
        variables.elements = [];
        return this;
    }

    /**
     * Set the block identifier.
     */
    public ContextBlock function id( required string id ) {
        variables.blockId = arguments.id;
        return this;
    }

    /**
     * Add an image element to the block.
     */
    public ImageElement function image( required string imageUrl, string altText = "" ) {
        return addElement( new Elements.ImageElement( arguments.imageUrl, arguments.altText ) );
    }

    /**
     * Add a text element to the block.
     */
    public TextObject function text( required string text ) {
        return addElement( new Elements.TextObject( arguments.text ) );
    }

    private any function addElement( required any element ) {
        if ( variables.elements.len() >= 10 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "There is a maximum of 10 elements in each context block."
            );
        }
        variables.elements.append( arguments.element );
        return arguments.element;
    }

    public struct function getMemento() {
        if ( variables.elements.isEmpty() ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "There must be at least one element in each context block."
            );
        }

        if ( variables.elements.len() > 10 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "There is a maximum of 10 elements in each context block."
            );
        }

        var memento = { "type": "context", "elements": variables.elements.map( ( element ) => element.getMemento() ) };

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
