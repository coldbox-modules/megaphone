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
     * An array of interactive element objects - buttons, select menus, overflow menus, or date pickers.
     *
     * There is a maximum of 25 elements in each action block.
     */
    property name="elements" type="array";

    public ActionsBlock function init() {
        variables.elements = [];
        return this;
    }

    /**
     * Set the block identifier.
     */
    public ActionsBlock function id( required string id ) {
        variables.blockId = arguments.id;
        return this;
    }

    /**
     * Add a button element to the block.
     */
    public ButtonElement function button( required string text ) {
        return addElement( new Elements.ButtonElement( arguments.text ) );
    }

    private any function addElement( required any element ) {
        if ( variables.elements.len() >= 25 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "There is a maximum of 25 elements in each actions block."
            );
        }
        variables.elements.append( arguments.element );
        return arguments.element;
    }

    public struct function getMemento() {
        if ( variables.elements.isEmpty() ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "There must be at least one element in each actions block."
            );
        }

        if ( variables.elements.len() > 25 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "There is a maximum of 25 elements in each actions block."
            );
        }

        var memento = { "type": "actions", "elements": variables.elements.map( ( element ) => element.getMemento() ) };

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
