component accessors="true" {

    /**
     * A string acting as a unique identifier for a block.
     *
     * If not specified, a block_id will be generated.
     *
     * You can use this block_id when you receive an interaction payload to identify the source of the action.
     */
    property name="blockId" type="string";

    public DividerBlock function init() {
        return this;
    }

    /**
     * Set the block identifier.
     */
    public DividerBlock function id( required string id ) {
        variables.blockId = arguments.id;
        return this;
    }

    public struct function getMemento() {
        var memento = { "type": "divider" };

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
