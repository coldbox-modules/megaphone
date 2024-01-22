component {

    /**
     * A text object that defines the button's text.
     *
     * Can only be of type: plain_text. Text may truncate with ~30 characters.
     *
     * Maximum length for the text in this field is 75 characters.
     */
    property name="text" type="PlainTextOnlyTextObject";

    /**
     * An identifier for this action.
     *
     * You can use this when you receive an interaction payload to identify the source of the action.
     *
     * Should be unique among all other action_ids in the containing block.
     *
     * Maximum length for this field is 255 characters.
     */
    property name="actionId" type="string";

    /**
     * A URL to load in the user's browser when the button is clicked.
     *
     * Maximum length for this field is 3000 characters. If you're using a URL, you will still
     * receive an interaction payload and will need to send an acknowledgement response.
     *
     * @link https://api.slack.com/interactivity/handling#payloads
     * @link https://api.slack.com/interactivity/handling#acknowledgment_response
     */
    property name="linkUrl" type="string";

    /**
     * The value to send along with the interaction payload.
     *
     * Maximum length for this field is 2000 characters.
     */
    property name="_value" type="string";

    /**
     * Decorates buttons with alternative visual color schemes. Use this option with restraint.
     *
     * - primary gives buttons a green outline and text, ideal for affirmation or confirmation actions.
     *   primary should only be used for one button within a set.
     *
     * - danger gives buttons a red outline and text, and should be used when the action is destructive.
     *   Use danger even more sparingly than primary.
     *
     * - If you don't include this field, the default button style will be used.
     */
    property name="style" type="string";

    /**
     * A confirm object that defines an optional confirmation dialog after the button is clicked.
     */
    property name="_confirm" type="ConfirmObject";

    /**
     * A label for longer descriptive text about a button element.
     *
     * This label will be read out by screen readers instead of the button text object.
     *
     * Maximum length for this field is 75 characters.
     */
    property name="_accessibilityLabel" type="string";

    /**
     * Create a new button element instance.
     */
    public ButtonElement function init( required string text, function callback ) {
        variables.text = new PlainTextOnlyTextObject( text = arguments.text, maxLength = 75 );
        variables.id( "button_" & lCase( slugify( left( arguments.text, 248 ) ) ) );

        if ( !isNull( arguments.callback ) ) {
            arguments.callback( variables.text );
        }

        return this;
    }

    /**
     * Set the URL for the button.
     */
    public ButtonElement function url( required string linkUrl ) {
        if ( arguments.linkUrl.len() > 3000 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Maximum length for the url field is 3000 characters."
            );
        }

        variables.linkUrl = arguments.linkUrl;

        return this;
    }

    /**
     * Set the action ID for the button.
     */
    public ButtonElement function id( required string id ) {
        if ( arguments.id.len() > 255 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Maximum length for the action_id field is 255 characters."
            );
        }

        variables.actionId = arguments.id;

        return this;
    }

    /**
     * Set the value for the button.
     */
    public ButtonElement function value( required string value ) {
        if ( arguments.value.len() > 2000 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Maximum length for the value field is 2000 characters."
            );
        }

        variables._value = arguments.value;

        return this;
    }

    /**
     * Set the style for the button to primary.
     */
    public ButtonElement function primary() {
        variables.style = "primary";
        return this;
    }

    /**
     * Set the style for the button to danger.
     */
    public ButtonElement function danger() {
        variables.style = "danger";
        return this;
    }

    /**
     * Set the confirm object for the button.
     */
    public ConfirmObject function confirm( required string text, function callback ) {
        variables._confirm = new ConfirmObject( arguments.text );

        if ( !isNull( arguments.callback ) ) {
            arguments.callback( variables._confirm );
        }

        return variables._confirm;
    }

    /**
     * Set the accessibility label for the button.
     */
    public ButtonElement function accessibilityLabel( required string label ) {
        if ( arguments.label.len() > 75 ) {
            throw(
                type = "Megaphone.Provider.SlackBlockException",
                message = "Maximum length for the accessibility label is 75 characters."
            );
        }

        variables._accessibilityLabel = arguments.label;

        return this;
    }

    public struct function getMemento() {
        var memento = { "type": "button", "text": variables.text.getMemento(), "action_id": variables.actionId };

        if ( !isNull( variables.linkUrl ) ) {
            memento[ "url" ] = variables.linkUrl;
        }

        if ( !isNull( variables._value ) ) {
            memento[ "value" ] = variables._value;
        }

        if ( !isNull( variables.style ) ) {
            memento[ "style" ] = variables.style;
        }

        if ( !isNull( variables._confirm ) ) {
            memento[ "confirm" ] = variables._confirm.getMemento();
        }

        if ( !isNull( variables._accessibilityLabel ) ) {
            memento[ "accessibility_label" ] = variables._accessibilityLabel;
        }

        return memento;
    }

    private string function slugify( required string str, string delimiter = "-" ) {
        return arrayToList( words( arguments.str ).map( ( w ) => lCase( w ) ), arguments.delimiter );
    }

    private array function words( required string str ) {
        return listToArray( addSpaceBetweenCapitalLetters( reReplace( str, "[\_\-\.]", " ", "ALL" ) ), " " );
    }

    private string function addSpaceBetweenCapitalLetters( required string str ) {
        return reReplace(
            arguments.str,
            "([A-Z])",
            " \1",
            "all"
        );
    }

}
