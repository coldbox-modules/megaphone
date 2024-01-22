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
     * The URL of the image to be displayed.
     *
     * Maximum length for this field is 3000 characters.
     */
    property name="imageUrl" type="string";

    /**
     * A plain-text summary of the image.
     *
     * This should not contain any markup. Maximum length for this field is 2000 characters.
     */
    property name="altText" type="string";

    /**
     * An optional title for the image in the form of a text object that can only be of type: plain_text.
     *
     * Maximum length for the text in this field is 2000 characters.
     */
    property name="_title" type="PlainTextOnlyTextObject";

    public ImageBlock function init( required string imageUrl, string altText = "" ) {
        if ( arguments.imageUrl.len() > 3000 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Maximum length for the url field is 3000 characters."
            );
        }
        variables.imageUrl = arguments.imageUrl;

        if ( arguments.altText.len() > 2000 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Maximum length for the alt field is 2000 characters."
            );
        }
        variables.altText = arguments.altText;

        return this;
    }

    /**
     * Set the block identifier.
     */
    public ImageBlock function id( required string id ) {
        variables.blockId = arguments.id;
        return this;
    }

    /**
     * Set the alt text for the image.
     */
    public ImageBlock function alt( required string altText ) {
        if ( arguments.altText.len() > 2000 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Maximum length for the alt_text field is 2000 characters."
            );
        }

        variables.altText = arguments.altText;

        return this;
    }

    /**
     * Set the title for the image.
     */
    public PlainTextOnlyTextObject function title( required string title ) {
        variables._title = new Elements.PlainTextOnlyTextObject( text = arguments.title, maxLength = 2000 );
        return variables._title;
    }

    public struct function getMemento() {
        if ( variables.altText.len() <= 0 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Alt text is required for an image block."
            );
        }

        var memento = { "type": "image", "image_url": variables.imageUrl, "alt_text": variables.altText };

        if ( !isNull( variables.blockId ) ) {
            if ( variables.blockId.len() > 255 ) {
                throw(
                    type = "Megaphone.Provider.SlackBlockException",
                    message = "Maximum length for the block_id field is 255 characters."
                );
            }
            memento[ "block_id" ] = variables.blockId;
        }

        if ( !isNull( variables._title ) ) {
            memento[ "title" ] = variables._title.getMemento();
        }

        return memento;
    }

}
