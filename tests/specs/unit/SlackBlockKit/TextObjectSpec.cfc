component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "text object", () => {
            it( "can convert to a memento", () => {
                var textObject = newTextObject( "A message *with some bold text* and _some italicized text_." );
                expect( textObject.getMemento() ).toBe( { "type": "plain_text", "text": "A message *with some bold text* and _some italicized text_." } );
            } );

            it( "can be a markdown text field", () => {
                var textObject = newTextObject( "A message *with some bold text* and _some italicized text_." );
                textObject.markdown();
                expect( textObject.getMemento() ).toBe( { "type": "mrkdwn", "text": "A message *with some bold text* and _some italicized text_." } );
            } );

            it( "has a minimum length of 1 character", () => {
                expect( () => {
                    newTextObject( "" );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Text must be at least 1 character long."
                );
            } );

            it( "truncates the text when over 3000 characters", () => {
                var textObject = newTextObject( repeatString( "a", 3001 ) );
                expect( textObject.getMemento() ).toBe( { "type": "plain_text", "text": repeatString( "a", 2997 ) & "..." } );
            } );

            it( "can indicate that emojis should be escaped into the colon emoji format", () => {
                var textObject = newTextObject( "Spooky time! 👻" );
                textObject.emoji();
                expect( textObject.getMemento() ).toBe( { "type": "plain_text", "text": "Spooky time! 👻", "emoji": true } );
            } );

            it( "cannot indicate that emojis should be escaped into the colon emoji format when using markdown formatting", () => {
                var textObject = newTextObject( "Spooky time! 👻" );
                textObject.markdown().emoji();
                expect( textObject.getMemento() ).toBe( { "type": "mrkdwn", "text": "Spooky time! 👻" } );
            } );

            it( "can indicate that auto conversion into clickable anchors should be skipped", () => {
                var textObject = newTextObject( "A message *with some bold text* and _some italicized text_." );
                textObject.markdown().verbatim();
                expect( textObject.getMemento() ).toBe( {
                    "type": "mrkdwn",
                    "text": "A message *with some bold text* and _some italicized text_.",
                    "verbatim": true
                } );
            } );

            it( "cannot indicate that auto conversion into clickable anchors should be skipped when using plain text formatting", () => {
                var textObject = newTextObject( "A message *with some bold text* and _some italicized text_." );
                textObject.verbatim();
                expect( textObject.getMemento() ).toBe( { "type": "plain_text", "text": "A message *with some bold text* and _some italicized text_." } );
            } );
        } );
    }

    private TextObject function newTextObject() {
        return new root.models.Providers.Slack.BlockKit.Blocks.Elements.TextObject( argumentCollection = arguments );
    }

}
