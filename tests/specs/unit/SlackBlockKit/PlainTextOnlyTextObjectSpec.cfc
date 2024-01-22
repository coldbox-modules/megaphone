component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "plain text only text object", () => {
            it( "can convert to a memento", () => {
                var ptoto = newPTOTO( "A message *with some bold text* and _some italicized text_." );
                expect( ptoto.getMemento() ).toBe( { "type": "plain_text", "text": "A message *with some bold text* and _some italicized text_." } );
            } );

            it( "has a minimum length of 1 character", () => {
                expect( () => {
                    newPTOTO( "" );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Text must be at least 1 character long."
                );
            } );

            it( "truncates the text when over 3000 characters", () => {
                var ptoto = newPTOTO( repeatString( "a", 3001 ) );
                expect( ptoto.getMemento() ).toBe( { "type": "plain_text", "text": repeatString( "a", 2997 ) & "..." } );
            } );

            it( "can indicate that emojis should be escaped into the colon emoji format", () => {
                var ptoto = newPTOTO( "Spooky time! 👻" );
                ptoto.emoji();
                expect( ptoto.getMemento() ).toBe( { "type": "plain_text", "text": "Spooky time! 👻", "emoji": true } );
            } );
        } );
    }

    private PlainTextOnlyTextObject function newPTOTO() {
        return new root.models.Providers.Slack.BlockKit.Blocks.Elements.PlainTextOnlyTextObject(
            argumentCollection = arguments
        );
    }

}
