component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "actions block", () => {
            it( "can convert to a memento", () => {
                var actionsBlock = newActionsBlock();
                actionsBlock.button( "Example Button" );

                expect( actionsBlock.getMemento() ).toBe( {
                    "type": "actions",
                    "elements": [
                        {
                            "type": "button",
                            "text": { "type": "plain_text", "text": "Example Button" },
                            "action_id": "button_example-button"
                        }
                    ]
                } );
            } );

            it( "requires at least one element", () => {
                var actionsBlock = newActionsBlock();

                expect( () => {
                    actionsBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "There must be at least one element in each actions block."
                );
            } );

            it( "has a maximum of 25 elements", () => {
                var actionsBlock = newActionsBlock();
                for ( var i = 1; i <= 25; i++ ) {
                    actionsBlock.button( "Button #i#" );
                }

                expect( () => {
                    actionsBlock.button( "Button 26" );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "There is a maximum of 25 elements in each actions block."
                );
            } );

            it( "can add buttons", () => {
                var actionsBlock = newActionsBlock();
                actionsBlock.button( "Example Button" );
                actionsBlock.button( "Scary Button" ).danger();

                expect( actionsBlock.getMemento() ).toBe( {
                    "type": "actions",
                    "elements": [
                        {
                            "type": "button",
                            "text": { "type": "plain_text", "text": "Example Button" },
                            "action_id": "button_example-button"
                        },
                        {
                            "type": "button",
                            "text": { "type": "plain_text", "text": "Scary Button" },
                            "action_id": "button_scary-button",
                            "style": "danger"
                        }
                    ]
                } );
            } );

            it( "can manually specify the block id field", () => {
                var actionsBlock = newActionsBlock();
                actionsBlock.button( "Example Button" );
                actionsBlock.id( "actions1" );

                expect( actionsBlock.getMemento() ).toBe( {
                    "type": "actions",
                    "elements": [
                        {
                            "type": "button",
                            "text": { "type": "plain_text", "text": "Example Button" },
                            "action_id": "button_example-button"
                        }
                    ],
                    "block_id": "actions1"
                } );
            } );

            it( "has a block id maximum length of 255 characters", () => {
                var actionsBlock = newActionsBlock();
                actionsBlock.button( "Example Button" );
                actionsBlock.id( repeatString( "a", 256 ) );

                expect( () => {
                    actionsBlock.getMemento();
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Maximum length for the block_id field is 255 characters."
                );
            } );
        } );
    }

    private ActionsBlock function newActionsBlock() {
        return new root.models.Providers.Slack.BlockKit.Blocks.ActionsBlock( argumentCollection = arguments );
    }

}
