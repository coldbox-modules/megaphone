component extends="tests.resources.ModuleIntegrationSpec" {

    property name="megaphone" inject="NotificationService@megaphone";
    property name="binder" inject="wirebox:binder";

    function beforeAll() {
        super.beforeAll();
        variables.slackProvider = variables.megaphone.getChannels().slack;
        addMatchers( "hyper.models.TestBoxMatchers" );
        addMatchers( {
            "toHaveBeenSentToSlack": function( expectation, args = {} ) {
                expect( variables.slackProvider.getClient() ).toHaveSentRequest( ( req ) => {
                    expect( req.getFullUrl() ).toBe( "https://slack.com/api/chat.postMessage" );
                    expect( req.getHeader( "Authorization" ) ).toBe( "Bearer fake-token" );
                    expect( req.getHeader( "Content-Type" ) ).toBe( "application/json" );
                    expect( req.getBody() ).toBe( expectation.actual );

                    return true;
                } );

                return true;
            }
        } );
    }

    function run() {
        describe( "slack notification provider", () => {
            beforeEach( () => {
                variables.slackProvider
                    .getClient()
                    .fake( {
                        "https://slack.com/api/chat.postMessage": ( newFakeResponse, req ) => {
                            if ( req.getHeader( "Authorization" ) != "Bearer fake-token" ) {
                                return newFakeResponse(
                                    401,
                                    "Unauthorized",
                                    serializeJSON( { "ok": false, "error": "invalid_auth" } )
                                );
                            }

                            return newFakeResponse(
                                201,
                                "Created",
                                serializeJSON( {
                                    "ok": true,
                                    "channel": req.getBody().channel,
                                    "ts": "1503435956.000247",
                                    "message": {
                                        "text": "Here's a message for you",
                                        "username": "ecto1",
                                        "bot_id": "B123ABC456",
                                        "attachments": [
                                            {
                                                "text": "This is an attachment",
                                                "id": 1,
                                                "fallback": "This is an attachment's fallback"
                                            }
                                        ],
                                        "type": "message",
                                        "subtype": "bot_message",
                                        "ts": "1503435956.000247"
                                    }
                                } )
                            );
                        }
                    } )
                    .preventStrayRequests();
            } );

            afterEach( () => {
                variables.slackProvider.getClient().clearFakes();
            } );

            it( "throws an exception if hyper is not installed", () => {
                var hyperMapping = variables.binder.getMapping( "HyperBuilder@hyper" );
                try {
                    variables.binder.unmap( "HyperBuilder@hyper" );
                    expect( () => {
                        variables.wirebox.getInstance(
                            "SlackProvider@megaphone",
                            { "name": "slack", "properties": { "token": "foo" } }
                        );
                    } ).toThrow( type = "Megaphone.Provider.MissingDependency" );
                } finally {
                    variables.binder.setMapping( "HyperBuilder@hyper", hyperMapping );
                }
            } );

            it( "requires a token to be set", () => {
                expect( () => {
                    variables.wirebox.getInstance( "SlackProvider@megaphone", { "name": "slack", "properties": {} } );
                } ).toThrow(
                    type = "Megaphone.Provider.MissingProperty",
                    regex = "You must provide a `token` to use the SlackProvider."
                );

                expect( () => {
                    variables.wirebox.getInstance(
                        "SlackProvider@megaphone",
                        { "name": "slack", "properties": { "token": "" } }
                    );
                } ).toThrow(
                    type = "Megaphone.Provider.MissingProperty",
                    regex = "You must provide a `token` to use the SlackProvider."
                );
            } );

            it( "can send a basic message", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information."
                } ).toHaveBeenSentToSlack();
            } );

            it( "throws an exception when no text or blocks are defined", () => {
                expect( () => {
                    sendTestNotification( ( message ) => {
                        message.to( "##general" );
                    } );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Slack messages must contain at least a text message or block."
                );
            } );

            it( "throws an exception when more than 50 blocks are defined", () => {
                expect( () => {
                    sendTestNotification( ( message ) => {
                        for ( var i = 1; i <= 51; i++ ) {
                            message.dividerBlock();
                        }
                    } );
                } ).toThrow(
                    type = "Megaphone.Provider.SlackBlockException",
                    regex = "Slack messages can only contain up to 50 blocks."
                );
            } );

            it( "throws an exception when the slack credentials are invalid", () => {
                expect( () => {
                    sendTestNotification(
                        callback = ( message ) => {
                            message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                        },
                        routeToken = "invalid-token"
                    );
                } ).toThrow(
                    type = "Megaphone.Provider.ProviderError",
                    regex = "Slack API call failed with error \[invalid_auth\]."
                );
            } );

            it( "can set a channel for the message", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.to( "##random" );
                } );

                expect( {
                    "channel": "##random",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information."
                } ).toHaveBeenSentToSlack();
            } );

            it( "can route to a channel on the notifiable", () => {
                sendTestNotification(
                    callback = ( message ) => {
                        message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    },
                    routeChannel = "##support"
                );

                expect( {
                    "channel": "##support",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information."
                } ).toHaveBeenSentToSlack();
            } );

            it( "can use an emoji as the icon for the message", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.image( "emoji-overrides-image-url-automatically-according-to-spec" ).emoji( ":tada:" );
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "icon_emoji": ":tada:"
                } ).toHaveBeenSentToSlack();
            } );

            it( "can use an image as the icon for the message", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message
                        .emoji( "auto-clearing-as-to-prefer-image-since-its-called-after" )
                        .image( "http://lorempixel.com/48/48" );
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "icon_url": "http://lorempixel.com/48/48"
                } ).toHaveBeenSentToSlack();
            } );

            it( "can include metadata", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.metadata( "task_created", { "id": "11223", "title": "Redesign Homepage" } );
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "metadata": {
                        "event_type": "task_created",
                        "event_payload": { "id": "11223", "title": "Redesign Homepage" }
                    }
                } ).toHaveBeenSentToSlack();
            } );

            it( "can disable slack markdown parsing", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.disableMarkdownParsing();
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "mrkdwn": false
                } ).toHaveBeenSentToSlack();
            } );

            it( "can unfurl links", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.unfurlLinks();
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "unfurl_links": true
                } ).toHaveBeenSentToSlack();
            } );

            it( "can unfurl media", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.unfurlMedia();
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "unfurl_media": true
                } ).toHaveBeenSentToSlack();
            } );

            it( "can set the bot username", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.username( "megaphonebot" );
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "username": "megaphonebot"
                } ).toHaveBeenSentToSlack();
            } );

            it( "can contain both blocks and a fallback text", () => {
                sendTestNotification( ( message ) => {
                    message.text( "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information." );
                    message.dividerBlock();
                } );

                expect( {
                    "channel": "##general",
                    "text": "This is a simple Web API text message. See https://api.slack.com/reference/messaging/payload for more information.",
                    "blocks": [ { "type": "divider" } ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "can contain action blocks", () => {
                sendTestNotification( ( message ) => {
                    message.actionsBlock( ( actions ) => {
                        actions
                            .button( "Cancel" )
                            .value( "cancel" )
                            .id( "button_1" );
                    } );
                } );

                expect( {
                    "channel": "##general",
                    "blocks": [
                        {
                            "type": "actions",
                            "elements": [
                                {
                                    "type": "button",
                                    "text": { "type": "plain_text", "text": "Cancel" },
                                    "action_id": "button_1",
                                    "value": "cancel"
                                }
                            ]
                        }
                    ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "can contain context blocks", () => {
                sendTestNotification( ( message ) => {
                    message.contextBlock( ( context ) => {
                        context
                            .image( "https://image.freepik.com/free-photo/red-drawing-pin_1156-445.jpg" )
                            .alt( "images" );
                    } );
                } );

                expect( {
                    "channel": "##general",
                    "blocks": [
                        {
                            "type": "context",
                            "elements": [
                                {
                                    "type": "image",
                                    "image_url": "https://image.freepik.com/free-photo/red-drawing-pin_1156-445.jpg",
                                    "alt_text": "images"
                                }
                            ]
                        }
                    ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "can contain divider blocks", () => {
                sendTestNotification( ( message ) => {
                    message.dividerBlock();
                } );

                expect( { "channel": "##general", "blocks": [ { "type": "divider" } ] } ).toHaveBeenSentToSlack();
            } );

            it( "can contain header blocks", () => {
                sendTestNotification( ( message ) => {
                    message.headerBlock( "Budget Performance" );
                } );

                expect( {
                    "channel": "##general",
                    "blocks": [ { "type": "header", "text": { "type": "plain_text", "text": "Budget Performance" } } ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "can contain image blocks", () => {
                sendTestNotification( ( message ) => {
                    message.imageBlock(
                        imageUrl = "http://placekitten.com/500/500",
                        callback = ( imageBlock ) => {
                            imageBlock.alt( "An incredibly cute kitten." );
                        }
                    );
                } );

                expect( {
                    "channel": "##general",
                    "blocks": [
                        {
                            "type": "image",
                            "image_url": "http://placekitten.com/500/500",
                            "alt_text": "An incredibly cute kitten."
                        }
                    ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "can contain section blocks", () => {
                sendTestNotification( ( message ) => {
                    message.sectionBlock( ( sectionBlock ) => {
                        sectionBlock.text( "A message *with some bold text* and _some italicized text_." ).markdown();
                    } );
                } );

                expect( {
                    "channel": "##general",
                    "blocks": [
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": "A message *with some bold text* and _some italicized text_."
                            }
                        }
                    ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "can add blocks conditionally with the when helper", () => {
                sendTestNotification( ( message ) => {
                    message
                        .when( true, ( m ) => {
                            m.sectionBlock( ( sectionBlock ) => {
                                sectionBlock.text( "I *will* be included." ).markdown();
                            } );
                        } )
                        .when( false, ( m ) => {
                            m.sectionBlock( ( sectionBlock ) => {
                                sectionBlock.text( "I *won't* be included." ).markdown();
                            } );
                        } )
                        .when(
                            false,
                            ( m ) => {
                                m.sectionBlock( ( sectionBlock ) => {
                                    sectionBlock.text( "I'm *not* included either..." ).markdown();
                                } );
                            },
                            ( m ) => {
                                m.sectionBlock( ( sectionBlock ) => {
                                    sectionBlock.text( "But I *will* be included!" ).markdown();
                                } );
                            }
                        );
                } );

                expect( {
                    "channel": "##general",
                    "blocks": [
                        { "type": "section", "text": { "type": "mrkdwn", "text": "I *will* be included." } },
                        { "type": "section", "text": { "type": "mrkdwn", "text": "But I *will* be included!" } }
                    ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "submits blocks in the order they were defined", () => {
                sendTestNotification( ( message ) => {
                    message.headerBlock( "Budget Performance" );
                    message.sectionBlock( ( sectionBlock ) => {
                        sectionBlock.text( "A message *with some bold text* and _some italicized text_." ).markdown();
                    } );
                    message.headerBlock( "Market Performance" );
                } );

                expect( {
                    "channel": "##general",
                    "blocks": [
                        { "type": "header", "text": { "type": "plain_text", "text": "Budget Performance" } },
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": "A message *with some bold text* and _some italicized text_."
                            }
                        },
                        { "type": "header", "text": { "type": "plain_text", "text": "Market Performance" } }
                    ]
                } ).toHaveBeenSentToSlack();
            } );

            it( "can submit a notification using a struct instead of a SlackMessage", () => {
                variables.megaphone.notify(
                    newTestNotifiable( "##general", "fake-token" ),
                    wirebox.getInstance( "TestRawSlackNotification" )
                );

                expect( {
                    "channel": "##general",
                    "blocks": [
                        { "type": "header", "text": { "type": "plain_text", "text": "Budget Performance" } },
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": "A message *with some bold text* and _some italicized text_."
                            }
                        },
                        { "type": "header", "text": { "type": "plain_text", "text": "Market Performance" } }
                    ]
                } ).toHaveBeenSentToSlack();
            } );
        } );
    }

    private any function sendTestNotification(
        required function callback,
        string routeChannel = "##general",
        string routeToken = "fake-token"
    ) {
        variables.megaphone.notify(
            newTestNotifiable( arguments.routeChannel, arguments.routeToken ),
            wirebox.getInstance( "TestSlackNotification" ).setCallback( arguments.callback )
        );

        return this;
    }

    private struct function newTestNotifiable( string routeChannel = "##general", string routeToken = "fake-token" ) {
        return {
            "getNotifiableId": () => 1,
            "getNotifiableType": () => "user",
            "routeNotificationForSlack": ( newSlackRoute ) => newSlackRoute( routeChannel, routeToken )
        };
    }

}
