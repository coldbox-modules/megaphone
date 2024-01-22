component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "image element", () => {
            it( "can convert an image element to a memento", () => {
                var imageElement = newImageElement( "http://placekitten.com/700/500", "Multiple cute kittens" );
                expect( imageElement.getMemento() ).toBe( { "type": "image", "image_url": "http://placekitten.com/700/500", "alt_text": "Multiple cute kittens" } );
            } );

            it( "requires alt text when converting to a memento", () => {
                var imageElement = newImageElement( "http://placekitten.com/700/500" );
                expect( () => {
                    imageElement.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Alt text is required for an image element."
                );
            } );

            it( "allows alt text to be supplied after instantiation", () => {
                var imageElement = newImageElement( "http://placekitten.com/700/500" );
                imageElement.alt( "Multiple cute kittens" );
                expect( imageElement.getMemento() ).toBe( { "type": "image", "image_url": "http://placekitten.com/700/500", "alt_text": "Multiple cute kittens" } );
            } );
        } );
    }

    private ImageElement function newImageElement() {
        return new root.models.Providers.Slack.BlockKit.Blocks.Elements.ImageElement( argumentCollection = arguments );
    }

}
