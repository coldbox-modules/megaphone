component {

    /**
     * The URL of the image to be displayed.
     */
    property name="imageUrl" type="string";

    /**
     * A plain-text summary of the image. This should not contain any markup.
     */
    property name="altText" type="string";

    /**
     * Create a new image element instance.
     */
    public ImageElement function init( required string imageUrl, string altText = "" ) {
        variables.imageUrl = arguments.imageUrl;
        variables.altText = arguments.altText;
        return this;
    }

    /**
     * Set the alt text for the image.
     */
    public ImageElement function alt( required string altText ) {
        variables.altText = arguments.altText;
        return this;
    }

    /**
     * Get the instance as an array.
     */
    public struct function getMemento() {
        if ( variables.altText.len() <= 0 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Alt text is required for an image element."
            );
        }

        return { "type": "image", "image_url": variables.imageUrl, "alt_text": variables.altText };
    }

}
