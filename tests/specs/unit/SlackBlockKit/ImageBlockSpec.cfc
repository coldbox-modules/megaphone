component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "image block", () => {
            it( "can convert to a memento", () => {
                var imageBlock = newImageBlock( "http://placekitten.com/500/500", "An incredibly cute kitten." );

                expect( imageBlock.getMemento() ).toBe( {
                    "type": "image",
                    "image_url": "http://placekitten.com/500/500",
                    "alt_text": "An incredibly cute kitten."
                } );
            } );

            it( "has a url maximum length of 3000 characters", () => {
                expect( () => {
                    newImageBlock( repeatString( "a", 3001 ) )
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the url field is 3000 characters."
                );
            } );

            it( "requires alt text", () => {
                var imageBlock = newImageBlock( "http://placekitten.com/500/500" );
                expect( () => {
                    imageBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Alt text is required for an image block."
                );
            } );

            it( "has an alt text maximum length of 2000 characters", () => {
                var imageBlock = newImageBlock( "http://placekitten.com/500/500" );
                expect( () => {
                    imageBlock.alt( repeatString( "a", 2001 ) );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the alt_text field is 2000 characters."
                );
            } );

            it( "can have a title", () => {
                var imageBlock = newImageBlock( "http://placekitten.com/500/500", "An incredibly cute kitten." );
                imageBlock.title( "This one is a cutesy kitten in a box." );

                expect( imageBlock.getMemento() ).toBe( {
                    "type": "image",
                    "image_url": "http://placekitten.com/500/500",
                    "alt_text": "An incredibly cute kitten.",
                    "title": { "type": "plain_text", "text": "This one is a cutesy kitten in a box." }
                } );
            } );

            it( "truncates the title field after 2000 characters", () => {
                var imageBlock = newImageBlock( "http://placekitten.com/500/500", "An incredibly cute kitten." );
                imageBlock.title( repeatString( "a", 2001 ) );

                expect( imageBlock.getMemento() ).toBe( {
                    "type": "image",
                    "image_url": "http://placekitten.com/500/500",
                    "alt_text": "An incredibly cute kitten.",
                    "title": { "type": "plain_text", "text": repeatString( "a", 1997 ) & "..." }
                } );
            } );

            it( "can manually specify the block id field", () => {
                var imageBlock = newImageBlock( "http://placekitten.com/500/500" );
                imageBlock.alt( "An incredibly cute kitten." );
                imageBlock.id( "actions1" );

                expect( imageBlock.getMemento() ).toBe( {
                    "type": "image",
                    "image_url": "http://placekitten.com/500/500",
                    "alt_text": "An incredibly cute kitten.",
                    "block_id": "actions1"
                } );
            } );

            it( "can manually specify the block id field", () => {
                var imageBlock = newImageBlock( "http://placekitten.com/500/500", "An incredibly cute kitten." );
                imageBlock.id( repeatString( "a", 256 ) );

                expect( () => {
                    imageBlock.getMemento()
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the block_id field is 255 characters."
                );
            } );
        } );
    }

    private ImageBlock function newImageBlock() {
        return new root.models.Providers.Slack.BlockKit.Blocks.ImageBlock( argumentCollection = arguments );
    }

}
