component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "section block", () => {
            it( "can convert to a memento", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                expect( sectionBlock.getMemento() ).toBe( {
                    "type": "section",
                    "text": { "type": "plain_text", "text": "Location: 123 Main Street, New York, NY 10010" }
                } );
            } );

            it( "requires text or a field to be set", () => {
                var sectionBlock = newSectionBlock();
                expect( () => {
                    sectionBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "A section requires at least one block, or the text to be set."
                );
            } );

            it( "has a minimum text length of one", () => {
                var sectionBlock = newSectionBlock();
                expect( () => {
                    sectionBlock.text( "" );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Text must be at least 1 character long."
                );
            } );

            it( "truncates the text past 3000 characters", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.text( repeatString( "a", 3001 ) );
                expect( sectionBlock.getMemento() ).toBe( { "type": "section", "text": { "type": "plain_text", "text": repeatString( "a", 2997 ) & "..." } } );
            } );

            it( "can customize the text object", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.text( "Location: 123 Main Street, New York, NY 10010" ).markdown();
                expect( sectionBlock.getMemento() ).toBe( {
                    "type": "section",
                    "text": { "type": "mrkdwn", "text": "Location: 123 Main Street, New York, NY 10010" }
                } );
            } );

            it( "does not allow more than ten fields", () => {
                var sectionBlock = newSectionBlock();
                for ( var i = 1; i <= 11; i++ ) {
                    sectionBlock.field( "Field " & i );
                }
                expect( () => {
                    sectionBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "There is a maximum of 10 fields in each section block."
                );
            } );

            it( "truncates field text after 2000 characters", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.field( repeatString( "a", 2001 ) );
                expect( sectionBlock.getMemento() ).toBe( { "type": "section", "fields": [ { "type": "plain_text", "text": repeatString( "a", 1997 ) & "..." } ] } );
            } );

            it( "allows fields to be customized", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.field( "Location: 123 Main Street, New York, NY 10010" ).markdown();
                expect( sectionBlock.getMemento() ).toBe( {
                    "type": "section",
                    "fields": [ { "type": "mrkdwn", "text": "Location: 123 Main Street, New York, NY 10010" } ]
                } );
            } );

            it( "can manually specify the block id field", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                sectionBlock.id( "section1" );
                expect( sectionBlock.getMemento() ).toBe( {
                    "type": "section",
                    "text": { "type": "plain_text", "text": "Location: 123 Main Street, New York, NY 10010" },
                    "block_id": "section1"
                } );
            } );

            it( "has a block id maximum length of 255 characters", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                sectionBlock.id( repeatString( "a", 256 ) );

                expect( () => {
                    sectionBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the block_id field is 255 characters."
                );
            } );

            it( "can specify an accessory element", () => {
                var sectionBlock = newSectionBlock();
                sectionBlock.text( "Location: 123 Main Street, New York, NY 10010" );
                sectionBlock.accessory( newImageElement( "https://example.com/image.png", "Image" ) );
                expect( sectionBlock.getMemento() ).toBe( {
                    "type": "section",
                    "text": { "type": "plain_text", "text": "Location: 123 Main Street, New York, NY 10010" },
                    "accessory": { "type": "image", "image_url": "https://example.com/image.png", "alt_text": "Image" }
                } );
            } );
        } );
    }

    private SectionBlock function newSectionBlock() {
        return new root.models.Providers.Slack.BlockKit.Blocks.SectionBlock( argumentCollection = arguments );
    }

    private ImageElement function newImageElement() {
        return new root.models.Providers.Slack.BlockKit.Blocks.Elements.ImageElement( argumentCollection = arguments );
    }

}
