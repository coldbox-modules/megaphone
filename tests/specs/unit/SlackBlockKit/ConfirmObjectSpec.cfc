component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "plain text only text object", () => {
            it( "can convert to a memento", () => {
                var confirmObject = newConfirmObject();
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": "No" }
                } );
            } );

            it( "has a customizable title field", () => {
                var confirmObject = newConfirmObject();
                confirmObject.title( "This is a custom title." );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "This is a custom title." },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": "No" }
                } );
            } );

            it( "truncates the title after 100 characters", () => {
                var confirmObject = newConfirmObject();
                confirmObject.title( repeatString( "a", 101 ) );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": repeatString( "a", 97 ) & "..." },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": "No" }
                } );
            } );

            it( "has a customizable text field", () => {
                var confirmObject = newConfirmObject();
                confirmObject.text( "This is some custom text." );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": "This is some custom text." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": "No" }
                } );
            } );

            it( "truncates the title after 300 characters", () => {
                var confirmObject = newConfirmObject();
                confirmObject.text( repeatString( "a", 301 ) );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": repeatString( "a", 297 ) & "..." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": "No" }
                } );
            } );

            it( "has a customizable confirm field", () => {
                var confirmObject = newConfirmObject();
                confirmObject.confirm( "Custom confirmation button." );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": "Custom confirmation button." },
                    "deny": { "type": "plain_text", "text": "No" }
                } );
            } );

            it( "truncates the confirm field after 30 characters", () => {
                var confirmObject = newConfirmObject();
                confirmObject.confirm( repeatString( "a", 31 ) );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": repeatString( "a", 27 ) & "..." },
                    "deny": { "type": "plain_text", "text": "No" }
                } );
            } );

            it( "can set the color scheme to danger", () => {
                var confirmObject = newConfirmObject();
                confirmObject.danger();
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": "No" },
                    "style": "danger"
                } );
            } );

            it( "has a customizable deny field", () => {
                var confirmObject = newConfirmObject();
                confirmObject.deny( "Custom deny button." );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": "Custom deny button." }
                } );
            } );

            it( "truncates the deny field after 30 characters", () => {
                var confirmObject = newConfirmObject();
                confirmObject.deny( repeatString( "a", 31 ) );
                expect( confirmObject.getMemento() ).toBe( {
                    "title": { "type": "plain_text", "text": "Are you sure?" },
                    "text": { "type": "plain_text", "text": "Please confirm this action." },
                    "confirm": { "type": "plain_text", "text": "Yes" },
                    "deny": { "type": "plain_text", "text": repeatString( "a", 27 ) & "..." }
                } );
            } );
        } );
    }

    private ConfirmObject function newConfirmObject() {
        return new root.models.Providers.Slack.BlockKit.Blocks.Elements.ConfirmObject( argumentCollection = arguments );
    }

}
