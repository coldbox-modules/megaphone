component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "context block", () => {
            it( "can convert to a memento", () => {
                var contextBlock = newContextBlock();
                contextBlock.text( "Location: 123 Main Street, New York, NY 10010" );

                expect( contextBlock.getMemento() ).toBe( {
                    "type": "context",
                    "elements": [ { "type": "plain_text", "text": "Location: 123 Main Street, New York, NY 10010" } ]
                } );
            } );

            it( "requires at least one element", () => {
                var contextBlock = newContextBlock();

                expect( () => {
                    contextBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "There must be at least one element in each context block."
                );
            } );

            it( "has a maximum of 10 elements", () => {
                var contextBlock = newContextBlock();
                for ( var i = 1; i <= 10; i++ ) {
                    contextBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                }

                expect( () => {
                    contextBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "There is a maximum of 10 elements in each context block."
                );
            } );

            it( "can add image blocks", () => {
                var contextBlock = newContextBlock();
                contextBlock
                    .image( "https://image.freepik.com/free-photo/red-drawing-pin_1156-445.jpg" )
                    .alt( "images" );
                contextBlock.image( "http://placekitten.com/500/500", "An incredibly cute kitten." );

                expect( contextBlock.getMemento() ).toBe( {
                    "type": "context",
                    "elements": [
                        {
                            "type": "image",
                            "image_url": "https://image.freepik.com/free-photo/red-drawing-pin_1156-445.jpg",
                            "alt_text": "images"
                        },
                        {
                            "type": "image",
                            "image_url": "http://placekitten.com/500/500",
                            "alt_text": "An incredibly cute kitten."
                        }
                    ]
                } );
            } );

            it( "can add text blocks", () => {
                var contextBlock = newContextBlock();
                contextBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                contextBlock.text( "Description: **Bring your dog!**" ).markdown();

                expect( contextBlock.getMemento() ).toBe( {
                    "type": "context",
                    "elements": [
                        { "type": "plain_text", "text": "Location: 123 Main Street, New York, NY 10010" },
                        { "type": "mrkdwn", "text": "Description: **Bring your dog!**" }
                    ]
                } );
            } );

            it( "can manually specify the block id field", () => {
                var contextBlock = newContextBlock();
                contextBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                contextBlock.id( "context1" );

                expect( contextBlock.getMemento() ).toBe( {
                    "type": "context",
                    "elements": [ { "type": "plain_text", "text": "Location: 123 Main Street, New York, NY 10010" } ],
                    "block_id": "context1"
                } );
            } );

            it( "has a block id maximum length of 255 characters", () => {
                var contextBlock = newContextBlock();
                contextBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                contextBlock.id( repeatString( "a", 256 ) );

                expect( () => {
                    contextBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the block_id field is 255 characters."
                );
            } );
        } );
    }

    private ContextBlock function newContextBlock() {
        return new root.models.Providers.Slack.BlockKit.Blocks.ContextBlock( argumentCollection = arguments );
    }

}
