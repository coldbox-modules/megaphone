component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "header block", () => {
            it( "can convert to a memento", () => {
                var headerBlock = newHeaderBlock( "Budget Performance" );

                expect( headerBlock.getMemento() ).toBe( { "type": "header", "text": { "type": "plain_text", "text": "Budget Performance" } } );
            } );

            it( "truncates the heading text after 150 characters", () => {
                var headerBlock = newHeaderBlock( repeatString( "a", 151 ) );

                expect( headerBlock.getMemento() ).toBe( { "type": "header", "text": { "type": "plain_text", "text": repeatString( "a", 147 ) & "..." } } );
            } );

            it( "can manually specify the block id field", () => {
                var headerBlock = newHeaderBlock( "Budget Performance" );
                headerBlock.id( "header1" );

                expect( headerBlock.getMemento() ).toBe( {
                    "type": "header",
                    "text": { "type": "plain_text", "text": "Budget Performance" },
                    "block_id": "header1"
                } );
            } );

            it( "has a block id maximum length of 255 characters", () => {
                var headerBlock = newHeaderBlock( "Budget Performance" );
                headerBlock.id( repeatString( "a", 256 ) );

                expect( () => {
                    headerBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the block_id field is 255 characters."
                );
            } );
        } );
    }

    private HeaderBlock function newHeaderBlock() {
        return new root.models.Providers.Slack.BlockKit.Blocks.HeaderBlock( argumentCollection = arguments );
    }

}
