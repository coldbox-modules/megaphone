component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "divider block", () => {
            it( "can convert to a memento", () => {
                var dividerBlock = newDividerBlock();

                expect( dividerBlock.getMemento() ).toBe( { "type": "divider" } );
            } );

            it( "can manually specify the block id field", () => {
                var dividerBlock = newDividerBlock();
                dividerBlock.id( "divider1" );

                expect( dividerBlock.getMemento() ).toBe( { "type": "divider", "block_id": "divider1" } );
            } );

            it( "has a block id maximum length of 255 characters", () => {
                var dividerBlock = newDividerBlock();
                dividerBlock.id( repeatString( "a", 256 ) );

                expect( () => {
                    dividerBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the block_id field is 255 characters."
                );
            } );
        } );
    }

    private DividerBlock function newDividerBlock() {
        return new root.models.Providers.Slack.BlockKit.Blocks.DividerBlock( argumentCollection = arguments );
    }

}
