component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "button element", () => {
            it( "can convert a button element to a memento", () => {
                var buttonElement = newButtonElement( "Click me" );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me"
                } );
            } );

            it( "truncates the button text after 75 characters", () => {
                var buttonElement = newButtonElement( repeatString( "a", 250 ) );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": repeatString( "a", 72 ) & "..." },
                    "action_id": "button_" & repeatString( "a", 248 )
                } );
            } );

            it( "can customize the button text", () => {
                var buttonElement = newButtonElement( "Click me", ( textObject ) => {
                    textObject.emoji();
                } );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me", "emoji": true },
                    "action_id": "button_click-me"
                } );
            } );

            it( "can customize the button action id", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.id( "my_custom_id" );
                expect( buttonElement.getMemento() ).toBe( { "type": "button", "text": { "type": "plain_text", "text": "Click me" }, "action_id": "my_custom_id" } );
            } );

            it( "throws an exception for action id values over 255 characters", () => {
                expect( () => {
                    var buttonElement = newButtonElement( "Click me" );
                    buttonElement.id( repeatString( "a", 256 ) );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the action_id field is 255 characters."
                );
            } );

            it( "can have a url", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.url( "https://www.ortussolutions.com" );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me",
                    "url": "https://www.ortussolutions.com"
                } );
            } );

            it( "throws an exception for url values over 3000 characters", () => {
                expect( () => {
                    var buttonElement = newButtonElement( "Click me" );
                    buttonElement.url( repeatString( "a", 3001 ) );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the url field is 3000 characters."
                );
            } );

            it( "can have a value", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.value( "click_me_123" );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me",
                    "value": "click_me_123"
                } );
            } );

            it( "throws an exception for value values over 2000 characters", () => {
                expect( () => {
                    var buttonElement = newButtonElement( "Click me" );
                    buttonElement.value( repeatString( "a", 2001 ) );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the value field is 2000 characters."
                );
            } );

            it( "can have the primary style", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.primary();
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me",
                    "style": "primary"
                } );
            } );

            it( "can have the danger style", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.danger();
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me",
                    "style": "danger"
                } );
            } );

            it( "can have a confirmation dialog", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.confirm( "This will do some thing." ).deny( "Yikes!" );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me",
                    "confirm": {
                        "title": { "type": "plain_text", "text": "Are you sure?" },
                        "text": { "type": "plain_text", "text": "This will do some thing." },
                        "confirm": { "type": "plain_text", "text": "Yes" },
                        "deny": { "type": "plain_text", "text": "Yikes!" }
                    }
                } );
            } );

            it( "can customized a confirmation dialog", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.confirm( "This will do some thing.", ( dialog ) => {
                    dialog.deny( "Yikes!" );
                    dialog.confirm( "Woohoo!" );
                } );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me",
                    "confirm": {
                        "title": { "type": "plain_text", "text": "Are you sure?" },
                        "text": { "type": "plain_text", "text": "This will do some thing." },
                        "confirm": { "type": "plain_text", "text": "Woohoo!" },
                        "deny": { "type": "plain_text", "text": "Yikes!" }
                    }
                } );
            } );

            it( "can have a an accessibility label", () => {
                var buttonElement = newButtonElement( "Click me" );
                buttonElement.accessibilityLabel( "Click Me Button" );
                expect( buttonElement.getMemento() ).toBe( {
                    "type": "button",
                    "text": { "type": "plain_text", "text": "Click me" },
                    "action_id": "button_click-me",
                    "accessibility_label": "Click Me Button"
                } );
            } );

            it( "throws an exception for accessibility label values over 75 characters", () => {
                expect( () => {
                    var buttonElement = newButtonElement( "Click me" );
                    buttonElement.accessibilityLabel( repeatString( "a", 76 ) );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the accessibility label is 75 characters."
                );
            } );
        } );
    }

    private ButtonElement function newButtonElement() {
        return new root.models.Providers.Slack.BlockKit.Blocks.Elements.ButtonElement( argumentCollection = arguments );
    }

}
