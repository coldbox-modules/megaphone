component accessors="true" {

    /**
     * The channel to send the message on.
     */
    property name="channel" type="string";

    /**
     * The text content of the message.
     */
    property name="_text" type="string";

    /**
     * The message's blocks.
     */
    property name="blocks" type="array";

    /**
     * The user emoji icon for the message.
     */
    property name="_icon" type="string";

    /**
     * The user image icon for the message.
     */
    property name="_image" type="string";

    /**
     * The JSON metadata for the message.
     */
    property name="_metadata" type="struct";

    /**
     * Indicates if you want the message to parse markdown or not.
     */
    property name="parseMarkdown" type="boolean";

    /**
     * Indicates if you want a preview of links inlined in the message.
     */
    property name="_unfurlLinks" type="boolean";

    /**
     * Indicates if you want a preview of links to media inlined in the message.
     */
    property name="_unfurlMedia" type="boolean";

    /**
     * The username to send the message as.
     */
    property name="_username" type="string";

    public SlackMessage function init() {
        variables.blocks = [];
        return this;
    }

    public SlackMessage function to( required string channel ) {
        variables.channel = arguments.channel;
        return this;
    }

    public SlackMessage function text( required string text ) {
        variables._text = arguments.text;
        return this;
    }

    /**
     * Add a new Actions block to the message.
     */
    public SlackMessage function actionsBlock( required function callback ) {
        var block = new Blocks.ActionsBlock();
        arguments.callback( block );
        variables.blocks.append( block );
        return this;
    }

    /**
     * Add a new Context block to the message.
     */
    public SlackMessage function contextBlock( required function callback ) {
        var block = new Blocks.ContextBlock();
        arguments.callback( block );
        variables.blocks.append( block );
        return this;
    }

    /**
     * Add a new Divider block to the message.
     */
    public SlackMessage function dividerBlock() {
        var block = new Blocks.DividerBlock();
        variables.blocks.append( block );
        return this;
    }

    /**
     * Add a new Header block to the message.
     */
    public SlackMessage function headerBlock( required string text, function callback ) {
        var block = new Blocks.HeaderBlock( argumentCollection = arguments );
        variables.blocks.append( block );
        return this;
    }

    /**
     * Add a new Image block to the message.
     */
    public SlackMessage function imageBlock( required string imageUrl, string altText = "", function callback ) {
        var block = new Blocks.ImageBlock( arguments.imageUrl, arguments.altText );
        if ( !isNull( arguments.callback ) ) {
            arguments.callback( block );
        }
        variables.blocks.append( block );
        return this;
    }

    /**
     * Add a new Section block to the message.
     */
    public SlackMessage function sectionBlock( required function callback ) {
        var block = new Blocks.SectionBlock();
        arguments.callback( block );
        variables.blocks.append( block );
        return this;
    }

    public SlackMessage function emoji( required string icon ) {
        variables._icon = arguments.icon;
        variables._image = javacast( "null", "" );
        return this;
    }

    public SlackMessage function image( required string image ) {
        variables._image = arguments.image;
        variables._icon = javacast( "null", "" );
        return this;
    }

    /**
     * Set the metadata the message should include.
     */
    public SlackMessage function metadata( required string eventType, struct payload = {} ) {
        variables._metaData = new EventMetadata( arguments.eventType, arguments.payload );
        return this;
    }

    /**
     * Disable Slack's markup parsing.
     */
    public SlackMessage function disableMarkdownParsing() {
        variables.parseMarkdown = false;
        return this;
    }

    /**
     * Unfurl links for rich display.
     */
    public SlackMessage function unfurlLinks( boolean unfurlLinks = true ) {
        variables._unfurlLinks = arguments.unfurlLinks;
        return this;
    }

    /**
     * Unfurl media for rich display.
     */
    public SlackMessage function unfurlMedia( boolean unfurlMedia = true ) {
        variables._unfurlMedia = arguments.unfurlMedia;
        return this;
    }

    /**
     * Set the user name for the Slack bot.
     */
    public SlackMessage function username( required string username ) {
        variables._username = arguments.username;
        return this;
    }

    /**
     * Returns a JSON-encodable representation of the message.
     */
    public struct function getMemento() {
        if ( variables.blocks.isEmpty() && isNull( variables._text ) ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Slack messages must contain at least a text message or block."
            );
        }

        if ( variables.blocks.len() > 50 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Slack messages can only contain up to 50 blocks."
            );
        }

        var memento = {};

        if ( !isNull( variables.channel ) ) {
            memento[ "channel" ] = variables.channel;
        }

        if ( !isNull( variables._text ) ) {
            memento[ "text" ] = variables._text;
        }

        if ( !variables.blocks.isEmpty() ) {
            memento[ "blocks" ] = variables.blocks.map( ( block ) => block.getMemento() );
        }

        if ( !isNull( variables._icon ) ) {
            memento[ "icon_emoji" ] = variables._icon;
        }

        if ( !isNull( variables._image ) ) {
            memento[ "icon_url" ] = variables._image;
        }

        if ( !isNull( variables._metadata ) ) {
            memento[ "metadata" ] = variables._metadata.getMemento();
        }

        if ( !isNull( variables.parseMarkdown ) ) {
            memento[ "mrkdwn" ] = variables.parseMarkdown;
        }

        if ( !isNull( variables._unfurlLinks ) ) {
            memento[ "unfurl_links" ] = variables._unfurlLinks;
        }

        if ( !isNull( variables._unfurlMedia ) ) {
            memento[ "unfurl_media" ] = variables._unfurlMedia;
        }

        if ( !isNull( variables._username ) ) {
            memento[ "username" ] = variables._username;
        }

        return memento;
    }

    public void function dump(
        boolean raw = false,
        string output = "browser",
        string format = "html",
        boolean abort = false,
        string label = "",
        boolean metainfo = false,
        numeric top = 9999,
        string show = "",
        string hide = "",
        numeric keys = 9999,
        boolean expand = true,
        boolean showUDFs = true
    ) {
        if ( arguments.raw ) {
            writeDump(
                var = getMemento(),
                output = arguments.output,
                format = arguments.format,
                abort = arguments.abort,
                label = arguments.label,
                metainfo = arguments.metainfo,
                top = arguments.top,
                hide = arguments.hide,
                keys = arguments.keys,
                expand = arguments.expand,
                showUDFs = arguments.showUDFs
            );
            return;
        }

        var slackBuilderUrl = "https://app.slack.com/block-kit-builder##" & urlEncodedFormat(
            serializeJSON(
                getMemento().filter( ( key, value ) => !arrayContains( [ "username", "text", "channel" ], key ) )
            )
        );

        writeDump(
            var = slackBuilderUrl,
            output = arguments.output,
            format = arguments.format,
            abort = arguments.abort,
            label = arguments.label,
            metainfo = arguments.metainfo,
            top = arguments.top,
            show = arguments.show,
            hide = arguments.hide,
            keys = arguments.keys,
            expand = arguments.expand,
            showUDFs = arguments.showUDFs
        );
    }

    /**
     * Functional construct for if statements
     *
     * @target  The boolean evaluator, this can be a boolean value
     * @success The closure/lambda to execute if the boolean value is true
     * @failure The closure/lambda to execute if the boolean value is false
     *
     * @return Returns the SuperType object for chaining
     */
    public SlackMessage function when( required boolean target, required success, failure ) cbMethod {
        if ( arguments.target ) {
            arguments.success( this );
        } else if ( !isNull( arguments.failure ) ) {
            arguments.failure( this );
        }
        return this;
    }

}
