component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "slack message", () => {
            it( "can create a slack message", () => {
                var message = newSlackMessage();
                message
                    .to( "##random" )
                    .text( "One of your invoices has been paid!" )
                    .headerBlock( "Invoice Paid" )
                    .contextBlock( ( block ) => {
                        block.text( "Customer ##1234" );
                    } )
                    .sectionBlock( ( block ) => {
                        block.text( "An invoice has been paid." );
                        block.field( "*Invoice No:*#chr( 10 )#1000" ).markdown();
                        block.field( "*Invoice Recipient:*#chr( 10 )#eric@ortussolutions.com" ).markdown();
                    } )
                    .dividerBlock()
                    .sectionBlock( ( block ) => {
                        block.text( "Congratulations!" );
                    } );

                expect( message.getMemento() ).toBe( {
                    "channel": "##random",
                    "blocks": [
                        { "text": { "text": "Invoice Paid", "type": "plain_text" }, "type": "header" },
                        { "elements": [ { "text": "Customer ##1234", "type": "plain_text" } ], "type": "context" },
                        {
                            "fields": [
                                { "text": "*Invoice No:*#chr( 10 )#1000", "type": "mrkdwn" },
                                { "text": "*Invoice Recipient:*#chr( 10 )#eric@ortussolutions.com", "type": "mrkdwn" }
                            ],
                            "text": { "text": "An invoice has been paid.", "type": "plain_text" },
                            "type": "section"
                        },
                        { "type": "divider" },
                        { "text": { "text": "Congratulations!", "type": "plain_text" }, "type": "section" }
                    ],
                    "text": "One of your invoices has been paid!"
                } );
            } );
        } );
    }

    private SlackMessage function newSlackMessage() {
        return new root.models.Providers.Slack.BlockKit.SlackMessage( argumentCollection = arguments );
    }

}
